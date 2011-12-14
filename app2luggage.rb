#!/usr/bin/ruby
#
#   Copyright 2010 Joe Block <jpb@ApesSeekingKnowledge.net>
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
#   Additional modifications contributed by the following people in no particular order : 
#    -  Henri Shustak
#
#   Version History : 
#       v1.0 - Initial release.
#       v1.1 - Added an option which provides automatic removal of the appliaction prior to installation.
#       v1.2 - Minor bug fix relating to working directories which contain spaces.
#       v1.3 - Added an option which when enabled will instruct the installer to not install if the application is found on target system.
#
#   Minor bug fix relating to directories which contain spaces added by Henri Shustak 2011
#
# If this breaks your system, you get to keep the parts.

require 'ftools'
require 'rubygems'

begin
  require 'trollop'
rescue LoadError
  puts "app2luggage.rb requires the trollop gem"
  puts "do 'sudo gem install trollop' and try again."
  exit 1
end

def generateMakefile()
  rawMakefile =<<"END_MAKEFILE"
#
# Package #{$installed_app}
#
# Makefile generated by app2luggage.rb
#

include #{$opts[:luggage_path]}

TITLE=#{$package_id}
REVERSE_DOMAIN=#{$opts[:reverse_domain]}
PAYLOAD=\\
	pack-script-preflight \\
	install-app2luggage-#{$app_name}


install-app2luggage-#{$app_name}: l_Applications #{$tarball_name}
	@sudo ${TAR} xjf #{$tarball_name} -C ${WORK_D}/Applications
	@sudo chown -R root:admin "${WORK_D}/Applications/#{$installed_app}"

END_MAKEFILE
  if File.exist?('./Makefile') then
    puts "there's already a Makefile here. Bailing out."
    exit 3
  else
    File.open("Makefile", "w") do |content|
      content.write(rawMakefile)
    end
  end
end

def generatePreflight()
    if $opts[:remove_exisiting_version] then
        
        rawPreflight =<<"END_PREFLIGHT"
#!/usr/bin/env bash
# Automatically generated preflight script to remove 
# the application prior to installation of with this
# package.
if [ -e "$3/Applications/#{$installed_app}" ] ; then
    rm -Rf "$3/Applications/#{$installed_app}"
    exit ${?}
fi
exit 0

END_PREFLIGHT
    else
        # GUI will just exit with error - as there is some issue with InstallationCheck and VolumeCheck picking up the target volume information
        if $opts[:no_overwrite] then
            rawPreflight =<<"END_PREFLIGHT"
#!/bin/bash
# Automatically generated preflight script which
# will return -1 if the application to install is found within
# the target drives /Application directory.
if [ -e "$3/Applications/#{$installed_app}" ] ; then
    `logger -s -i -t Installer "Application \"#{$installed_app}\" is already installed on system. This package will not overwrite the currently installed version."`
    exit -1
fi
exit 0

END_PREFLIGHT
        else
            rawPreflight =<<"END_PREFLIGHT"
#!/bin/bash
# Automatically generated preflight script which
# will not do anything but return success.
exit 0

END_PREFLIGHT
        end
end
  if File.exist?('./preflight') then
    puts "there's already a preflight script here. Bailing out."
    exit 3
  else
    File.open("preflight", "w") do |content|
      content.write(rawPreflight)
      `chmod 755 "./preflight"`
    end
  end
end


def clean_name(name)
  # get rid of toxic spaces
  cleaned = name.gsub(' ','_')
  return cleaned
end

def bundleApplication()
  app_dir = File.dirname($opts[:application])
  # spaces are toxic.
  scratch_tarball = "#{$app_name}.#{$build_date}.tar"
  if $opts[:debug] >= 10
    puts "app_name: #{$app_name}"
    puts "app_dir: #{app_dir}"
    puts "tarball_name: #{$tarball_name}"
  end
  # check for a pre-existing tarball so we don't step on existing files
  if File.exist?("#{$app_name}.tar.bz2")
    print "#{$app_name}.tar.bz2 already exists. Skipping tarball creation."
    return
  end
  if File.exist?("#{$app_name}.tar")
    print "#{$app_name}.tar already exists. Skipping tarball creation."
    return
  end
  # Use Apple's tar so we don't get bitten by resource forks. We only care
  # because on 10.6 they started stashing compressed binaries there. Yay.
  `/usr/bin/tar cf "#{scratch_tarball}" -C "#{app_dir}" "#{File.basename($opts[:application])}"`
  `bzip2 -9v "#{scratch_tarball}"`
end

$opts = Trollop::options do
  version "app2luggage 0.1 (c) 2010 Joe Block"
  banner <<-EOS
Automagically wrap an Application into a tar.bz2 and spew out a Luggage-compatible Makefile.
Usage:
       app2luggage [options] --application=AppName.app

where [options] are:
EOS

  opt :application, "Application to package", :type => String
  opt :create_tarball, "Create tarball for app", :default => true
  opt :debug, "Set debug level", :default => 0
  opt :directory_name, "Directory to put Makefile, tarball & dmg into", :type => String
  opt :luggage_path, "path to luggage.make", :type => String, :default => "/usr/local/share/luggage/luggage.make"
  opt :make_dmg, "Create dmg after creating subdir", :default => true
  opt :make_pkg, "Create pkg file after creating subdir", :default => false
  opt :package_id, "Package id (no spaces!)", :type => String
  opt :package_version, "Package version (numeric!)", :type => :int
  opt :remove_exisiting_version, "Remove the previous version of the application prior to installation", :default => false
  opt :no_overwrite, "Only install if previous version of the application was not found within target volume \"/Applications/\" directory", :default => false
  opt :reverse_domain, "Your domain in reverse format, eg com.example.corp", :type => String
end

# Sanity check args
Trollop::die :application, "#{$opts[:application]} must exist" unless File.exist?($opts[:application]) if $opts[:application]
Trollop::die :application, "must specify an application to package" if $opts[:application] == nil
Trollop::die :luggage_path, "#{$opts[:luggage_path]} doesn't exist" unless File.exist?($opts[:luggage_path]) if $opts[:luggage_path]
Trollop::die :package_id, "must specify a package id" if $opts[:package_id] == nil
Trollop::die :reverse_domain, "must specify a reversed domain" if $opts[:reverse_domain] == nil
Trollop::die :remove_exisiting_version, "and argument no-overwrite are incompatible with each other" if ($opts[:no_overwrite] == true && $opts[:remove_exisiting_version] == true)

$build_date = `date -u "+%Y-%m-%d"`.chomp
$app_name = clean_name(File.basename($opts[:application]))
$package_id = clean_name($opts[:package_id])
$installed_app = File.basename($opts[:application])
$tarball_name = "#{$app_name}.#{$build_date}.tar.bz2"

# debuggery.
if $opts[:debug] > 0
  require 'pp'
  puts "$opts: #{pp $opts}"
  puts "$package_id: #{$package_id}"
  puts "$build_date: #{$build_date}"
  puts "$app_name: #{$app_name}"
  puts "$installed_app: #{$installed_app}"
  puts "$tarball_name: #{$tarball_name}"
end

if $opts[:directory_name] != nil then
  target_dir = $opts[:directory_name]
else
  target_dir = $package_id
end

if File.directory?(target_dir) then
  puts "#{target_dir} already exists. Exiting so we don't step on your data"
  exit 5
end

Dir.mkdir(target_dir)
Dir.chdir(target_dir)

bundleApplication() if $opts[:create_tarball]
generatePreflight()
generateMakefile()
%x(sudo make dmg) if $opts[:make_dmg]
%x(sudo make pkg) if $opts[:make_pkg]
