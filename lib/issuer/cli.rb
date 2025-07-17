# frozen_string_literal: true

require 'yaml'
require 'thor'

module Issuer
  class CLI < Thor
    # Silence Thor deprecation warning
    def self.exit_on_failure?
      true
    end

    # Define class-level options for access in help
    class_option :file, type: :string, desc: 'IMYML file path (alternative to positional argument)'
    class_option :proj, type: :string, desc: 'Override $meta.proj (org/repo)'
    class_option :vrsn, type: :string, desc: 'Default version for all issues'
    class_option :user, type: :string, desc: 'Default assignee (GitHub username)'
    class_option :tags, type: :string, desc: 'Comma-separated default or appended (+) labels for all issues'
    class_option :stub, type: :boolean, desc: 'Enable stub mode for all issues'
    class_option :dry, type: :boolean, default: false, aliases: ['--dry-run'], desc: 'Print issues, don\'t post'
    class_option :tokenv, type: :string, desc: 'Name of environment variable containing GitHub token'

    # Resource automation options
    class_option :auto_versions, type: :boolean, aliases: ['--auto-milestones'], desc: 'Automatically create missing versions/milestones without prompting'
    class_option :auto_tags, type: :boolean, aliases: ['--auto-labels'], desc: 'Automatically create missing tags/labels without prompting'
    class_option :auto_metadata, type: :boolean, desc: 'Automatically create all missing metadata (versions and tags) without prompting'

    class_option :help, type: :boolean, aliases: ['-h'], desc: 'Show help message'
    class_option :version, type: :boolean, aliases: ['-v'], desc: 'Show version'

    # Handle special options first
    def self.start given_args=ARGV, config={}
      # Handle --version option
      if given_args.include?('--version') || given_args.include?('-v')
        puts "Issuer version #{Issuer::VERSION}"
        exit 0
      end

      # Handle --help option
      if given_args.include?('--help') || given_args.include?('-h') || given_args.empty?
        show_help
        exit 0
      end

      # For all other cases, treat first argument as file and process as main command
      given_args.unshift('main') unless given_args[0] == 'main'
      super(given_args, config)
    end

    desc 'main [IMYML_FILE]', 'Create GitHub issues from an IMYML YAML file', hide: true

    def main file=nil
      # Handle options that should exit early
      if options[:help]
        self.class.show_help
        return
      end

      if options[:version]
        puts "Issuer version #{Issuer::VERSION}"
        return
      end

      # Determine file path: --file option takes precedence over positional argument
      file_path = options[:file] || file
      if file_path.nil?
        abort "Error: No IMYML file specified. Use 'issuer FILE' or 'issuer --file FILE'"
      end

      unless File.exist?(file_path)
        abort "Error: File not found: #{file_path}"
      end

      begin
        raw = File.open(file_path) { |f| YAML.load(f) }
      rescue => e
        abort "Error: Could not parse YAML file: #{file_path}\n#{e.message}"
      end

      if raw.nil?
        abort "Error: YAML file appears to be empty: #{file_path}"
      end

      meta = raw['$meta'] || {}
      issues_data = raw['issues'] || raw # fallback if no $meta

      unless issues_data.is_a?(Array)
        abort 'Error: No issues array found (root or under "issues")'
      end

      # Build defaults merging: CLI > $meta.defaults > issue
      defaults = (meta['defaults'] || {}).dup
      defaults['proj'] = meta['proj'] if meta['proj']
      defaults['vrsn'] = options[:vrsn] if options[:vrsn]
      defaults['user'] = options[:user] if options[:user]
      defaults['stub'] = options[:stub] if !options[:stub].nil?

      # Determine target repository
      repo = options[:proj] || meta['proj'] || ENV['ISSUER_REPO'] || ENV['ISSUER_PROJ']
      if repo.nil? && !options[:dry]
        abort 'No target repo set. Use --proj, $meta.proj, or ENV[ISSUER_REPO].'
      end

      # Process issues with new Ops module
      issues = Issuer::Ops.process_issues_data(issues_data, defaults)

      # Apply tag logic (append vs default behavior)
      issues = Issuer::Ops.apply_tag_logic(issues, options[:tags])

      # Apply stub logic with head/tail/body composition
      issues = Issuer::Ops.apply_stub_logic(issues, defaults)

      # Separate valid and invalid issues
      valid_issues = issues.select(&:valid?)
      invalid_issues = issues.reject(&:valid?)

      # Report invalid issues
      invalid_issues.each_with_index do |issue, idx|
        puts "Skipping issue ##{find_original_index(issues, issue) + 1}: #{issue.validation_errors.join(', ')}"
      end

      if options[:dry]
        perform_dry_run(valid_issues, repo)
      else
        # Use Sites architecture for validation and posting
        site_options = {}
        site_options[:token_env_var] = options[:tokenv] if options[:tokenv]
        site = Issuer::Sites::Factory.create('github', **site_options)
        automation_options = {
          auto_versions: !!options[:auto_versions] || !!options[:auto_metadata],
          auto_tags: !!options[:auto_tags] || !!options[:auto_metadata]
        }

        # Start run tracking for live operations
        require_relative 'cache'
        run_id = Issuer::Cache.start_run(issues_planned: valid_issues.length)
        puts "🏃 Started run #{run_id} - tracking #{valid_issues.length} issues"

        begin
          Issuer::Ops.validate_and_prepare_resources(site, repo, valid_issues, automation_options, run_id) unless valid_issues.empty?
          processed_count = site.post_issues(repo, valid_issues, run_id)

          # Complete the run successfully
          Issuer::Cache.complete_run(run_id, processed_count)
          puts "✅ Run #{run_id} completed successfully - #{processed_count} issues created"
        rescue => e
          # Mark run as failed
          Issuer::Cache.fail_run(run_id, e.message)
          puts "❌ Run #{run_id} failed: #{e.message}"
          raise
        end
      end

      print_summary(valid_issues.length, invalid_issues.length, options[:dry])
    end

    private

    def self.show_help
      puts <<~HELP
      Issuer: Bulk GitHub issue creator from YAML definitions

      Usage:
        issuer IMYML_FILE [options]
        issuer --file IMYML_FILE [options]

      Issue Default Options:
        --vrsn VERSION           #{self.class_options[:vrsn].description}
        --user USERNAME          #{self.class_options[:user].description}
        --tags tag1,+tag2        #{self.class_options[:tags].description}
        --stub                   #{self.class_options[:stub].description}

      Site Options:
        --proj org/repo          #{self.class_options[:proj].description}
        --tokenv VAR_NAME        #{self.class_options[:tokenv].description}

      Mode Options:
        --dry, --dry-run         #{self.class_options[:dry].description}
        --auto-versions          #{self.class_options[:auto_versions].description}
        --auto-milestones        (alias for --auto-versions)
        --auto-tags              #{self.class_options[:auto_tags].description}
        --auto-labels            (alias for --auto-tags)
        --auto-metadata          #{self.class_options[:auto_metadata].description}

      Info:
        -h, --help               #{self.class_options[:help].description}
        -v, --version            #{self.class_options[:version].description}

      Examples:
        issuer issues.yml --dry
        issuer issues.yml --proj myorg/myrepo
        issuer --file issues.yml --proj myorg/myrepo --dry
        issuer issues.yml --vrsn 1.1.2
        issuer --version
        issuer --help

      Authentication:
      Set GITHUB_TOKEN environment variable with your GitHub personal access token
      Or use --tokenv to specify a custom environment variable name

      HELP
    end

    def find_original_index issues_array, target_issue
      issues_array.find_index(target_issue) || 0
    end

    def perform_dry_run issues, repo
      # Create site instance for parameter conversion in dry-run mode
      site_options = { token: 'dry-run-token' }
      site_options[:token_env_var] = options[:tokenv] if options[:tokenv]
      site = Issuer::Sites::Factory.create('github', **site_options)

      issues.each do |issue|
        print_issue_summary(issue, repo, site)
      end
      
      # Add project summary at the end
      if repo
        project_term = site.field_mappings[:project_name] || 'project'
        puts "Would process #{issues.length} issues for #{project_term}: #{repo}"
      end
    end

    def print_summary valid_count, invalid_count, dry_run
      if dry_run
        puts "\nDry run complete (use without --dry to actually post)"
        puts "Would process #{valid_count} issues, skip #{invalid_count}"
      else
        puts "\n✅ Completed: #{valid_count} issues processed, #{invalid_count} skipped"
        # Note: Run ID is already displayed in the main flow, no need to repeat it here
      end
      
    end

    def print_issue_summary issue, repo, site
      # Use the new formatted output method from the Issue class
      puts issue.formatted_output(site, repo)
    end
  end
end
