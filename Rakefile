require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = 'specs/tests/rspec/**/*_spec.rb'
end

task :default => :spec

desc "Run bundle install"
task :install do
  sh "bundle install"
end

desc "Build and install gem locally"
task :install_local => :build do
  sh "gem install pkg/issuer-*.gem"
end
