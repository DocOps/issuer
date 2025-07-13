# frozen_string_literal: true

require 'octokit'

module Issuer
  module APIs
    module GitHub
      class Client
        def initialize token: nil, token_env_var: nil
          @token = token || detect_github_token(token_env_var)

          unless @token
            env_vars = [token_env_var, *default_token_env_vars].compact.uniq
            raise Issuer::Error, "GitHub token not found. Set #{env_vars.join(', ')} environment variable."
          end

          @client = Octokit::Client.new(access_token: @token)
          @client.auto_paginate = true
        end

        def create_issue repo, issue_params
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

          # Handle milestone - only if milestone exists
          if issue_params[:milestone]
            milestone = find_milestone(repo, issue_params[:milestone])
            params[:milestone] = milestone.number if milestone
          end

          @client.create_issue(repo, params[:title], params[:body], params)
        rescue Octokit::Error => e
          raise Issuer::Error, "GitHub API error: #{e.message}"
        end

        def find_milestone repo, milestone_title
          milestones = @client.milestones(repo, state: 'all')
          milestones.find { |m| m.title == milestone_title.to_s }
        rescue Octokit::Error => e
          raise Issuer::Error, "Error fetching milestones: #{e.message}"
        end

        def create_milestone repo, title, description: nil
          @client.create_milestone(repo, title, description: description)
        rescue Octokit::Error => e
          raise Issuer::Error, "Error creating milestone '#{title}': #{e.message}"
        end

        def find_label repo, label_name
          labels = @client.labels(repo)
          labels.find { |l| l.name == label_name.to_s }
        rescue Octokit::Error => e
          raise Issuer::Error, "Error fetching labels: #{e.message}"
        end

        def create_label repo, name, color: 'f29513', description: nil
          @client.add_label(repo, name, color, description: description)
        rescue Octokit::Error => e
          raise Issuer::Error, "Error creating label '#{name}': #{e.message}"
        end

        def get_milestones repo
          @client.milestones(repo, state: 'all')
        rescue Octokit::Error => e
          raise Issuer::Error, "Error fetching milestones: #{e.message}"
        end

        def get_labels repo
          @client.labels(repo)
        rescue Octokit::Error => e
          raise Issuer::Error, "Error fetching labels: #{e.message}"
        end

        def test_connection
          @client.user
          true
        rescue Octokit::Error => e
          raise Issuer::Error, "GitHub connection test failed: #{e.message}"
        end

        def rate_limit
          @client.rate_limit
        end

        private

        def default_token_env_vars
          %w[ISSUER_API_TOKEN ISSUER_GITHUB_TOKEN GITHUB_ACCESS_TOKEN GITHUB_TOKEN]
        end

        def detect_github_token(custom_env_var)
          # Check custom env var first if provided
          return ENV[custom_env_var] if custom_env_var && ENV[custom_env_var]

          # Fall back to standard env vars
          default_token_env_vars.each do |env_var|
            token = ENV[env_var]
            return token if token
          end

          nil
        end
      end
    end
  end
end
