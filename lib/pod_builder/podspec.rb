module PodBuilder
  class Podspec
    def self.generate(all_buildable_items, analyzer)  
      unless all_buildable_items.count > 0
        return
      end
      
      puts "Generating PodBuilder's local podspec".yellow
                  
      platform = analyzer.instance_variable_get("@result").targets.first.platform
      generate_podspec_from(all_buildable_items, platform)
    end

    def self.include?(pod_name)
      return File.exists?(PodBuilder::prebuiltpath("#{pod_name}.podspec"))
    end
    
    private

    def self.generate_spec_keys_for(item, name, all_buildable_items)
      vendored_frameworks = item.vendored_frameworks + ["#{item.module_name}.framework"]
      existing_vendored_frameworks = vendored_frameworks.select { |t| File.exist?(PodBuilder::prebuiltpath(t) || "") }
      existing_vendored_frameworks_basename = vendored_frameworks.map { |t| File.basename(t) }.select { |t| File.exist?(PodBuilder::prebuiltpath(t) || "") }
      vendored_frameworks = (existing_vendored_frameworks + existing_vendored_frameworks_basename).uniq
      
      vendored_libraries = item.vendored_libraries
      existing_vendored_libraries = vendored_libraries.map { |t| "#{item.module_name}/#{t}" }.select { |t| File.exist?(PodBuilder::prebuiltpath(t) || "") }
      existing_vendored_libraries_basename = vendored_libraries.map { |t| File.basename("#{item.module_name}/#{t}") }.select { |t| File.exist?(PodBuilder::prebuiltpath(t) || "") }
      vendored_libraries = (existing_vendored_libraries + existing_vendored_libraries_basename).uniq

      # .a are static libraries and should not be included again in the podspec to prevent duplicated symbols (in the app and in the prebuilt framework)
      vendored_libraries.select! { |t| !t.end_with?(".a") }

      frameworks = all_buildable_items.select { |t| vendored_frameworks.include?("#{t.module_name}.framework") }.uniq
      static_frameworks = frameworks.select { |x| x.is_static }

      resources = static_frameworks.map { |x| x.vendored_framework_path.nil? ? nil : "#{x.vendored_framework_path}/*.{nib,bundle,xcasset,strings,png,jpg,tif,tiff,otf,ttf,ttc,plist,json,caf,wav,p12,momd}" }.compact.flatten.uniq
      exclude_files = static_frameworks.map { |x| x.vendored_framework_path.nil? ? nil : "#{x.vendored_framework_path}/Info.plist" }.compact.flatten.uniq
      exclude_files += frameworks.map { |x| x.vendored_framework_path.nil? ? nil : "#{x.vendored_framework_path}/#{Configuration.framework_plist_filename}" }.compact.flatten.uniq.sort
      
      indentation = "    "
      if name.nil?
        spec_name = "p"
        podspec = ""
      else
        spec_name = "s"
        podspec = "    p.subspec '#{name}' do |#{spec_name}|\n"
        indentation += "    "
      end

      if vendored_frameworks.count > 0
        podspec += "#{indentation}#{spec_name}.vendored_frameworks = '#{vendored_frameworks.uniq.sort.join("','")}'\n"
      end      
      if vendored_libraries.count > 0
        podspec += "#{indentation}#{spec_name}.vendored_libraries = '#{vendored_libraries.uniq.sort.join("','")}'\n"
      end
      if item.frameworks.count > 0
        podspec += "#{indentation}#{spec_name}.frameworks = '#{item.frameworks.uniq.sort.join("', '")}'\n"
      end
      if item.libraries.count > 0
        podspec += "#{indentation}#{spec_name}.libraries = '#{item.libraries.uniq.sort.join("', '")}'\n"
      end
      if resources.count > 0
        podspec += "#{indentation}#{spec_name}.resources = '#{resources.uniq.sort.join("', '")}'\n"
      end
      if exclude_files.count > 0
        podspec += "#{indentation}#{spec_name}.exclude_files = '#{exclude_files.uniq.sort.join("', '")}'\n"
      end
      if item.xcconfig.keys.count > 0
        xcconfig = Hash.new
        item.xcconfig.each do |k, v|
          unless v != "$(inherited)"
            xcconfig[k] = item.xcconfig[k]
            next
          end
          unless k == "OTHER_LDFLAGS"
            next # For the time being limit to OTHER_LDFLAGS key
          end

          if podspec_values = item.xcconfig[k]
            podspec_values_arr = podspec_values.split(" ")
            podspec_values_arr.push(v)
            v = podspec_values_arr.join(" ")          
          end
          
          xcconfig[k] = item.xcconfig[k]
        end

        if xcconfig.keys.count > 0 
          podspec += "#{indentation}#{spec_name}.xcconfig = #{xcconfig.to_s}\n"
        end
      end

      deps = item.dependency_names.sort
      if name.nil?
        deps.select! { |t| t.split("/").first != item.root_name }
      end

      if deps.count > 0
        if podspec.count("\n") > 1
          podspec += "\n"
        end
        deps.each do |dependency|
          podspec += "#{indentation}#{spec_name}.dependency '#{dependency}'\n"
        end
      end
      
      if !name.nil?
        podspec += "    end\n"  
      end

      return podspec, vendored_frameworks.count > 0
    end

    def self.generate_podspec_from(all_buildable_items, platform)
      specs = Dir.glob(PodBuilder::prebuiltpath("*.podspec"))
      specs.each do |s| 
        FileUtils.rm(s)
      end

      all_buildable_items.each do |item|  
        if item.name != item.root_name
          if all_buildable_items.map(&:name).include?(item.root_name)
            next # will process root spec, skip subspecs
          end
        end

        podspec = "Pod::Spec.new do |p|\n"

        podspec += "    p.name             = '#{item.root_name}'\n"
        podspec += "    p.version          = '#{item.version}'\n"
        podspec += "    p.summary          = '#{item.summary.gsub("'", "\\'")}'\n"
        podspec += "    p.homepage         = '#{item.homepage}'\n"
        podspec += "    p.author           = 'PodBuilder'\n"
        podspec += "    p.source           = { 'git' => '#{item.source['git']}'}\n"
        podspec += "    p.license          = { :type => '#{item.license}' }\n"

        podspec += "\n"
        podspec += "    p.#{platform.safe_string_name.downcase}.deployment_target  = '#{platform.deployment_target.version}'\n"
        podspec += "\n"

        main_keys, valid = generate_spec_keys_for(item, nil, all_buildable_items)
        if !valid
          next
        end

        podspec += main_keys

        subspec_names = item.dependency_names.select { |t| t.start_with?("#{item.root_name}/") }
        subspec_names += all_buildable_items.map(&:name).select { |t| t.start_with?("#{item.root_name}/") }
        subspec_names.uniq!
        subspec_names.sort!
  
        subspec_names.each do |subspec|
          name = subspec.split("/").last

          if subspec_item = all_buildable_items.detect { |t| t.name == subspec }
            podspec += "\n"
            
            subspec_keys, valid = generate_spec_keys_for(subspec_item, name, all_buildable_items) 
            podspec += subspec_keys
          end
        end

        podspec += "end"

        spec_path = PodBuilder::prebuiltpath("#{item.root_name}.podspec")
        File.write(spec_path, podspec)
      end
    end
  end
end