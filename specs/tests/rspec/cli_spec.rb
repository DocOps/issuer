# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Issuer::CLI do
  # Mock the GitHub site methods to avoid actual API calls during testing
  before do
    # Mock GitHub token detection to avoid authentication errors
    allow(Issuer::Sites::GitHub).to receive(:detect_github_token).and_return('mock-token')
    
    allow_any_instance_of(Issuer::Sites::GitHub).to receive(:get_versions).and_return([])
    allow_any_instance_of(Issuer::Sites::GitHub).to receive(:get_tags).and_return([])
    allow_any_instance_of(Issuer::Sites::GitHub).to receive(:find_milestone).and_return(nil)
    allow_any_instance_of(Issuer::Sites::GitHub).to receive(:create_version).and_return({
      object: double(number: 1, title: 'test-milestone'),
      tracking_data: { number: 1, title: 'test-milestone' }
    })
    allow_any_instance_of(Issuer::Sites::GitHub).to receive(:create_tag).and_return({
      object: double(name: 'test-label'),
      tracking_data: { name: 'test-label' }
    })
    allow_any_instance_of(Issuer::Sites::GitHub).to receive(:convert_issue_to_site_params).and_wrap_original do |method, *args|
      issue, repo = args
      {
        title: issue.summ,
        body: issue.body,
        labels: issue.tags || [],
        assignee: issue.user,
        milestone: issue.vrsn
      }
    end
    
    # Mock Octokit client to avoid actual API calls
    mock_client = double('Octokit::Client')
    allow(mock_client).to receive(:auto_paginate=)
    allow(Octokit::Client).to receive(:new).and_return(mock_client)
    
    # Mock Cache methods to avoid file system operations
    allow(Issuer::Cache).to receive(:start_run).and_return('mock-run-id')
    allow(Issuer::Cache).to receive(:complete_run)
    allow(Issuer::Cache).to receive(:fail_run)
    allow(Issuer::Cache).to receive(:log_milestone_created)
    allow(Issuer::Cache).to receive(:log_label_created)
    
    # Mock STDIN to avoid hanging on user input
    allow(STDIN).to receive(:gets).and_return("n\n")
  end

  describe 'file argument handling' do
    let(:sample_file) { create_temp_yaml_file(sample_imyml_content) }

    after { File.unlink(sample_file) if File.exist?(sample_file) }

    it 'accepts positional file argument' do
      # Capture output to avoid cluttering test output
      expect {
        cli = Issuer::CLI.new
        cli.invoke(:main, [sample_file], {dry: true})
      }.to output(/Would process 2 issues/).to_stdout
    end

    it 'accepts --file option' do
      expect {
        cli = Issuer::CLI.new
        cli.invoke(:main, [], {file: sample_file, dry: true})
      }.to output(/Would process 2 issues/).to_stdout
    end

    it 'gives precedence to --file over positional argument' do
      nonexistent_file = '/tmp/nonexistent.yml'

      expect {
        cli = Issuer::CLI.new
        cli.invoke(:main, [nonexistent_file], {file: sample_file, dry: true})
      }.to output(/Would process 2 issues/).to_stdout
    end

    it 'shows error when no file is specified' do
      expect {
        cli = Issuer::CLI.new
        cli.invoke(:main, [], {})
      }.to raise_error(SystemExit).and output(/No IMYML file specified/).to_stderr
    end

    it 'shows error when file does not exist' do
      expect {
        cli = Issuer::CLI.new
        cli.invoke(:main, ['/tmp/nonexistent.yml'], {})
      }.to raise_error(SystemExit).and output(/File not found/).to_stderr
    end
  end

  describe 'option handling' do
    let(:sample_file) { create_temp_yaml_file(sample_imyml_content) }

    after { File.unlink(sample_file) if File.exist?(sample_file) }

    it 'handles --proj option' do
      expect {
        cli = Issuer::CLI.new
        cli.invoke(:main, [sample_file], {proj: 'custom/repo', dry: true})
      }.to output(/repo:\s+custom\/repo/).to_stdout
    end

    it 'handles --tags option with append and default logic' do
      expect {
        cli = Issuer::CLI.new
        cli.invoke(:main, [sample_file], {tags: '+urgent,docs', dry: true})
      }.to output(/- urgent/).to_stdout
    end

    it 'handles --stub option' do
      expect {
        cli = Issuer::CLI.new
        cli.invoke(:main, [sample_file], {stub: true, dry: true})
      }.to output(/Would process 2 issues/).to_stdout
    end

    it 'handles --tokenv option (deprecated but functional)' do
      ENV['MY_GITHUB_TOKEN'] = 'ghp_xxxxx'

      # Mock the Factory to capture the site_options passed to it
      allow(Issuer::Sites::Factory).to receive(:create).and_call_original

      cli = Issuer::CLI.new
      cli.invoke(:main, [sample_file], {tokenv: 'MY_GITHUB_TOKEN', dry: true})

      # Verify that Factory.create was called with the correct token_env_var
      expect(Issuer::Sites::Factory).to have_received(:create).with(
        'github',
        hash_including(token_env_var: 'MY_GITHUB_TOKEN')
      )

      ENV.delete('MY_GITHUB_TOKEN')
    end

    it 'handles --auto-metadata option' do
      # Mock the Ops.validate_and_prepare_resources to capture automation options
      allow(Issuer::Ops).to receive(:validate_and_prepare_resources)
      # Mock post_issues to avoid actual GitHub API calls
      allow_any_instance_of(Issuer::Sites::GitHub).to receive(:post_issues).and_return(0)

      cli = Issuer::CLI.new
      cli.invoke(:main, [sample_file], {auto_metadata: true, proj: 'test/repo'})

      # Verify that validate_and_prepare_resources was called with correct automation options
      expect(Issuer::Ops).to have_received(:validate_and_prepare_resources).with(
        anything,  # site
        anything,  # repo
        anything,  # issues
        hash_including(auto_versions: true, auto_tags: true),  # automation_options
        anything   # run_id
      )
    end

    it 'handles --auto-versions option' do
      # Mock the Ops.validate_and_prepare_resources to capture automation options
      allow(Issuer::Ops).to receive(:validate_and_prepare_resources)
      # Mock post_issues to avoid actual GitHub API calls
      allow_any_instance_of(Issuer::Sites::GitHub).to receive(:post_issues).and_return(0)

      cli = Issuer::CLI.new
      cli.invoke(:main, [sample_file], {auto_versions: true, proj: 'test/repo'})

      # Verify that validate_and_prepare_resources was called with correct automation options
      expect(Issuer::Ops).to have_received(:validate_and_prepare_resources).with(
        anything,  # site
        anything,  # repo
        anything,  # issues
        hash_including(auto_versions: true, auto_tags: false),  # automation_options
        anything   # run_id
      )
    end

    it 'handles --auto-tags option' do
      # Mock the Ops.validate_and_prepare_resources to capture automation options
      allow(Issuer::Ops).to receive(:validate_and_prepare_resources)
      # Mock post_issues to avoid actual GitHub API calls
      allow_any_instance_of(Issuer::Sites::GitHub).to receive(:post_issues).and_return(0)

      cli = Issuer::CLI.new
      cli.invoke(:main, [sample_file], {auto_tags: true, proj: 'test/repo'})

      # Verify that validate_and_prepare_resources was called with correct automation options
      expect(Issuer::Ops).to have_received(:validate_and_prepare_resources).with(
        anything,  # site
        anything,  # repo
        anything,  # issues
        hash_including(auto_versions: false, auto_tags: true),  # automation_options
        anything   # run_id
      )
    end

    it 'combines individual flags with auto_metadata' do
      # Test that --auto-metadata overrides individual flags
      allow(Issuer::Ops).to receive(:validate_and_prepare_resources)
      # Mock post_issues to avoid actual GitHub API calls
      allow_any_instance_of(Issuer::Sites::GitHub).to receive(:post_issues).and_return(0)

      cli = Issuer::CLI.new
      cli.invoke(:main, [sample_file], {auto_metadata: true, auto_versions: false, proj: 'test/repo'})

      # auto_metadata should set both to true, regardless of individual flag values
      expect(Issuer::Ops).to have_received(:validate_and_prepare_resources).with(
        anything,  # site
        anything,  # repo
        anything,  # issues
        hash_including(auto_versions: true, auto_tags: true),  # automation_options
        anything   # run_id
      )
    end

    it 'handles --json option with default path' do
      # Mock File.write to avoid actually creating files during test
      allow(File).to receive(:write)
      # Mock FileUtils.mkdir_p to avoid creating directories
      allow(FileUtils).to receive(:mkdir_p)
      
      expect {
        cli = Issuer::CLI.new
        cli.invoke(:main, [sample_file], {json: ''})
      }.to output(/Saved 2 issue payloads to: _payloads/).to_stdout
      
      # Verify File.write was called with JSON content
      expect(File).to have_received(:write) do |path, content|
        expect(path).to match(/_payloads\/issues_\d{8}_\d{6}\.json/)
        json_data = JSON.parse(content)
        expect(json_data['metadata']['repository']).to eq('test/repo')
        expect(json_data['issues'].length).to eq(2)
      end
    end
    
    it 'handles --json option with custom path' do
      # Mock File.write to avoid actually creating files during test
      allow(File).to receive(:write)
      # Mock FileUtils.mkdir_p to avoid creating directories
      allow(FileUtils).to receive(:mkdir_p)
      
      expect {
        cli = Issuer::CLI.new
        cli.invoke(:main, [sample_file], {json: 'custom-output.json'})
      }.to output(/Saved 2 issue payloads to: custom-output.json/).to_stdout
      
      # Verify File.write was called with the custom path
      expect(File).to have_received(:write) do |path, content|
        expect(path).to eq('custom-output.json')
        json_data = JSON.parse(content)
        expect(json_data['metadata']['repository']).to eq('test/repo')
        expect(json_data['issues'].length).to eq(2)
      end
    end
    
    it 'auto-enables dry mode when --json is used' do
      # Mock File.write to avoid actually creating files during test
      allow(File).to receive(:write)
      allow(FileUtils).to receive(:mkdir_p)
      
      # Should show dry run output even without --dry when --json is used
      expect {
        cli = Issuer::CLI.new
        cli.invoke(:main, [sample_file], {json: 'test.json'})
      }.to output(/Dry run complete/).to_stdout
    end
    
    it 'includes correct JSON structure in --json output' do
      json_content = nil
      
      # Capture the JSON content that would be written
      allow(File).to receive(:write) do |path, content|
        json_content = content
      end
      allow(FileUtils).to receive(:mkdir_p)
      
      cli = Issuer::CLI.new
      cli.invoke(:main, [sample_file], {json: 'test.json'})
      
      # Parse and verify the JSON structure
      json_data = JSON.parse(json_content)
      
      # Check metadata structure
      expect(json_data['metadata']).to include(
        'generated_at',
        'repository',
        'total_issues',
        'issuer_version'
      )
      expect(json_data['metadata']['repository']).to eq('test/repo')
      expect(json_data['metadata']['total_issues']).to eq(2)
      
      # Check issues structure
      expect(json_data['issues']).to be_an(Array)
      expect(json_data['issues'].length).to eq(2)
      
      # Verify first issue has expected API payload structure
      first_issue = json_data['issues'].first
      expect(first_issue).to include('title', 'body', 'labels', 'assignee', 'milestone')
      expect(first_issue['title']).to eq('Test issue 1')
    end

  end

  describe 'version and help' do
    it 'shows version with --version' do
      expect {
        cli = Issuer::CLI.new
        cli.invoke(:main, [], {version: true})
      }.to output(/Issuer version/).to_stdout
    end

    it 'shows help with --help' do
      expect {
        cli = Issuer::CLI.new
        cli.invoke(:main, [], {help: true})
      }.to output(/Usage:/).to_stdout
    end
  end
end
