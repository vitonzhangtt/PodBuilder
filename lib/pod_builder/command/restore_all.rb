require 'pod_builder/core'

module PodBuilder
  module Command
    class RestoreAll
      def self.call(options)
        unless Configuration.restore_enabled
          raise "Restore not enabled!".red
        end
  
        Configuration.check_inited
        PodBuilder::prepare_basepath

        begin
          File.rename(PodBuilder::basepath("Podfile"), PodBuilder::basepath("Podfile.tmp2"))
          File.rename(PodBuilder::basepath("Podfile.restore"), PodBuilder::basepath("Podfile"))

          ARGV << "*"
          options[:skip_prebuild_update] = true
          return Command::Build::call(options)
        rescue Exception => e
          raise e
        ensure
          FileUtils.rm_f(PodBuilder::basepath("Podfile.restore"))
          File.rename(PodBuilder::basepath("Podfile"), PodBuilder::basepath("Podfile.restore"))
          File.rename(PodBuilder::basepath("Podfile.tmp2"), PodBuilder::basepath("Podfile"))
        end

        return -1
      end
    end
  end
end
