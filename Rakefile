require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "yaml"
require_relative 'lib/issuer/version'

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

desc "Draft ReleaseHx document"
task :rhx do
  # constructs command like GITHUB_TOKEN=$(gh auth token) && bundle exec rhx 0.3.0 --yaml docs/releases/0.3.0.yml --config .config/releasehx.yml --force
  # First looks for GITHUB_TOKEN already set, then invokes gh auth token if gh is available
  github_token = ENV['GITHUB_TOKEN']
  version = Issuer::VERSION
  unless github_token
    begin
      # check for a valid token or else use gh to refresh the token with export gh auth refresh -s repo
      require 'open3'
      stdout, stderr, status = Open3.capture3("gh auth token")
      if status.success? && !stdout.strip.empty?
        github_token = stdout.strip
      else
        raise "gh auth token failed"
      end
    rescue
      puts "Error: GITHUB_TOKEN not set and 'gh' CLI not available."
      exit 1
    end
  end
  env = { 'GITHUB_TOKEN' => github_token }
  command = "bundle exec rhx #{version} --yaml docs/releases/#{version}.yml --config .config/releasehx.yml --force"
  Bundler.with_original_env do
    sh env, command, verbose: false
  end
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
