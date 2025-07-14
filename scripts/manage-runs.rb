#!/usr/bin/env ruby
# frozen_string_literal: true

# Run management utility for issuer CLI
# Lists and manages cached runs in .issuer/logs/

require 'bundler/setup'
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'issuer/cache'

def show_help
  puts <<~HELP
  Issuer Run Management Utility
  
  Usage:
    ruby scripts/manage-runs.rb [command]
  
  Commands:
    list                 List all cached runs
    list --recent        List recent runs only (last 10)
    show RUN_ID          Show detailed information for a specific run
    clean-logs           Remove all log files (use with caution)
    
  Examples:
    ruby scripts/manage-runs.rb list
    ruby scripts/manage-runs.rb show run_20250711_180124_97d1f1f3
    ruby scripts/manage-runs.rb list --recent
  HELP
end

def list_runs recent_only = false
  runs = Issuer::Cache.list_runs
  runs = runs.take(10) if recent_only
  
  if runs.empty?
    puts "No cached runs found."
    return
  end
  
  puts "Cached Runs#{recent_only ? ' (Recent)' : ''}:"
  puts "=" * 60
  
  runs.each do |run|
    puts "#{run[:run_id]} - #{run[:status].upcase}"
    puts "  Started: #{run[:started_at]}"
    
    if run[:metadata] && run[:metadata][:issues_planned]
      puts "  Issues planned: #{run[:metadata][:issues_planned]}"
    end
    
    if run[:status] == 'completed'
      puts "  Completed: #{run[:completed_at]}"
      puts "  Artifacts: #{run[:summary][:issues_created]} issues, #{run[:summary][:milestones_created]} milestones, #{run[:summary][:labels_created]} labels"
      puts "  Processed: #{run[:summary][:issues_processed]} issues"
    elsif run[:status] == 'failed'
      puts "  Failed: #{run[:failed_at] || 'unknown time'}"
      puts "  Error: #{run[:error] || 'no error message'}"
    end
    puts ""
  end
  
  puts "Total: #{runs.length} runs"
  puts "Use 'ruby scripts/manage-runs.rb show RUN_ID' for detailed view"
end

def show_run run_id
  run_data = Issuer::Cache.get_run(run_id)
  unless run_data
    puts "Error: Run #{run_id} not found."
    return
  end
  
  puts "Run Details: #{run_id}"
  puts "=" * 60
  puts "Status: #{run_data[:status]}"
  puts "Started: #{run_data[:started_at]}"
  
  if run_data[:completed_at]
    puts "Completed: #{run_data[:completed_at]}"
  end
  
  if run_data[:failed_at]
    puts "Failed: #{run_data[:failed_at]}"
    puts "Error: #{run_data[:error]}" if run_data[:error]
  end
  
  if run_data[:metadata]
    puts ""
    puts "Metadata:"
    run_data[:metadata].each do |key, value|
      puts "  #{key}: #{value}"
    end
  end
  
  if run_data[:artifacts]
    puts ""
    puts "Artifacts Created:"
    
    [:issues, :milestones, :labels].each do |type|
      artifacts = run_data[:artifacts][type.to_s] || run_data[:artifacts][type] || []
      next if artifacts.empty?
      
      puts "  #{type.to_s.capitalize} (#{artifacts.length}):"
      artifacts.each do |artifact|
        case type
        when :issues
          puts "    ##{artifact[:number] || artifact['number']} - #{artifact[:title] || artifact['title']}"
          puts "      #{artifact[:url] || artifact['url']}"
        when :milestones
          puts "    ##{artifact[:number] || artifact['number']} - #{artifact[:title] || artifact['title']}"
          puts "      #{artifact[:url] || artifact['url']}"
        when :labels
          puts "    #{artifact[:name] || artifact['name']} (#{artifact[:color] || artifact['color']})"
          puts "      #{artifact[:url] || artifact['url']}"
        end
        puts ""
      end
    end
  end
  
  if run_data[:summary]
    puts "Summary:"
    run_data[:summary].each do |key, value|
      puts "  #{key}: #{value}"
    end
  end
end

def clean_logs
  logs_dir = Issuer::Cache.logs_dir
  unless Dir.exist?(logs_dir)
    puts "No logs directory found."
    return
  end
  
  log_files = Dir.glob(File.join(logs_dir, '*.json'))
  if log_files.empty?
    puts "No log files found."
    return
  end
  
  puts "Found #{log_files.length} log files."
  print "Are you sure you want to delete all log files? [y/N]: "
  response = STDIN.gets.chomp.downcase
  
  unless ['y', 'yes'].include?(response)
    puts "Cancelled."
    return
  end
  
  log_files.each { |f| File.delete(f) }
  puts "Deleted #{log_files.length} log files."
end

# Main execution
case ARGV[0]
when 'list'
  recent_only = ARGV.include?('--recent')
  list_runs(recent_only)
when 'show'
  if ARGV[1]
    show_run(ARGV[1])
  else
    puts "Error: Please specify a run ID"
    puts "Usage: ruby scripts/manage-runs.rb show RUN_ID"
  end
when 'clean-logs'
  clean_logs
when nil, '--help', '-h'
  show_help
else
  puts "Error: Unknown command '#{ARGV[0]}'"
  puts ""
  show_help
end
