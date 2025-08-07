# frozen_string_literal: true

module Issuer
  ##
  # Represents a single issue in the IMYML format.
  #
  # The Issue class is the core data model that represents individual work items.
  # It handles validation, default application, and processing of IMYML properties
  # like stub composition and tag logic.
  #
  # == IMYML Properties
  #
  # +summ+:: (Required) Issue title/summary
  # +body+:: Issue description/body text
  # +tags+:: Array of labels to apply
  # +user+:: Assignee username
  # +vrsn+:: Milestone/version
  # +type+:: Issue type (e.g., Bug, Feature, Task)
  # +stub+:: Whether to apply stub text composition
  #
  # == Tag Logic
  #
  # Tags support special prefix notation:
  # * Regular tags (e.g., +"bug"+) are only applied if the issue has no existing tags
  # * Append tags (e.g., +"+urgent"+) are always applied to all issues
  # * Removal tags (e.g., +"-needs:docs"+) are removed from the default/appended tags list
  #
  # == Stub Composition
  #
  # When +stub+ is true, the final body is composed from:
  # 1. +head+ text (if provided in defaults)
  # 2. Issue +body+ or default +body+ 
  # 3. +tail+ text (if provided in defaults)
  #
  # @example Creating an issue from IMYML data
  #   data = {
  #     'summ' => 'Fix authentication bug',
  #     'body' => 'Users cannot log in',
  #     'tags' => ['bug', '+urgent'],
  #     'user' => 'developer1',
  #     'vrsn' => '1.0.0'
  #   }
  #   issue = Issuer::Issue.new(data)
  #   issue.valid? # => true
  #
  # @example Applying defaults
  #   defaults = { 'user' => 'default-user', 'tags' => ['needs-triage'] }
  #   issue = Issuer::Issue.new(minimal_data, defaults)
  #
  # @example Processing multiple issues
  #   issues = Issuer::Issue.from_array(array_of_data, defaults)
  #   valid_issues = Issuer::Issue.valid_issues_from_array(array_of_data, defaults)
  #
  class Issue
    attr_reader :summ, :tags, :user, :vrsn, :type, :raw_data
    attr_accessor :body, :stub

    ##
    # Create a new Issue instance from IMYML data
    #
    # @param issue_data [Hash, String] The issue data from IMYML. If String, treated as +summ+.
    # @param defaults [Hash] Default values to apply when issue data is missing properties
    #
    def initialize issue_data, defaults={}
      # Handle string issues (simple format where string is the summary)
      if issue_data.is_a?(String)
        @raw_data = { 'summ' => issue_data }
      else
        @raw_data = issue_data || {}
      end
      @defaults = defaults
      
      # For most fields, issue data overrides defaults
      @summ = @raw_data['summ'] || defaults['summ']
      @body = @raw_data['body'] || @raw_data['desc'] || defaults['body'] || defaults['desc'] || '' # Support both body and desc (legacy)
      @user = @raw_data['user'] || defaults['user']
      @vrsn = @raw_data['vrsn'] || defaults['vrsn']
      @type = @raw_data['type'] || defaults['type']
      @stub = @raw_data.key?('stub') ? @raw_data['stub'] : defaults['stub']
      
      # For tags, we need special handling - combine defaults and issue tags for later processing
      defaults_tags = Array(defaults['tags'])
      issue_tags = Array(@raw_data['tags'])
      @tags = defaults_tags + issue_tags
    end

    ##
    # Check if this issue has the minimum required data
    #
    # @return [Boolean] True if the issue has a non-empty +summ+ (title)
    #
    def valid?
      !summ.nil? && !summ.strip.empty?
    end

    ##
    # Get validation error messages for this issue
    #
    # @return [Array<String>] Array of error messages, empty if valid
    #
    def validation_errors
      errors = []
      errors << "missing required 'summ' field" if summ.nil? || summ.strip.empty?
      errors
    end

    ##
    # Add additional tags to this issue
    #
    # @param additional_tags [Array<String>, String] Tags to add, duplicates removed
    # @return [Array<String>] The updated tags array
    #
    def add_tags additional_tags
      @tags = (@tags + Array(additional_tags)).uniq
    end

    def summary_description
      truncated_body = body.strip[0..50].gsub(/\n.*/m, '…')
      {
        summ: summ,
        body_preview: truncated_body,
        tags: tags,
        user: user,
        vrsn: vrsn
      }
    end

    def ==(other)
      return false unless other.is_a?(Issue)

      summ == other.summ &&
        body == other.body &&
        tags.sort == other.tags.sort &&
        user == other.user &&
        vrsn == other.vrsn
    end

    def self.from_array issues_array, defaults={}
      issues_array.map { |issue_data| new(issue_data, defaults) }
    end

    def self.valid_issues_from_array issues_array, defaults={}
      from_array(issues_array, defaults).select(&:valid?)
    end

    def self.invalid_issues_from_array issues_array, defaults={}
      from_array(issues_array, defaults).reject(&:valid?)
    end

    # Apply tag logic (append vs default behavior)
    def self.apply_tag_logic issues, cli_tags
      # Parse CLI tags for append (+) vs default-only behavior
      cli_append_tags, cli_default_tags = parse_tag_logic(cli_tags)

      issues.each do |issue|
        issue.apply_tag_logic(cli_append_tags, cli_default_tags)
      end

      issues
    end

    # Apply stub logic with head/tail/body composition
    def self.apply_stub_logic issues, defaults
      issues.each do |issue|
        issue.apply_stub_logic(defaults)
      end

      issues
    end

    # Apply tag logic for this issue
    # 
    # Processes existing tags with + prefix as append tags, - prefix as removal tags,
    # combines them with CLI-provided tags, and determines final tag set based on precedence rules.
    # 
    # @param cli_append_tags [Array<String>] Tags to always append from CLI
    # @param cli_default_tags [Array<String>] Default tags from CLI (used when no regular tags exist)
    # @return [void] Sets @tags instance variable
    # 
    # @example
    #   # Issue has tags: ['+urgent', 'bug', '-needs:docs']
    #   issue.apply_tag_logic(['cli-tag'], ['default-tag', 'needs:docs'])
    #   # Result: ['urgent', 'cli-tag', 'bug', 'default-tag'] (needs:docs removed)
    def apply_tag_logic cli_append_tags, cli_default_tags
      # Parse existing tags for + and - prefixes
      existing_tags = tags || []
      append_tags = []
      regular_tags = []
      remove_tags = []

      existing_tags.each do |tag|
        tag_str = tag.to_s
        if tag_str.start_with?('+')
          append_tags << tag_str[1..] # Remove + prefix
        elsif tag_str.start_with?('-')
          remove_tags << tag_str[1..] # Remove - prefix
        else
          regular_tags << tag_str
        end
      end

      # Start with append tags from both defaults and CLI (always applied)
      defaults_append_tags = Array(@defaults['tags']).select { |tag| tag.to_s.start_with?('+') }.map { |tag| tag[1..] }
      final_tags = append_tags + defaults_append_tags + cli_append_tags

      # For regular tags, add issue's own tags, otherwise use default tags
      issue_regular_tags = Array(@raw_data['tags']).reject { |tag| tag.to_s.start_with?('+') || tag.to_s.start_with?('-') }

      if !issue_regular_tags.empty?
        # Issue has its own regular tags, use them
        final_tags.concat(issue_regular_tags)
      else
        # Issue has no regular tags, use defaults from CLI
        final_tags.concat(cli_default_tags)
        # Also add non-append defaults tags (- prefix ignored in defaults)
        defaults_regular_tags = Array(@defaults['tags']).reject { |tag| tag.to_s.start_with?('+') }
        final_tags.concat(defaults_regular_tags)
      end

      # Collect removal tags from issue only (not defaults)
      all_remove_tags = remove_tags
      
      # Remove duplicates first, then remove tags specified for removal
      final_tags = final_tags.uniq - all_remove_tags
      
      # Set the final tags
      @tags = final_tags
    end

    # Apply stub logic for this issue
    # 
    # Composes issue body by combining head, body, and tail components
    # from defaults when stub application is enabled.
    # 
    # @param defaults [Hash] Default values containing 'head', 'body', 'tail', and 'stub' keys
    # @return [void] Sets @body instance variable with composed content
    # 
    # @example
    #   defaults = {'head' => 'Header', 'body' => 'Default body', 'tail' => 'Footer'}
    #   issue.apply_stub_logic(defaults)
    #   # Composes body as "Header\nIssue body\nFooter"
    def apply_stub_logic defaults
      return unless should_apply_stub?(defaults)

      # Build body with stub components
      body_parts = []

      # Add head if present
      if defaults['head'] && !defaults['head'].to_s.strip.empty?
        body_parts << defaults['head'].to_s.strip
      end

      # Add main body (issue body or default body)
      main_body = body
      if main_body.nil? || main_body.to_s.strip.empty?
        main_body = defaults['body'] if defaults['body']
      end
      body_parts << main_body.to_s.strip if main_body

      # Add tail if present
      if defaults['tail'] && !defaults['tail'].to_s.strip.empty?
        body_parts << defaults['tail'].to_s.strip
      end

      # Set the composed body
      @body = body_parts.join("\n")
    end

    # Parse tag logic from a comma-separated string
    # 
    # Separates tags with + prefix (append tags) from regular tags (default tags).
    # Tags with + prefix are always applied, while regular tags are only used
    # when the issue has no existing regular tags. Tags with - prefix are handled
    # in the apply_tag_logic method for removal.
    # 
    # @param tags_string [String] Comma-separated tag string
    # @return [Array<Array<String>>] Two-element array: [append_tags, default_tags]
    # 
    # @example
    #   Issue.parse_tag_logic("+urgent,bug,+critical")
    #   # => [['urgent', 'critical'], ['bug']]
    def self.parse_tag_logic tags_string
      return [[], []] if tags_string.nil? || tags_string.strip.empty?

      tags = tags_string.split(',').map(&:strip).reject(&:empty?)
      append_tags = []
      default_tags = []

      tags.each do |tag|
        if tag.start_with?('+')
          # Remove + prefix and add to append list
          append_tags << tag[1..]
        else
          # Add to default-only list
          default_tags << tag
        end
      end

      [append_tags, default_tags]
    end

    # Generate formatted output for dry-run display
    # 
    # This method produces a standardized format for displaying issues during dry runs.
    # Process: IMYML properties → site-specific parameters → display labels
    # 
    # 1. convert_issue_to_site_params() converts IMYML (summ→title, vrsn→milestone, etc.)
    # 2. field_mappings() provides display labels for those converted parameters
    # 
    # @param site [Issuer::Sites::Base] The target site/platform
    # @param repo [String] The repository identifier
    # @return [String] Formatted issue display
    # 
    # @example Output format
    #   ------
    #   title:      "Fix authentication bug"
    #   body:
    #               Users cannot log in properly after the recent update.
    #               This affects all user accounts.
    #   
    #   type:       Bug
    #   milestone:  1.0.0
    #   labels:
    #     - bug
    #     - urgent
    #   assignee:   developer1
    #   ------
    def formatted_output site, repo
      # Get site-specific field mappings
      field_map = site.field_mappings
      
      # Convert to site-specific parameters
      site_params = site.convert_issue_to_site_params(self, repo, dry_run: true)
      
      output = [""]
      
      # Title (always present)
      title_field = field_map[:title] || 'title'
      output << sprintf("%-12s%s", "#{title_field}:", site_params[:title].inspect)
      
      # Body (with special formatting if present)
      if site_params[:body] && !site_params[:body].strip.empty?
        body_field = field_map[:body] || 'body'
        output << "#{body_field}:"
        # Indent body content with proper line wrapping
        body_lines = site_params[:body].strip.split("\n")
        body_lines.each do |line|
          wrapped_lines = wrap_line_with_indentation(line, 12)
          wrapped_lines.each do |wrapped_line|
            output << wrapped_line
          end
        end
        output << ""  # Empty line after body
      end
      
      # Type
      if site_params[:type]
        type_field = field_map[:type] || 'type'
        output << sprintf("%-12s%s", "#{type_field}:", site_params[:type])
      end
      
      # Milestone/Version
      if site_params[:milestone]
        milestone_field = field_map[:milestone] || 'milestone'
        output << sprintf("%-12s%s", "#{milestone_field}:", site_params[:milestone])
      end
      
      # Labels/Tags
      if site_params[:labels] && !site_params[:labels].empty?
        labels_field = field_map[:labels] || 'labels'
        output << "#{labels_field}:"
        site_params[:labels].each do |label|
          output << "            - #{label}"
        end
      end
      
      # Assignee/User
      if site_params[:assignee]
        assignee_field = field_map[:assignee] || 'assignee'
        output << sprintf("%-12s%s", "#{assignee_field}:", site_params[:assignee])
      end
      
      output << "------"
      output << ""  # Empty line after each issue
      
      output.join("\n")
    end

    private

    # Wrap a line with proper indentation, handling long lines that exceed terminal width
    # 
    # @param line [String] The line to wrap
    # @param indent_size [Integer] Number of spaces for indentation
    # @return [Array<String>] Array of wrapped lines with proper indentation
    # 
    # @example
    #   wrap_line_with_indentation("This is a very long line that needs wrapping", 4)
    #   # => ["    This is a very long line that needs", "    wrapping"]
    def wrap_line_with_indentation line, indent_size
      # Get terminal width, default to 80 if not available
      terminal_width = ENV['COLUMNS']&.to_i || 80
      
      # Calculate available width for content (terminal width - indentation)
      available_width = terminal_width - indent_size
      
      # If line fits within available width, just return it with indentation
      if line.length <= available_width
        return [' ' * indent_size + line]
      end
      
      # Split long line into chunks that fit
      wrapped_lines = []
      remaining_text = line
      
      while remaining_text.length > available_width
        # Find the last space before the available width limit
        break_point = remaining_text.rindex(' ', available_width)
        
        # If no space found, break at the available width (hard wrap)
        break_point = available_width if break_point.nil?
        
        # Extract the chunk and add it with proper indentation
        chunk = remaining_text[0...break_point]
        wrapped_lines << (' ' * indent_size + chunk)
        
        # Remove the processed chunk from remaining text
        remaining_text = remaining_text[break_point..].lstrip
      end
      
      # Add the final chunk if any text remains
      if !remaining_text.empty?
        wrapped_lines << (' ' * indent_size + remaining_text)
      end
      
      wrapped_lines
    end
    
    # Determine if stub logic should be applied to this issue
    # 
    # Checks issue-level stub property first, then falls back to defaults.
    # Converts various truthy values to boolean.
    # 
    # @param defaults [Hash] Default configuration containing 'stub' key
    # @return [Boolean] True if stub should be applied, false otherwise
    # 
    # @example
    #   issue.stub = 'yes'
    #   issue.should_apply_stub?({'stub' => false}) # => true (issue-level wins)
    def should_apply_stub? defaults
      # Check if stub should be applied:
      # 1. Issue-level stub property takes precedence
      # 2. Falls back to defaults stub setting
      # 3. Defaults to false if not specified

      issue_stub = stub
      default_stub = defaults['stub']

      if issue_stub.nil?
        # Use default stub setting (convert to boolean)
        case default_stub
        when true, 'true', 'yes', '1'
          true
        else
          false
        end
      else
        # Use issue-level setting (convert to boolean)
        case issue_stub
        when true, 'true', 'yes', '1'
          true
        else
          false
        end
      end
    end
  end
end
