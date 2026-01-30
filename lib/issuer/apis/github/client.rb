# frozen_string_literal: true

require 'octokit'
require 'ostruct'
require 'json'
require 'net/http'
require 'uri'

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

          # If type is specified, use GraphQL API
          if issue_params[:type]
            return create_issue_with_type(repo, issue_params)
          end

          # Otherwise use REST API
          create_issue_rest(repo, issue_params)
        rescue Octokit::Error => e
          raise Issuer::Error, "GitHub API error: #{e.message}"
        end

        def create_issue_rest repo, issue_params
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
            milestone = find_milestone(repo, issue_params[:milestone])
            params[:milestone] = milestone.number if milestone
          end

          @client.create_issue(repo, params[:title], params[:body], params)
        end

        def create_issue_with_type repo, issue_params
          # Get repository owner and name
          owner, name = repo.split('/')
          
          # Get issue type ID
          issue_type_id = resolve_issue_type(repo, issue_params[:type])
          unless issue_type_id
            puts "⚠️  Warning: Issue type '#{issue_params[:type]}' not found. Falling back to REST API."
            # Add type as a label when issue type is not found
            fallback_params = issue_params.dup
            type_label = "type:#{fallback_params[:type]}"
            fallback_params[:labels] = (fallback_params[:labels] || []) + [type_label]
            fallback_params.delete(:type)  # Remove type since REST API doesn't support it
            puts "⚠️  Adding label '#{type_label}' to preserve type information."
            return create_issue_rest(repo, fallback_params)
          end

          # Prepare GraphQL input
          input = {
            repositoryId: get_repository_id(owner, name),
            title: issue_params[:title],
            body: issue_params[:body] || '',
            issueTypeId: issue_type_id
          }

          # Handle labels
          if issue_params[:labels] && !issue_params[:labels].empty?
            input[:labelIds] = resolve_label_ids(repo, issue_params[:labels])
          end

          # Handle assignee
          if issue_params[:assignee] && !issue_params[:assignee].strip.empty?
            input[:assigneeIds] = [get_user_id(issue_params[:assignee])]
          end

          # Handle milestone
          if issue_params[:milestone]
            milestone = find_milestone(repo, issue_params[:milestone])
            input[:milestoneId] = milestone.node_id if milestone
          end

          # Execute GraphQL mutation
          mutation = <<~GRAPHQL
            mutation CreateIssue($input: CreateIssueInput!) {
              createIssue(input: $input) {
                issue {
                  id
                  number
                  title
                  body
                  url
                  createdAt
                }
              }
            }
          GRAPHQL

          result = execute_graphql_query(mutation, { "input" => input })

          # Convert GraphQL response to REST-like format for compatibility
          issue_data = result["data"]["createIssue"]["issue"]
          OpenStruct.new(
            number: issue_data["number"],
            title: issue_data["title"],
            body: issue_data["body"],
            html_url: issue_data["url"],
            created_at: issue_data["createdAt"]
          )
        rescue => e
          puts "⚠️  Warning: GraphQL issue creation failed: #{e.message}. Falling back to REST API."
          # Add type as a label when GraphQL fails
          fallback_params = issue_params.dup
          if fallback_params[:type]
            type_label = "type:#{fallback_params[:type]}"
            fallback_params[:labels] = (fallback_params[:labels] || []) + [type_label]
            fallback_params.delete(:type)  # Remove type since REST API doesn't support it
            puts "⚠️  Adding label '#{type_label}' to preserve type information."
          end
          create_issue_rest(repo, fallback_params)
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

        def get_issue_types repo
          owner, name = repo.split('/')
          query = <<~GRAPHQL
            query GetIssueTypes($owner: String!, $name: String!) {
              repository(owner: $owner, name: $name) {
                issueTypes(first: 20) {
                  nodes {
                    id
                    name
                    description
                  }
                }
              }
            }
          GRAPHQL

          result = execute_graphql_query(query, { owner: owner, name: name })
          result['data']['repository']['issueTypes']['nodes']
        rescue => e
          raise Issuer::Error, "Error fetching issue types: #{e.message}"
        end

        private

        def default_token_env_vars
          %w[ISSUER_API_TOKEN ISSUER_GITHUB_TOKEN GITHUB_ACCESS_TOKEN GITHUB_TOKEN]
        end

        def detect_github_token custom_env_var
          # Check custom env var first if provided
          return ENV[custom_env_var] if custom_env_var && ENV[custom_env_var]

          # Fall back to standard env vars
          default_token_env_vars.each do |env_var|
            token = ENV[env_var]
            return token if token
          end

          nil
        end

        # GraphQL helper methods
        def resolve_issue_type repo, type_name
          issue_types = get_issue_types(repo)
          issue_type = issue_types.find { |type| type['name'].downcase == type_name.downcase }
          issue_type&.[]('id')
        end

        def get_repository_id owner, name
          query = <<~GRAPHQL
            query GetRepository($owner: String!, $name: String!) {
              repository(owner: $owner, name: $name) {
                id
              }
            }
          GRAPHQL

          result = execute_graphql_query(query, { owner: owner, name: name })
          result['data']['repository']['id']
        end

        def resolve_label_ids repo, label_names
          # For now, we'll skip complex label ID resolution
          # GitHub GraphQL API requires label IDs, but REST API uses names
          # This is a simplification; in practice, you'd need to fetch and match labels
          []
        end

        def get_user_id username
          query = <<~GRAPHQL
            query GetUser($login: String!) {
              user(login: $login) {
                id
              }
            }
          GRAPHQL

          result = execute_graphql_query(query, { login: username })
          result['data']['user']['id']
        end

        def execute_graphql_query query, variables = {}
          uri = URI.parse("https://api.github.com/graphql")
          request = Net::HTTP::Post.new(uri)
          request.content_type = "application/json"
          request["Authorization"] = "Bearer #{@token}"
          request.body = JSON.dump({
            "query" => query,
            "variables" => variables
          })

          response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
            http.request(request)
          end

          result = JSON.parse(response.body)

          if result["errors"] && !result["errors"].empty?
            raise Issuer::Error, "GraphQL error: #{result["errors"].first['message']}"
          end

          result
        end
      end
    end
  end
end
