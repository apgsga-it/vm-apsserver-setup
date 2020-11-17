#!/usr/bin/env ruby
# encoding: utf-8
require 'slop'
require 'yaml'
require 'fileutils'
require 'ostruct'

opts = Slop.parse do |o|
  o.array '-i', '--install', 'Bolt installation plans to executed on the target host(s), , separated by <,>, the plan names can also match partially ', delimiter: ','
  o.bool '-c', '--clone', 'clones gradle home locally '
  o.separator ''
  o.separator 'other options:'
  o.bool '-l', '--list', 'List all Installation Bolt plans '
  o.bool '-a', '--all', 'Execute all Bolt plans'
  o.bool '-x', '--xceptJenkins', 'Execute all Bolt plans', default: false
  o.bool '--dry', '--dry-run','Only print all Bolt plans commands', default: false
  o.bool '--debug', 'Enable bolt debug optin', default: false
  o.on '-h', '--help' do
    puts o
    exit
  end
end
show_output = `bolt plan show --concurrency 20 `
plans_installation_order = []
plans_installation_order << OpenStruct.new('install_order' => 1, 'name' => 'piper::cvs_install')
plans_installation_order << OpenStruct.new('install_order' => 1, 'name' => 'piper::git_install')
plans_installation_order << OpenStruct.new('install_order' => 1, 'name' => 'piper::wget_install')
plans_installation_order << OpenStruct.new('install_order' => 1, 'name' => 'piper::java_install')
plans_installation_order << OpenStruct.new('install_order' => 2, 'name' => 'piper::gradle_install')
plans_installation_order << OpenStruct.new('install_order' => 2, 'name' => 'piper::maven_install')
plans_installation_order << OpenStruct.new('install_order' => 10, 'name' => 'piper::jenkins_account_create')
plans_installation_order << OpenStruct.new('install_order' => 11, 'name' => 'piper::jenkins_dirs_create')
plans_installation_order << OpenStruct.new('install_order' => 12, 'name' => 'piper::jenkins_service_install')
plans_installation_order << OpenStruct.new('install_order' => 20, 'name' => 'piper::jenkins_create_jobs')
plans_installation_order << OpenStruct.new('install_order' => 30, 'name' => 'piper::yum_repo')
plans_installation_order << OpenStruct.new('install_order' => 31, 'name' => 'piper::piper_install')
plans_installation_order << OpenStruct.new('install_order' => 32, 'name' => 'piper::piper_properties')

plans_available = []
plans_to_execute = []
lines = show_output.split("\n")
lines.each do |line|
  if line.match(/piper::/)
    plans_available << line
  end
end
if opts[:clone]
  bolt_inventory_file = File.join(File.dirname(__FILE__), 'inventory.yaml')
  inventory = YAML.load_file(bolt_inventory_file)
  user = inventory['groups'].first['config']['ssh']['user']
  temp_dir = inventory['vars']['temp_gradle']
  if  File.exist?(temp_dir)
    FileUtils.remove_dir(temp_dir, force = true)
  end
  system("git clone #{user}@git.apgsga.ch:/var/git/repos/apg-gradle-properties.git #{temp_dir}")
end
if !opts[:install].empty? and opts[:all]
  puts 'Specify either  -a  or -i option, but not both. -a being all plans and -i being a filter on the available plan names '
  puts opts
  exit
end
if !opts[:all] and opts[:xceptJenkins]
  puts 'The x , resp. xceptJenkins option only makes sense with the --all options'
  puts opts
  exit
end
if opts[:list]
  puts 'Available installations plans are: '
  plans_available.each do
    | plan | puts plan
  end
  puts 'The ordering of the plan execution will be respected with the --all option'
  puts 'With the -i option, the order of the input defines the execution order of the plans'
end
if opts[:install].empty? and !opts[:all]
  exit
end

unless opts[:install].empty?
  plans = []
  opts[:install].each do |plan|
    plans += plans_available.select { |e| e =~ /#{plan}/  }
  end
  plans_to_execute = plans
end

def run(plan,opts)
  debug = opts[:debug] ? '--debug' : ' '
  cmd = "bolt plan run #{plan} #{debug} --concurrency 10 -t testvms"
  puts "#{cmd}"
  system(cmd) unless opts[:dry]
  puts "Done: #{plan}"  unless opts[:dry]
end

if opts[:all]
  plans_available.delete('pipertest::clean_repo')
  plans_to_execute = plans_available
end


unless plans_to_execute.empty?
  puts "Running the plans=<#{plans_to_execute}>"
  if opts[:xceptJenkins]
    plans_to_execute.delete('piper::jenkins_service_install')
    plans_to_execute.delete('piper::jenkins_account_create')
    plans_to_execute.delete('piper::jenkins_dirs_create')
    plans_to_execute.delete('piper::piper_install')
    plans_to_execute.delete('piper::piper_properties')
    plans_to_execute.delete('piper::jenkins_create_jobs')
  end
  sorted_plans = plans_installation_order.sort_by {|p| [p.install_order]}
  sorted_plans.each do |plan|
    if plans_to_execute.include? plan.name
      run(plan.name,opts)
    end
  end

end

