class Runner
  include MessageLogger
  @@silent = false

  def self.execute! options
    @@silent = options[:silent]
    begin
      _log "\nExecuting task named #{options[:name]} on #{options[:server].name}..\n", :color => :blue
      options[:server].__with_connection_for(options[:address]) do |ssh|
        options[:commands].each do |command|
          ret = run_command(command, ssh, options)
          break if ret != 0 and command[:abort_on_fail] == true
        end
      end
    rescue Net::SSH::AuthenticationFailed => e
      raise Net::SSH::AuthenticationFailed, "Authentication failed for server named #{server.name}.  Please check your authentication credentials."
    ensure
      _log "\nComplete\n", :color => :blue
    end
    options[:commands] # for tests
  end

  def self.execute_locally! options
    @@silent = options[:silent]
    _log "\n*** BEGIN executing local task #{options[:name]}\n", :color => :blue
    options[:commands].each do |command|
      command[:stdout] = ret = `#{command[:command]}`
      
      if $?.to_i == 0
        _log "    I: (local):  #{command[:command]}\n", :color => :blue
        _log("    O: (local):  #{ret}\n", :color => :blue) unless ret.nil? or ret == ""
      else
        _log "    I: (local):  #{command[:command]}\n", :color => :blue
        _errorlog("    O: (local):  #{ret}\n", :color => :red) unless ret.nil? or ret == ""
        _errorlog("    E: (local): #{command[:command]} return exit code: #{$?}\n", :color => :red) if $? != 0
      end
    end
    _log "\n*** END executing local task #{options[:name]}\n", :color => :blue
    options[:commands]
  end

  private

  def self.run_command(command, ssh, options)
    case command[:type]
    when :remote
      stdout, stderr, exit_code, exit_signal = ssh_exec! ssh, command[:command]
      command[:stdout] = stdout
      command[:stderr] = stderr
      command[:exit_code] = exit_code
      if exit_code == 0
        _log(".", :color => :green)
      else
        _errorlog("\n    E: (#{options[:address]}): #{command[:command]} return exit code: #{exit_code}\n", :color => :red) if exit_code != 0
      end
      return exit_code
    when :local
      ret = `#{command[:command]}`
      command[:stdout] = ret
      if $?.to_i == 0
        _log(".", :color => :green)
      else
        _errorlog("\n    E: (local): #{command[:command]} return exit code: #{$?}\n", :color => :red) if $? != 0
      end
      return $?
    when :scp
      putc "."
      options[:server].__upload_to!(options[:address], command[:local], command[:remote])

      # this will need to be improved to allow for :onfailure
      return 0
    when :block
      command[:block].call
    end
  end

  # courtesy of flitzwald on stackoverflow
  # http://stackoverflow.com/questions/3386233/how-to-get-exit-status-with-rubys-netssh-library
  def self.ssh_exec!(ssh, command)
    stdout_data = ""
    stderr_data = ""
    exit_code = nil
    exit_signal = nil
    ssh.open_channel do |channel|
      channel.exec(command) do |ch, success|
        channel.on_data do |ch,data|
          stdout_data+=data
        end
  
        channel.on_extended_data do |ch,type,data|
          stderr_data+=data
        end
  
        channel.on_request("exit-status") do |ch,data|
          exit_code = data.read_long
        end
  
        channel.on_request("exit-signal") do |ch, data|
          exit_signal = data.read_long
        end
      end
    end
    ssh.loop
    [stdout_data, stderr_data, exit_code, exit_signal]
  end

  def self._log(message, options)
    return if @@silent == true
    log(message, options)
  end

  def self._errorlog(message, options)
    return if @@silent == true
    errorlog(message, options)
  end
end
