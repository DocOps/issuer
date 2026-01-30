# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'digest'
require 'securerandom'
require 'time'

module Issuer
  module Cache
    module_function

    # Directory and file management
    def cache_dir
      if ENV['ISSUER_CONFIG_DIR']
        File.expand_path(ENV['ISSUER_CONFIG_DIR'])
      elsif ENV['XDG_CONFIG_HOME']
        File.join(ENV['XDG_CONFIG_HOME'], 'issuer')
      else
        File.expand_path('~/.config/issuer')
      end
    rescue ArgumentError
      # Fallback if home directory issues
      File.expand_path('.issuer', Dir.pwd)
    end

    def logs_dir
      File.join(cache_dir, 'logs')
    end

    def ensure_cache_directories
      FileUtils.mkdir_p(logs_dir) unless Dir.exist?(logs_dir)
    end

    def run_log_file run_id
      File.join(logs_dir, "#{run_id}.json")
    end

    def generate_run_id
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      random_suffix = SecureRandom.hex(4)
      "run_#{timestamp}_#{random_suffix}"
    end

    # Run tracking
    def start_run metadata = {}
      ensure_cache_directories

      run_id = generate_run_id
      run_data = {
        run_id: run_id,
        started_at: Time.now.iso8601,
        status: 'in_progress',
        metadata: metadata,
        artifacts: {
          issues: [],
          milestones: [],
          labels: []
        },
        summary: {
          issues_created: 0,
          milestones_created: 0,
          labels_created: 0
        }
      }

      save_run_log(run_id, run_data)
      run_id
    end

    def complete_run run_id, issues_processed = nil
      run_data = load_run_log(run_id)
      return unless run_data

      # Handle both symbol and string keys
      completed_key = run_data.key?(:completed_at) ? :completed_at : 'completed_at'
      status_key = run_data.key?(:status) ? :status : 'status'

      run_data[completed_key] = Time.now.iso8601
      run_data[status_key] = 'completed'

      # Update issues processed if provided
      if issues_processed
        summary_key = run_data.key?(:summary) ? :summary : 'summary'
        processed_key = 'issues_processed'
        run_data[summary_key][processed_key] = issues_processed
      end

      save_run_log(run_id, run_data)
    end

    def fail_run run_id, error_message
      run_data = load_run_log(run_id)
      return unless run_data

      # Handle both symbol and string keys
      failed_key = run_data.key?(:failed_at) ? :failed_at : 'failed_at'
      status_key = run_data.key?(:status) ? :status : 'status'
      error_key = run_data.key?(:error) ? :error : 'error'

      run_data[failed_key] = Time.now.iso8601
      run_data[status_key] = 'failed'
      run_data[error_key] = error_message
      save_run_log(run_id, run_data)
    end

    # Artifact tracking
    def log_issue_created run_id, issue_data
      log_artifact(run_id, :issues, issue_data)
    end

    def log_milestone_created run_id, milestone_data
      log_artifact(run_id, :milestones, milestone_data)
    end

    def log_label_created run_id, label_data
      log_artifact(run_id, :labels, label_data)
    end

    def log_artifact run_id, type, artifact_data
      run_data = load_run_log(run_id)
      return unless run_data

      # Handle both symbol and string keys (since JSON loading converts symbols to strings)
      artifacts_key = run_data.key?(:artifacts) ? :artifacts : 'artifacts'
      summary_key = run_data.key?(:summary) ? :summary : 'summary'
      type_key = run_data[artifacts_key].key?(type) ? type : type.to_s

      run_data[artifacts_key][type_key] << artifact_data

      # Increment the appropriate counter (use proper plural-to-singular mapping)
      counter_key = case type.to_s
                   when 'issues' then 'issues_created'
                   when 'milestones' then 'milestones_created'  
                   when 'labels' then 'labels_created'
                   else "#{type}_created"
                   end

      summary_section = run_data[summary_key]
      if summary_section.key?(counter_key.to_sym)
        summary_section[counter_key.to_sym] += 1
      elsif summary_section.key?(counter_key)
        summary_section[counter_key] += 1
      else
        # Fallback; create the key as string
        summary_section[counter_key] = 1
      end

      save_run_log(run_id, run_data)
    end

    # Data persistence
    def save_run_log run_id, data
      File.write(run_log_file(run_id), JSON.pretty_generate(data))
    end

    def load_run_log run_id
      log_file = run_log_file(run_id)
      return nil unless File.exist?(log_file)

      JSON.parse(File.read(log_file), symbolize_names: true)
    rescue JSON::ParserError => e
      puts "⚠️  Warning: Could not parse run log file #{log_file}: #{e.message}"
      nil
    end

    # Query and listing
    def list_runs status: nil, limit: nil
      ensure_cache_directories

      log_files = Dir.glob(File.join(logs_dir, '*.json'))
                     .sort_by { |f| File.mtime(f) }
                     .reverse

      runs = log_files.map do |file|
        begin
          data = JSON.parse(File.read(file), symbolize_names: true)
          next if status && data[:status] != status.to_s
          data
        rescue JSON::ParserError
          nil
        end
      end.compact

      limit ? runs.take(limit) : runs
    end

    def get_run run_id
      load_run_log(run_id)
    end

    def delete_run_log run_id
      log_file = run_log_file(run_id)
      File.delete(log_file) if File.exist?(log_file)
    end
  end
end
