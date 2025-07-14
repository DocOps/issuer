# frozen_string_literal: true

require 'set'

module Issuer
  # The Ops module provides high-level operations for processing collections of issues,
  # including data normalization, tag and stub logic application, and resource validation.
  # This module serves as an orchestrator that delegates specific behaviors to the Issue class.
  module Ops
    module_function

    # Processes raw issue data into normalized Issue objects.
    # 
    # This method converts scalar strings to proper issue hashes and creates Issue objects
    # with enhanced defaults processing. It handles both string and hash inputs gracefully.
    #
    # @param issues_data [Array<String, Hash>] Raw issue data - can be strings or hashes
    # @param defaults [Hash] Default values to apply to all issues
    # @return [Array<Issuer::Issue>] Array of processed Issue objects
    #
    # @example
    #   issues_data = ["Fix login bug", {"summ" => "Add feature", "tags" => ["enhancement"]}]
    #   defaults = {"assignee" => "admin", "priority" => "normal"}
    #   issues = Ops.process_issues_data(issues_data, defaults)
    def self.process_issues_data issues_data, defaults
      # Convert scalar strings to issue objects
      normalized_data = self.normalize_issue_records(issues_data)

      # Create Issue objects with enhanced defaults processing
      issues = Issuer::Issue.from_array(normalized_data, defaults)

      issues
    end

    # Applies tag logic to a collection of issues, typically based on CLI-provided tags.
    # 
    # This method delegates to the Issue class for consistency and to avoid code duplication.
    # Tags can be applied based on various conditions or merged with existing issue tags.
    #
    # @param issues [Array<Issuer::Issue>] Collection of issues to process
    # @param cli_tags [Array<String>] Tags provided via CLI arguments
    # @return [Array<Issuer::Issue>] Issues with updated tag logic applied
    #
    # @example
    #   issues = [issue1, issue2]
    #   cli_tags = ["urgent", "frontend"]
    #   Ops.apply_tag_logic(issues, cli_tags)
    def self.apply_tag_logic issues, cli_tags
      # Delegate to Issue class method for consistency
      Issuer::Issue.apply_tag_logic(issues, cli_tags)
    end

    # Applies stub logic to a collection of issues based on provided defaults.
    # 
    # This method delegates to the Issue class for consistency and to avoid code duplication.
    # Stub logic determines whether to create stub issues or apply certain transformations.
    #
    # @param issues [Array<Issuer::Issue>] Collection of issues to process
    # @param defaults [Hash] Default values and configuration for stub logic
    # @return [Array<Issuer::Issue>] Issues with updated stub logic applied
    #
    # @example
    #   issues = [issue1, issue2]
    #   defaults = {"stub_enabled" => true, "stub_prefix" => "[STUB]"}
    #   Ops.apply_stub_logic(issues, defaults)
    def self.apply_stub_logic issues, defaults
      # Delegate to Issue class method for consistency
      Issuer::Issue.apply_stub_logic(issues, defaults)
    end

    # Validates and prepares resources (versions/milestones and tags/labels) needed for issues.
    # 
    # This method ensures that all versions and tags referenced by issues exist in the target
    # project. It can interactively prompt for creation of missing resources or auto-create
    # them based on automation options.
    #
    # @param site [Object] Site connector object (e.g., GitHub, GitLab, Jira)
    # @param proj [String] Project identifier (repository name, project key, etc.)
    # @param issues [Array<Issuer::Issue>] Issues that will be created
    # @param automation_options [Hash] Options for automatic resource creation
    # @option automation_options [Boolean] :auto_versions Auto-create missing versions
    # @option automation_options [Boolean] :auto_tags Auto-create missing tags
    # @param run_id [String] Optional run identifier for tracking created resources
    # @return [void]
    #
    # @example
    #   automation = {auto_versions: true, auto_tags: false}
    #   Ops.validate_and_prepare_resources(github_site, "my-repo", issues, automation, "run123")
    def self.validate_and_prepare_resources site, proj, issues, automation_options = {}, run_id = nil
      return if issues.empty?

      # Step 1: Collect all unique versions and tags from issues
      required_versions, required_tags = self.collect_required_resources(issues)

      return if required_versions.empty? && required_tags.empty?

      # Get site-specific terminology
      version_term, tag_term = self.get_site_terminology(site)

      puts "🔍 Checking #{site.site_name} project for existing #{version_term} and #{tag_term}..."

      # Step 2: Check what exists vs what's missing
      missing_versions, missing_tags = self.check_missing_resources(site, proj, required_versions, required_tags)

      if missing_versions.empty? && missing_tags.empty?
        puts "✅ All #{version_term} and #{tag_term} already exist in project"
        return
      end

      puts "⚠️  Found missing #{version_term} (vrsn entries) and/or #{tag_term} (tags) that need to be created:"

      # Step 3: Interactive or automatic creation of missing resources
      auto_versions = automation_options[:auto_versions] || false
      auto_tags = automation_options[:auto_tags] || false

      self.create_missing_versions(site, proj, missing_versions, version_term, auto_versions, run_id) unless missing_versions.empty?
      self.create_missing_tags(site, proj, missing_tags, tag_term, auto_tags, run_id) unless missing_tags.empty?

      puts ""
      puts "✅ Resource validation complete. Proceeding with issue creation..."
    rescue => e
      puts "❌ Error during validation: #{e.message}"
      puts "Proceeding anyway, but some issues might fail to create..."
    end

    private

    def self.get_site_terminology site
      case site.site_name.downcase
      when 'github'
        ['milestones', 'labels']
      when 'jira'
        ['versions', 'labels']
      when 'gitlab'
        ['milestones', 'labels']
      else
        ['versions', 'tags']
      end
    end

    def self.normalize_issue_records issues_data
      issues_data.map do |item|
        if item.is_a?(String)
          # Convert scalar string to hash with summ property
          { 'summ' => item }
        else
          # Already a hash, return as-is
          item
        end
      end
    end

    def self.collect_required_resources issues
      versions = Set.new
      tags = Set.new

      issues.each do |issue|
        # Collect version (vrsn in IMYML)
        if issue.vrsn && !issue.vrsn.to_s.strip.empty?
          versions << issue.vrsn.to_s.strip
        end

        # Collect tags (tags in IMYML)
        issue.tags.each do |tag|
          tag_name = tag.to_s.strip
          tags << tag_name unless tag_name.empty?
        end
      end

      [versions.to_a, tags.to_a]
    end

    def self.check_missing_resources site, proj, required_versions, required_tags
      existing_versions = site.get_versions(proj).map(&:title)
      existing_tags = site.get_tags(proj).map(&:name)

      missing_versions = required_versions - existing_versions
      missing_tags = required_tags - existing_tags

      [missing_versions, missing_tags]
    end

    def self.create_missing_versions site, proj, missing_versions, version_term = 'versions', auto_create = false, run_id = nil
      missing_versions.each do |version_name|
        puts ""
        puts "📋 #{version_term.capitalize.chomp('s')} '#{version_name}' does not exist in project '#{proj}'"

        if auto_create
          puts "Auto-creating #{version_term.chomp('s').downcase}: #{version_name}"
          result = site.create_version(proj, version_name)
          puts "✅ #{version_term.capitalize.chomp('s')} '#{version_name}' created successfully"

          # Log the created milestone if tracking is enabled
          if run_id && result.is_a?(Hash) && result[:tracking_data]
            require_relative 'cache'
            Issuer::Cache.log_milestone_created(run_id, result[:tracking_data])
          end
        else
          print "Create #{version_term.chomp('s').downcase} '#{version_name}'? [Y/n/q]: "

          response = STDIN.gets.chomp.downcase
          case response
          when '', 'y', 'yes'
            puts "Creating #{version_term.chomp('s').downcase}: #{version_name}"
            result = site.create_version(proj, version_name)
            puts "✅ #{version_term.capitalize.chomp('s')} '#{version_name}' created successfully"

            # Log the created milestone if tracking is enabled
            if run_id && result.is_a?(Hash) && result[:tracking_data]
              require_relative 'cache'
              Issuer::Cache.log_milestone_created(run_id, result[:tracking_data])
            end
          when 'q', 'quit'
            puts "❌ Exiting - please resolve missing #{version_term} and try again"
            exit 1
          else
            puts "⚠️  Skipping #{version_term.chomp('s').downcase} creation. Issues with this #{version_term.chomp('s').downcase} may fail to create."
          end
        end
      end
    end

    def self.create_missing_tags site, proj, missing_tags, tag_term = 'tags', auto_create = false, run_id = nil
      missing_tags.each do |tag_name|
        puts ""
        puts "🏷️  #{tag_term.capitalize.chomp('s')} '#{tag_name}' does not exist in project '#{proj}'"

        if auto_create
          puts "Auto-creating #{tag_term.chomp('s').downcase}: #{tag_name}"
          result = site.create_tag(proj, tag_name)
          puts "✅ #{tag_term.capitalize.chomp('s')} '#{tag_name}' created successfully"

          # Log the created label if tracking is enabled
          if run_id && result.is_a?(Hash) && result[:tracking_data]
            require_relative 'cache'
            Issuer::Cache.log_label_created(run_id, result[:tracking_data])
          end
        else
          print "Create #{tag_term.chomp('s').downcase} '#{tag_name}' with default color? [Y/n/c/q]: "

          response = STDIN.gets.chomp.downcase
          case response
          when '', 'y', 'yes'
            puts "Creating #{tag_term.chomp('s').downcase}: #{tag_name}"
            result = site.create_tag(proj, tag_name)
            puts "✅ #{tag_term.capitalize.chomp('s')} '#{tag_name}' created successfully"

            # Log the created label if tracking is enabled
            if run_id && result.is_a?(Hash) && result[:tracking_data]
              require_relative 'cache'
              Issuer::Cache.log_label_created(run_id, result[:tracking_data])
            end
          when 'c', 'custom'
            print "Enter hex color (without #, e.g. 'f29513'): "
            color = STDIN.gets.chomp
            color = 'f29513' if color.empty?

            print "Enter description (optional): "
            description = STDIN.gets.chomp
            description = nil if description.empty?

            puts "Creating #{tag_term.chomp('s').downcase}: #{tag_name} with color ##{color}"
            result = site.create_tag(proj, tag_name, color: color, description: description)
            puts "✅ #{tag_term.capitalize.chomp('s')} '#{tag_name}' created successfully"

            # Log the created label if tracking is enabled
            if run_id && result.is_a?(Hash) && result[:tracking_data]
              require_relative 'cache'
              Issuer::Cache.log_label_created(run_id, result[:tracking_data])
            end
          when 'q', 'quit'
            puts "❌ Exiting - please resolve missing #{tag_term} and try again"
            exit 1
          else
            puts "⚠️  Skipping #{tag_term.chomp('s').downcase} creation. Issues with this #{tag_term.chomp('s').downcase} may not be tagged properly."
          end
        end
      end
    end
  end
end
