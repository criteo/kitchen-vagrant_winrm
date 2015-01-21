require 'fileutils'
require 'rubygems/version'
require 'kitchen'
require 'tempfile'

module Kitchen

  module Driver

    # VagrantWinrm driver for Kitchen.
    #
    # @author Baptiste Courtois <b.courtois@criteo.com>
    class VagrantWinrm < Base

      default_config :communicator, :winrm
      default_config :custom_settings, {}
      default_config :customize, {
        vrde: 'on',
        vrdeport: '5000-5100',
        vrdeauthtype: 'null',
      }
      default_config :guest, :windows
      default_config :network, []
      default_config :pre_create_command, nil
      default_config :require_chef_omnibus, false
      default_config :synced_folders, []
      default_config :provision, false

      default_config :vagrantfile_erb,
        File.join(File.dirname(__FILE__), '../../../templates/Vagrantfile.erb')

      default_config :provider,
        ENV.fetch('VAGRANT_DEFAULT_PROVIDER', 'virtualbox')

      default_config :vm_hostname do |driver|
        driver.instance.name
      end

      default_config :box do |driver|
        "opscode-#{driver.instance.platform.name}"
      end

      required_config :box

      no_parallel_for :create, :destroy

      def create(state)
        create_vagrantfile
        run_pre_create_command
        cmd = 'vagrant up'
        cmd += ' --no-provision' unless config[:provision]
        cmd += " --provider=#{config[:provider]}" if config[:provider]
        run cmd
        info("Vagrant instance #{instance.to_str} created.")
        state[:created] = true
      end

      def converge(state)
        create_vagrantfile
        provisioner = instance.provisioner
        provisioner.create_sandbox

        run_remote provisioner.install_command
        run_remote provisioner.init_command

        sandbox_path = provisioner.sandbox_path
        root_path = provisioner[:root_path]

        debug("Uploading #{sandbox_path} to #{root_path} through WinRM")
        run "vagrant winrm-upload -c '#{sandbox_path}' '#{root_path}'"

        run_remote provisioner.prepare_command
        run_remote provisioner.run_command
      ensure
        provisioner && provisioner.cleanup_sandbox
      end

      def setup(state)
        create_vagrantfile
        run_remote busser.setup_cmd
      end

      def verify(state)
        create_vagrantfile
        run_remote busser.sync_cmd
        run_remote busser.run_cmd
      end

      def destroy(state)
        return unless state[:created]

        create_vagrantfile
        @vagrantfile_created = false
        run 'vagrant destroy -f'
        FileUtils.rm_rf(vagrant_root)
        info("Vagrant instance #{instance.to_str} destroyed.")
        state.delete(:created)
      end

      def verify_dependencies
        check_vagrant_version
        check_vagrant_winrm_version
      end

      def instance=(instance)
        @instance = instance
        resolve_config!
      end

      protected
      WEBSITE = 'http://downloads.vagrantup.com/'
      VAGRANT_MIN_VER = '1.6.0'
      VAGRANT_WINRM_MIN_VER = '0.4.0'

      def run_remote(cmd)
        return unless cmd

        debug("Executing winRM command #{cmd}")
        tmp = ::Tempfile.new(['script', '.sh'])
        begin
          tmp << cmd
          tmp.close

          remote_script = run "vagrant winrm-upload -t '#{tmp.path}'"
          run "vagrant winrm -c 'sh \"#{remote_script}\"'"
        ensure
          tmp.close
          tmp.unlink
        end
      end

      def run(cmd, options = {})
        cmd = "echo #{cmd}" if config[:dry_run]
        run_command(cmd, { :cwd => vagrant_root }.merge(options))
      end

      def silently_run(cmd)
        run_command(cmd,
          :live_stream => nil, :quiet => logger.debug? ? false : true)
      end

      def run_pre_create_command
        if config[:pre_create_command]
          run(config[:pre_create_command], :cwd => config[:kitchen_root])
        end
      end

      def vagrant_root
        @vagrant_root ||= File.join(
          config[:kitchen_root], %w{.kitchen kitchen-vagrant}, instance.name
        )
      end

      def create_vagrantfile
        return if @vagrantfile_created

        finalize_synced_folder_config

        vagrantfile = File.join(vagrant_root, 'Vagrantfile')
        debug("Creating Vagrantfile for #{instance.to_str} (#{vagrantfile})")
        FileUtils.mkdir_p(vagrant_root)
        File.open(vagrantfile, 'wb') { |f| f.write(render_template) }
        debug_vagrantfile(vagrantfile)
        @vagrantfile_created = true
      end

      def finalize_synced_folder_config
        config[:synced_folders].map! do |source, destination, options|
          [
            File.expand_path(
              source.gsub("%{instance_name}", instance.name),
              config[:kitchen_root]
            ),
            destination.gsub("%{instance_name}", instance.name),
            options || 'nil'
          ]
        end
      end

      def render_template
        if File.exists?(template)
          ERB.new(IO.read(template)).result(binding).gsub(%r{^\s*$\n}, '')
        else
          raise ActionFailed, "Could not find Vagrantfile template #{template}"
        end
      end

      def template
        File.expand_path(config[:vagrantfile_erb], config[:kitchen_root])
      end

      def debug_vagrantfile(vagrantfile)
        if logger.debug?
          debug('------------')
          IO.read(vagrantfile).each_line { |l| debug(l.chomp) }
          debug('------------')
        end
      end

      def resolve_config!
        unless config[:vagrantfile_erb].nil?
          config[:vagrantfile_erb] =
            File.expand_path(config[:vagrantfile_erb], config[:kitchen_root])
        end
        unless config[:pre_create_command].nil?
          config[:pre_create_command] =
            config[:pre_create_command].gsub('{{vagrant_root}}', vagrant_root)
        end
      end

      def vagrant_version
        version_string = silently_run('vagrant --version')
        version_string = version_string.chomp.split(' ').last
      rescue Errno::ENOENT
        raise UserError, <<-EOS
Vagrant #{VAGRANT_MIN_VER} or higher is not installed.
Please download a package from #{WEBSITE}.
EOS
      end

      def check_vagrant_version
        version = vagrant_version
        if Gem::Version.new(version) < Gem::Version.new(VAGRANT_MIN_VER)
          raise UserError, <<-EOS
Detected an old version of Vagrant (#{version}).
Please upgrade to version #{VAGRANT_MIN_VER} or higher from #{WEBSITE}.
EOS
        end
      end

      def vagrant_winrm_version
        silently_run('vagrant winrm --plugin-version').chomp.split(' ').last
      rescue Errno::ENOENT
        raise UserError,
          "Vagrant-winrm #{VAGRANT_WINRM_MIN_VER} or higher is not installed."
      end

      def check_vagrant_winrm_version
        version = vagrant_winrm_version
        if Gem::Version.new(version) < Gem::Version.new(VAGRANT_WINRM_MIN_VER)
          raise UserError, <<-EOS
Detected an old version of Vagrant-winrm (#{version}).
Please upgrade to version #{VAGRANT_WINRM_MIN_VER} or higher.
EOS
        end
      end
    end
  end
end
