# frozen_string_literal: true

require 'octokit'
require_relative 'base'
require_relative '../apis/github/client'

module Issuer
  module Sites
    class GitHub < Base
      def initialize token: nil, token_env_var: nil
        @token = token || self.class.detect_github_token(custom_env_var: token_env_var)
        @milestone_cache = {}  # Cache for milestones by project
        @label_cache = {}      # Cache for labels by project

        # Skip authentication validation for dry-run mode
        if @token == 'dry-run-token'
          @client = nil
          @octokit_client = nil
          return
        end

        unless @token
          env_vars = [token_env_var, *self.class.default_token_env_vars].compact.uniq
          raise Issuer::Error, "GitHub token not found. Set #{env_vars.join(', ')} environment variable."
        end

        # Create our enhanced API client that supports GraphQL
        @client = Issuer::APIs::GitHub::Client.new(token: @token)
        # Keep the Octokit client for non-issue operations
        @octokit_client = Octokit::Client.new(access_token: @token)
        @octokit_client.auto_paginate = true
      end

      def site_name
        'github'
      end

      # Return field display labels for dry-run output
      # Maps site-specific parameter names to user-friendly display labels
      # Note: Issue properties are already converted by convert_issue_to_site_params
      def field_mappings
        {
          title: 'title',        # site_params[:title] displays as "title:"
          body: 'body',          # site_params[:body] displays as "body:"
          repo: 'repo',          # repo displays as "repo:"
          milestone: 'milestone', # site_params[:milestone] displays as "milestone:"
          labels: 'labels',      # site_params[:labels] displays as "labels:"
          assignee: 'assignee',  # site_params[:assignee] displays as "assignee:"
          type: 'type',          # site_params[:type] displays as "type:"
          project_name: 'repo'   # For summary messages: "repo: owner/name"
        }
      end

      def validate_and_prepare_resources proj, issues
        Issuer::Ops.validate_and_prepare_resources(self, proj, issues)
      end

      def create_issue proj, issue_params
        # Validate required fields
        unless issue_params[:title] && !issue_params[:title].strip.empty?
          raise Issuer::Error, "Issue title is required"
        end

        # Prepare issue creation parameters
        params = {
          title: issue_params[:title],
          body: issue_params[:body] || ''
        }

        # Handle labels
        if issue_params[:labels] && !issue_params[:labels].empty?
          params[:labels] = issue_params[:labels].map(&:strip).reject(&:empty?)
        end

        # Handle assignee
        if issue_params[:assignee] && !issue_params[:assignee].strip.empty?
          params[:assignee] = issue_params[:assignee].strip
        end

        # Handle milestone; only if milestone exists
        if issue_params[:milestone]
          # If milestone is already a number (from convert_issue_to_site_params), use it directly
          if issue_params[:milestone].is_a?(Integer)
            params[:milestone] = issue_params[:milestone]
          else
            # If it's a string name, look it up
            milestone = find_milestone(proj, issue_params[:milestone])
            params[:milestone] = milestone.number if milestone
          end
        end

        # Handle type
        if issue_params[:type]
          params[:type] = issue_params[:type]
        end

        created_issue = @client.create_issue(proj, params)

        # Extract relevant data for potential cleanup tracking
        issue_data = {
          number: created_issue.number,
          title: created_issue.title,
          url: created_issue.html_url,
          created_at: created_issue.created_at,
          repository: proj
        }

        # Return both the created issue and tracking data
        { object: created_issue, tracking_data: issue_data }
      rescue Octokit::Error => e
        raise Issuer::Error, "GitHub API error: #{e.message}"
      end

      def get_versions proj
        @octokit_client.milestones(proj, state: 'all')
      rescue Octokit::Error => e
        raise Issuer::Error, "Failed to fetch milestones: #{e.message}"
      end

      def get_tags proj
        @octokit_client.labels(proj)
      rescue Octokit::Error => e
        raise Issuer::Error, "Failed to fetch labels: #{e.message}"
      end

      def create_version proj, version_name, options={}
        description = options[:description] || "Created by issuer CLI"

        # Call create_milestone with proper parameters
        created_milestone = @octokit_client.create_milestone(proj, version_name, description: description)

        # Add the newly created milestone to our cache for immediate availability
        @milestone_cache[proj] ||= []
        @milestone_cache[proj] << created_milestone

        # Return tracking data
        {
          object: created_milestone,
          tracking_data: {
            number: created_milestone.number,
            title: created_milestone.title,
            url: created_milestone.html_url,
            created_at: created_milestone.created_at,
            repository: proj
          }
        }
      rescue Octokit::Error => e
        raise Issuer::Error, "Failed to create milestone '#{version_name}': #{e.message}"
      end

      def create_tag proj, tag_name, options={}
        color = options[:color] || 'f29513'
        description = options[:description]

        # Call add_label with proper parameters
        created_label = @octokit_client.add_label(proj, tag_name, color, description: description)

        # Return tracking data
        {
          object: created_label,
          tracking_data: {
            name: created_label.name,
            color: created_label.color,
            description: created_label.description,
            url: created_label.url,
            repository: proj
          }
        }
      rescue Octokit::Error => e
        raise Issuer::Error, "Failed to create label '#{tag_name}': #{e.message}"
      end

      # Cleanup methods
      def close_issue proj, issue_number
        @octokit_client.close_issue(proj, issue_number)
      rescue Octokit::Error => e
        raise Issuer::Error, "Failed to close issue ##{issue_number}: #{e.message}"
      end

      def delete_milestone proj, milestone_number
        @octokit_client.delete_milestone(proj, milestone_number)
      rescue Octokit::Error => e
        raise Issuer::Error, "Failed to delete milestone ##{milestone_number}: #{e.message}"
      end

      def delete_label proj, label_name
        @octokit_client.delete_label!(proj, label_name)
      rescue Octokit::Error => e
        raise Issuer::Error, "Failed to delete label '#{label_name}': #{e.message}"
      end

      def validate_configuration
        # Test API access
        @octokit_client.user
        true
      rescue Octokit::Error => e
        raise Issuer::Error, "GitHub authentication failed: #{e.message}"
      end

      def authenticate
        validate_configuration
      end

      # Convert IMYML issue to GitHub-specific parameters
      def convert_issue_to_site_params issue, proj, dry_run: false, post_validation: false
        params = {
          title: issue.summ,
          body: issue.body || ''
        }

        # Handle tags -> labels
        if issue.tags && !issue.tags.empty?
          params[:labels] = issue.tags.map(&:strip).reject(&:empty?)
        end

        # Handle user -> assignee
        if issue.user && !issue.user.strip.empty?
          params[:assignee] = issue.user.strip
        end

        # Handle vrsn -> milestone
        if issue.vrsn
          if dry_run
            # In dry-run mode, just show the milestone name without API lookup
            params[:milestone] = issue.vrsn
          else
            # In normal mode, resolve milestone name to number
            milestone = find_milestone(proj, issue.vrsn)
            if milestone
              params[:milestone] = milestone.number
            elsif post_validation
              # If we're in post-validation mode and milestone still not found,
              # this indicates a serious problem with the validation flow
              puts "⚠️  Warning: Milestone '#{issue.vrsn}' not found even after validation for issue '#{issue.summ}'"
            end
          end
        end

        # Handle type
        if issue.type && !issue.type.strip.empty?
          params[:type] = issue.type.strip
        end

        params
      end

      protected

      # Class method to get standard GitHub token environment variable names
      def self.default_token_env_vars
        %w[ISSUER_API_TOKEN ISSUER_GITHUB_TOKEN GITHUB_ACCESS_TOKEN GITHUB_TOKEN]
      end

      # Class method to detect GitHub token from environment
      # @param custom_env_var [String, nil] Custom environment variable name to check first
      # @return [String, nil] The token value or nil if not found
      def self.detect_github_token(custom_env_var: nil)
        # Check custom env var first if provided
        return ENV[custom_env_var] if custom_env_var && ENV[custom_env_var]

        # Fall back to standard env vars
        default_token_env_vars.each do |env_var|
          token = ENV[env_var]
          return token if token
        end

        nil
      end

      private

      def detect_github_token
        self.class.detect_github_token
      end

      def find_milestone proj, milestone_name
        # First check newly created milestones in cache
        if @milestone_cache[proj]
          cached_milestone = @milestone_cache[proj].find { |m| m.title == milestone_name.to_s }
          return cached_milestone if cached_milestone
        end
        
        # Fall back to API lookup for existing milestones
        milestones = get_versions(proj)
        milestones.find { |m| m.title == milestone_name.to_s }
      end
    end
  end
end
