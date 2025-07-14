# frozen_string_literal: true

require_relative "issuer/version"
require_relative "issuer/issue"
require_relative "issuer/apis/github/client"
require_relative "issuer/sites/base"
require_relative "issuer/sites/github"
require_relative "issuer/sites/factory"
require_relative "issuer/ops"
require_relative "issuer/cache"
require_relative "issuer/cli"

##
# = Issuer: Bulk GitHub Issue Creator
#
# Issuer is a Ruby gem that allows you to define all your work tickets in one place
# using the IMYML (Issue Management YAML-based Modeling Language) format, apply defaults,
# and post them to GitHub Issues (and other platforms) in bulk.
#
# == Features
#
# * Bulk issue creation from a single YAML file
# * Dry-run mode for testing without creating issues
# * Automatic milestone and label creation
# * Configurable defaults and label application logic
# * Environment variable support for authentication
# * Issue validation with helpful error messages
# * Extensible architecture for multiple platforms (GitHub, JIRA, GitLab, etc.)
# * Run logging and artifact tracking for cleanup operations
#
# == Quick Start
#
#   # Create issues from an IMYML file
#   processor = Issuer::Processor.new
#   results = processor.process_file('issues.yml', 
#                                    proj: 'myorg/myrepo',
#                                    dry_run: false)
#
#   # Access individual components
#   site = Issuer::Sites::Factory.create(:github)
#   issues = Issuer::Issue.from_array(yaml_data['issues'], defaults)
#
# == Extensibility
#
# The gem is designed for extensibility:
#
# * Create new site adapters by subclassing {Issuer::Sites::Base}
# * Extend the IMYML format by customizing {Issuer::Ops} methods
# * Add custom validation logic to {Issuer::Issue}
# * Track operations with {Issuer::Cache}
#
# @see https://github.com/DocOps/issuer Project Homepage
# @see Issuer::Sites::Base For creating new platform adapters
# @see Issuer::Issue For the core issue model
# @see Issuer::Ops For IMYML processing operations
#
module Issuer

  ##
  # Standard error class for all Issuer-related errors
  class Error < StandardError; end

  ##
  # Main processor class that provides a clean API for external usage.
  # This is the recommended entry point for programmatic access to Issuer functionality.
  #
  # @example Basic usage
  #   processor = Issuer::Processor.new
  #   results = processor.process_file('issues.yml', proj: 'myorg/myrepo')
  #
  # @example With custom site
  #   site = Issuer::Sites::Factory.create(:github, token: 'custom-token')
  #   processor = Issuer::Processor.new(site: site)
  #   results = processor.process_data(yaml_data, proj: 'myorg/myrepo')
  #
  class Processor

    ##
    # Initialize a new processor
    #
    # @param site [Issuer::Sites::Base, nil] Custom site adapter. If nil, will auto-detect.
    # @param cache [Boolean] Whether to enable run tracking and caching (default: true)
    #
    def initialize(site: nil, cache: true)
      @site = site
      @cache_enabled = cache
    end

    ##
    # Process an IMYML file and create issues
    #
    # @param file_path [String] Path to the IMYML YAML file
    # @param proj [String, nil] Target repository (org/repo format)
    # @param dry_run [Boolean] If true, validate and show what would be created without API calls
    # @param automation_options [Hash] Options for automatic resource creation
    # @option automation_options [Boolean] :auto_versions Automatically create missing milestones
    # @option automation_options [Boolean] :auto_tags Automatically create missing labels
    # @option automation_options [Boolean] :auto_metadata Automatically create all missing metadata
    #
    # @return [Hash] Results including created issues, milestones, labels, and run metadata
    # @raise [Issuer::Error] If file cannot be read or processed
    #
    # @example
    #   results = processor.process_file('issues.yml', 
    #                                    proj: 'myorg/myrepo',
    #                                    dry_run: false,
    #                                    automation_options: { auto_metadata: true })
    #   puts "Created #{results[:issues_created]} issues"
    #
    def process_file(file_path, proj: nil, dry_run: false, automation_options: {})
      require 'yaml'

      unless File.exist?(file_path)
        raise Error, "File not found: #{file_path}"
      end

      begin
        raw_data = YAML.load_file(file_path)
      rescue => e
        raise Error, "Could not parse YAML file: #{file_path}\n#{e.message}"
      end

      process_data(raw_data, proj: proj, dry_run: dry_run, automation_options: automation_options)
    end

    ##
    # Process IMYML data structure and create issues
    #
    # @param data [Hash] Parsed IMYML data structure
    # @param proj [String, nil] Target repository (org/repo format)
    # @param dry_run [Boolean] If true, validate and show what would be created without API calls
    # @param automation_options [Hash] Options for automatic resource creation
    #
    # @return [Hash] Results including created issues, milestones, labels, and run metadata
    # @raise [Issuer::Error] If data is invalid or processing fails
    #
    def process_data(data, proj: nil, dry_run: false, automation_options: {})
      # Extract metadata and issues
      meta = data['$meta'] || {}
      issues_data = data['issues'] || data

      unless issues_data.is_a?(Array)
        raise Error, 'No issues array found (root or under "issues")'
      end

      # Build defaults
      defaults = (meta['defaults'] || {}).dup
      defaults['proj'] = meta['proj'] if meta['proj']

      # Determine target repository
      target_repo = proj || meta['proj'] || ENV['ISSUER_REPO']
      if target_repo.nil? && !dry_run
        raise Error, 'No target repo specified. Use proj parameter, $meta.proj, or ISSUER_REPO environment variable.'
      end

      # Process issues
      issues = Ops.process_issues_data(issues_data, defaults)
      valid_issues = issues.select(&:valid?)
      invalid_issues = issues.reject(&:valid?)

      # Report validation errors
      invalid_issues.each_with_index do |issue, idx|
        puts "⚠️  Skipping invalid issue: #{issue.validation_errors.join(', ')}"
      end

      if dry_run
        return perform_dry_run(valid_issues, target_repo)
      else
        return perform_live_run(valid_issues, target_repo, automation_options)
      end
    end

    private

    def get_site
      @site ||= Sites::Factory.create(Sites::Factory.default_site)
    end

    def perform_dry_run(issues, repo)
      site = Sites::Factory.create('github', token: 'dry-run-token')

      puts "🧪 DRY RUN - No issues will be created"
      puts "📋 Target repository: #{repo}" if repo
      puts "📝 Would create #{issues.length} issues:"
      puts

      issues.each_with_index do |issue, idx|
        params = site.convert_issue_to_site_params(issue, repo, dry_run: true)
        puts "#{idx + 1}. #{params[:title]}"
        puts "   Labels: #{params[:labels].join(', ')}" if params[:labels]&.any?
        puts "   Assignee: #{params[:assignee]}" if params[:assignee]
        puts "   Milestone: #{params[:milestone]}" if params[:milestone]
        puts
      end

      {
        dry_run: true,
        issues_planned: issues.length,
        target_repo: repo,
        valid_issues: issues.length
      }
    end

    def perform_live_run(issues, repo, automation_options)
      site = get_site

      # Start run tracking if caching enabled
      run_id = if @cache_enabled
        Cache.start_run(issues_planned: issues.length, target_repo: repo)
      else
        nil
      end

      begin
        # Validate and prepare resources (milestones, labels)
        Ops.validate_and_prepare_resources(site, repo, issues, automation_options, run_id) unless issues.empty?

        # Create issues
        processed_count = site.post_issues(repo, issues, run_id)

        # Complete run tracking
        Cache.complete_run(run_id, processed_count) if run_id

        {
          dry_run: false,
          issues_created: processed_count,
          issues_planned: issues.length,
          target_repo: repo,
          run_id: run_id
        }
      rescue => e
        # Mark run as failed
        Cache.fail_run(run_id, e.message) if run_id
        raise
      end
    end
  end
end
