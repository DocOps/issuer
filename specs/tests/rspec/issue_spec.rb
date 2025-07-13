# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Issuer::Issue do
  let(:issue_data) do
    {
      'summ' => 'Test issue title',
      'desc' => 'Test issue description',
      'tags' => ['bug', 'high-priority'],
      'user' => 'testuser',
      'vrsn' => '1.0.0'
    }
  end

  let(:defaults) do
    {
      'user' => 'defaultuser',
      'tags' => ['default-tag']
    }
  end

  describe '#initialize' do
    it 'initializes with issue data and defaults' do
      issue = described_class.new(issue_data, defaults)
      
      expect(issue.summ).to eq('Test issue title')
      expect(issue.body).to eq('Test issue description')
      expect(issue.tags).to eq(['bug', 'high-priority'])
      expect(issue.user).to eq('testuser')
      expect(issue.vrsn).to eq('1.0.0')
    end

    it 'merges defaults with issue data, preferring issue data' do
      issue = described_class.new(issue_data, defaults)
      
      # Issue data should override defaults
      expect(issue.user).to eq('testuser')
      expect(issue.tags).to eq(['bug', 'high-priority'])
    end

    it 'uses defaults when issue data is missing fields' do
      minimal_data = { 'summ' => 'Title only' }
      issue = described_class.new(minimal_data, defaults)
      
      expect(issue.summ).to eq('Title only')
      expect(issue.user).to eq('defaultuser')
      expect(issue.tags).to eq(['default-tag'])
    end
  end

  describe '#valid?' do
    it 'returns true for issues with a title' do
      issue = described_class.new(issue_data)
      expect(issue).to be_valid
    end

    it 'returns false for issues without a title' do
      invalid_data = { 'desc' => 'Description only' }
      issue = described_class.new(invalid_data)
      expect(issue).not_to be_valid
    end

    it 'returns false for issues with empty title' do
      invalid_data = { 'summ' => '   ' }
      issue = described_class.new(invalid_data)
      expect(issue).not_to be_valid
    end
  end

  describe '#add_tags' do
    it 'adds additional tags to existing ones' do
      issue = described_class.new(issue_data)
      issue.add_tags(['new-label', 'another-label'])
      
      expect(issue.tags).to include('bug', 'high-priority', 'new-label', 'another-label')
    end

    it 'removes duplicates when adding tags' do
      issue = described_class.new(issue_data)
      issue.add_tags(['bug', 'new-label'])
      
      expect(issue.tags.count('bug')).to eq(1)
      expect(issue.tags).to include('new-label')
    end
  end

  describe 'site integration' do
    let(:github_site) do
      # Mock the Octokit client to avoid real API calls
      mock_client = double('client')
      allow(mock_client).to receive(:auto_paginate=)
      
      # Mock milestone for version conversion
      mock_milestone = double('milestone', title: '1.0.0', number: 1)
      allow(mock_client).to receive(:milestones).with(any_args).and_return([mock_milestone])
      allow(Octokit::Client).to receive(:new).and_return(mock_client)
      allow_any_instance_of(Issuer::Sites::GitHub).to receive(:detect_github_token).and_return('test-token')
      Issuer::Sites::GitHub.new(token: 'test-token')
    end
    
    it 'can be translated to GitHub API parameters via site' do
      issue = described_class.new(issue_data)
      params = github_site.convert_issue_to_site_params(issue, "test/repo")
      
      expect(params[:title]).to eq('Test issue title')
      expect(params[:body]).to eq('Test issue description')
      expect(params[:labels]).to eq(['bug', 'high-priority'])
      expect(params[:assignee]).to eq('testuser')
      expect(params[:milestone]).to eq(1)
    end

    it 'handles missing optional fields when translated via site' do
      minimal_data = { 'summ' => 'Title only' }
      issue = described_class.new(minimal_data)
      params = github_site.convert_issue_to_site_params(issue, "test/repo")
      
      expect(params[:title]).to eq('Title only')
      expect(params[:body]).to eq('')
      expect(params).not_to have_key(:labels)
      expect(params).not_to have_key(:assignee)
      expect(params).not_to have_key(:milestone)
    end
  end

  describe '.from_array' do
    it 'creates multiple Issue objects from array' do
      issues_array = [
        { 'summ' => 'First issue' },
        { 'summ' => 'Second issue' }
      ]
      
      issues = described_class.from_array(issues_array, defaults)
      
      expect(issues.length).to eq(2)
      expect(issues.first.summ).to eq('First issue')
      expect(issues.last.summ).to eq('Second issue')
    end
  end

  describe '.valid_issues_from_array' do
    it 'returns only valid issues' do
      issues_array = [
        { 'summ' => 'Valid issue' },
        { 'desc' => 'Invalid - no title' },
        { 'summ' => 'Another valid issue' }
      ]
      
      valid_issues = described_class.valid_issues_from_array(issues_array)
      
      expect(valid_issues.length).to eq(2)
      expect(valid_issues.map(&:summ)).to eq(['Valid issue', 'Another valid issue'])
    end
  end

  describe 'new properties support' do
    it 'supports body field instead of desc (legacy support)' do
      new_format = { 'summ' => 'Title', 'body' => 'New body format' }
      issue = described_class.new(new_format)
      
      expect(issue.body).to eq('New body format')
    end

    it 'prefers body over desc when both are present' do
      mixed_format = { 'summ' => 'Title', 'body' => 'New body', 'desc' => 'Old desc' }
      issue = described_class.new(mixed_format)
      
      expect(issue.body).to eq('New body')
    end

    it 'supports stub property' do
      stub_data = { 'summ' => 'Title', 'stub' => true }
      issue = described_class.new(stub_data)
      
      expect(issue.stub).to be true
    end

    it 'allows body to be modified' do
      issue = described_class.new(issue_data)
      expect { issue.body = 'Modified body' }.not_to raise_error
      expect(issue.body).to eq('Modified body')
    end
  end
end
