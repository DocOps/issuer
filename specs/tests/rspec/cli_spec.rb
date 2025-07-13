# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Issuer::CLI do
  # Mock the GitHub site methods to avoid actual API calls during testing
  before do
    allow_any_instance_of(Issuer::Sites::GitHub).to receive(:get_versions).and_return([])
    allow_any_instance_of(Issuer::Sites::GitHub).to receive(:find_milestone).and_return(nil)
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

    it 'handles --tokenv option' do
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
