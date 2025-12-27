require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "yaml"

# Load DocOps Lab development tasks
begin
  require 'docopslab/dev'
rescue LoadError
  # Skip if not available (e.g., production environment)
end

RSpec::Core::RakeTask.new(:rspec) do |t|
  t.pattern = 'specs/tests/rspec/**/*_spec.rb'
end

task :default => :rspec

desc "Setup Vale styles"
task :vale_setup do
  sh "vale sync"
end

desc "Run documentation quality checks"
task :quality => :vale_setup do
  sh "vale --no-exit --output=line *.adoc examples/*.adoc specs/tests/*.adoc || true"
end

desc "Run CLI tests"
task :cli_test do
  puts "Testing CLI functionality..."
  sh "ruby -Ilib exe/issuer --version"
  sh "ruby -Ilib exe/issuer --help"
  sh "ruby -Ilib exe/issuer examples/minimal-example.yml --dry"
end

desc "Validate YAML examples"
task :yaml_test do
  puts "Validating YAML examples..."
  Dir.glob("examples/*.yml").each do |file|
    puts "Validating #{file}"
    begin
      YAML.load_file(file)
      puts "✓ #{file} is valid"
    rescue => e
      puts "✗ #{file} failed: #{e.message}"
      exit 1
    end
  end
end

desc "Run bundle install"
task :install do
  sh "bundle install"
end

desc "Run all PR tests locally (same as GitHub Actions)"
task :pr_test do
  puts "🔍 Running all PR tests locally..."
  puts "\n=== RSpec Tests ==="
  Rake::Task[:rspec].invoke
  
  puts "\n=== CLI Tests ==="
  Rake::Task[:cli_test].invoke
  
  puts "\n=== YAML Validation ==="
  Rake::Task[:yaml_test].invoke
  
  puts "\n=== Documentation Quality ==="
  Rake::Task[:quality].invoke
  
  puts "\n✅ All PR tests passed!"
end

desc "Build and install gem locally"
task :install_local => :build do
  sh "gem install pkg/issuer-*.gem"
end
