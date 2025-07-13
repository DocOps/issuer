# frozen_string_literal: true

module Issuer
  module Sites
    class Base
      # Site identification
      def site_name
        raise NotImplementedError, "Subclasses must implement site_name"
      end

      # Field display labels for dry-run output formatting
      # Maps site-specific parameter names to user-friendly display labels
      def field_mappings
        raise NotImplementedError, "Subclasses must implement field_mappings"
      end

      # Resource validation and preparation
      def validate_and_prepare_resources proj, issues
        raise NotImplementedError, "Subclasses must implement validate_and_prepare_resources"
      end

      # Issue creation
      def create_issue proj, issue_params
        raise NotImplementedError, "Subclasses must implement create_issue"
      end

      # Resource queries for validation
      def get_versions proj
        raise NotImplementedError, "Subclasses must implement get_versions"
      end

      def get_tags proj
        raise NotImplementedError, "Subclasses must implement get_tags"
      end

      # Resource creation for validation
      def create_version proj, version_name, options={}
        raise NotImplementedError, "Subclasses must implement create_version"
      end

      def create_tag proj, tag_name, options={}
        raise NotImplementedError, "Subclasses must implement create_tag"
      end

      # Resource cleanup methods for caching/undo functionality
      def close_issue proj, issue_number
        raise NotImplementedError, "Subclasses must implement close_issue"
      end

      def delete_milestone proj, milestone_number
        raise NotImplementedError, "Subclasses must implement delete_milestone"
      end

      def delete_label proj, label_name
        raise NotImplementedError, "Subclasses must implement delete_label"
      end

      # Convert IMYML issue to site-specific parameters
      def convert_issue_to_site_params issue, proj, dry_run: false
        raise NotImplementedError, "Subclasses must implement convert_issue_to_site_params"
      end

      # Issue posting
      def post_issues proj, issues, run_id = nil
        processed_count = 0

        issues.each do |issue|
          begin
            # Convert IMYML issue to site-specific parameters
            site_params = convert_issue_to_site_params(issue, proj)
            result = create_issue(proj, site_params)

            # Extract the created issue object (for backwards compatibility)
            created_issue = result.is_a?(Hash) ? result[:object] : result

            puts "✅ Created issue ##{created_issue.number}: #{issue.summ}"
            puts "   URL: #{created_issue.html_url}" if created_issue.respond_to?(:html_url)
            processed_count += 1

            # Log the created issue if tracking is enabled
            if run_id && result.is_a?(Hash) && result[:tracking_data]
              require_relative '../cache'
              Issuer::Cache.log_issue_created(run_id, result[:tracking_data])
            end

            # Rate limiting courtesy
            sleep(1) if processed_count % 10 == 0
          rescue => e
            puts "❌ Failed to create issue '#{issue.summ}': #{e.message}"
          end
        end

        processed_count
      end

      protected

      # Site-specific configuration validation
      def validate_configuration
        raise NotImplementedError, "Subclasses must implement validate_configuration"
      end

      # Site-specific authentication
      def authenticate
        raise NotImplementedError, "Subclasses must implement authenticate"
      end
    end
  end
end
