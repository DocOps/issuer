# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Issuer::Ops do
  describe '.process_issues_data' do
    it 'handles scalar string issues' do
      issues_data = ['String issue 1', 'String issue 2']
      defaults = {'vrsn' => '1.0.0'}

      issues = Issuer::Ops.process_issues_data(issues_data, defaults)

      expect(issues.length).to eq(2)
      expect(issues[0].summ).to eq('String issue 1')
      expect(issues[1].summ).to eq('String issue 2')
      expect(issues[0].vrsn).to eq('1.0.0')
    end

    it 'handles mixed scalar and hash issues' do
      issues_data = [
        'String issue',
        {'summ' => 'Hash issue', 'body' => 'Custom body'}
      ]
      defaults = {'user' => 'testuser'}

      issues = Issuer::Ops.process_issues_data(issues_data, defaults)

      expect(issues.length).to eq(2)
      expect(issues[0].summ).to eq('String issue')
      expect(issues[1].summ).to eq('Hash issue')
      expect(issues[1].body).to eq('Custom body')
    end
  end

  describe '.apply_tag_logic' do
    let(:issues) do
      [
        Issuer::Issue.new({'summ' => 'Issue with no tags'}, {}),
        Issuer::Issue.new({'summ' => 'Issue with tags', 'tags' => ['bug']}, {}),
        Issuer::Issue.new({'summ' => 'Issue with append tag', 'tags' => ['+critical']}, {})
      ]
    end

    it 'applies append tags to all issues' do
      result = Issuer::Ops.apply_tag_logic(issues, '+urgent,docs')

      expect(result[0].tags).to include('urgent')
      expect(result[1].tags).to include('urgent')
      expect(result[2].tags).to include('urgent')
    end

    it 'applies default tags only to issues without explicit tags' do
      result = Issuer::Ops.apply_tag_logic(issues, '+urgent,docs')

      # Issue with no tags should get default tags
      expect(result[0].tags).to include('docs')

      # Issue with explicit tags should not get default tags
      expect(result[1].tags).not_to include('docs')
      expect(result[1].tags).to include('bug')
    end

    it 'processes + prefix correctly in existing tags' do
      result = Issuer::Ops.apply_tag_logic(issues, 'docs')

      # Issue with +critical should have critical (without +) and docs
      expect(result[2].tags).to include('critical')
      expect(result[2].tags).to include('docs')
      expect(result[2].tags).not_to include('+critical')
    end
  end

  describe '.apply_stub_logic' do
    let(:defaults) do
      {
        'stub' => true,
        'head' => 'HEADER',
        'body' => 'DEFAULT BODY',
        'tail' => 'FOOTER'
      }
    end

    it 'applies stub components when stub is true' do
      issues = [
        Issuer::Issue.new({'summ' => 'Test', 'stub' => true}, defaults)
      ]

      result = Issuer::Ops.apply_stub_logic(issues, defaults)

      expect(result[0].body).to eq("HEADER\nDEFAULT BODY\nFOOTER")
    end

    it 'does not apply stub components when stub is false' do
      issues = [
        Issuer::Issue.new({'summ' => 'Test', 'body' => 'Custom', 'stub' => false}, defaults)
      ]

      result = Issuer::Ops.apply_stub_logic(issues, defaults)

      expect(result[0].body).to eq('Custom')
    end

    it 'uses default stub setting when issue-level stub is not specified' do
      issues = [
        Issuer::Issue.new({'summ' => 'Test'}, defaults)
      ]

      result = Issuer::Ops.apply_stub_logic(issues, defaults)

      expect(result[0].body).to eq("HEADER\nDEFAULT BODY\nFOOTER")
    end

    it 'handles missing stub components gracefully' do
      minimal_defaults = {'stub' => true, 'body' => 'BODY ONLY'}
      issues = [
        Issuer::Issue.new({'summ' => 'Test'}, minimal_defaults)
      ]

      result = Issuer::Ops.apply_stub_logic(issues, minimal_defaults)

      expect(result[0].body).to eq('BODY ONLY')
    end
  end

  describe '.validate_and_prepare_resources' do
    let(:mock_site) do
      double('Site').tap do |site|
        allow(site).to receive(:site_name).and_return('github')
        allow(site).to receive(:get_versions).and_return([])
        allow(site).to receive(:get_tags).and_return([])
        allow(site).to receive(:create_version).and_return({
          object: double(number: 1, title: 'test-milestone'),
          tracking_data: { number: 1, title: 'test-milestone' }
        })
        allow(site).to receive(:create_tag).and_return({
          object: double(name: 'test-label'),
          tracking_data: { name: 'test-label' }
        })
      end
    end

    let(:mock_issue) do
      double('Issue').tap do |issue|
        allow(issue).to receive(:vrsn).and_return('0.3.0')
        allow(issue).to receive(:tags).and_return(['test-label'])
      end
    end

    let(:proj) { 'test-org/test-repo' }
    let(:issues) { [mock_issue] }

    # Mock STDIN to avoid hanging on user input in all tests
    before do
      allow(STDIN).to receive(:gets).and_return("n\n")
    end

    context 'with auto_versions enabled' do
      it 'creates missing milestones automatically' do
        automation_options = { auto_versions: true, auto_tags: false }
        
        # Expect the milestone to be created
        expect(mock_site).to receive(:create_version).with(proj, '0.3.0')
        
        # Capture stdout but don't hang on complex output matching
        output = capture_stdout do
          Issuer::Ops.validate_and_prepare_resources(mock_site, proj, issues, automation_options)
        end
        
        expect(output).to include('Auto-creating milestone: 0.3.0')
      end
    end

    context 'with auto_tags enabled' do
      it 'creates missing labels automatically' do
        automation_options = { auto_versions: false, auto_tags: true }
        
        # Expect the label to be created
        expect(mock_site).to receive(:create_tag).with(proj, 'test-label')
        
        # Capture stdout but don't hang on complex output matching
        output = capture_stdout do
          Issuer::Ops.validate_and_prepare_resources(mock_site, proj, issues, automation_options)
        end
        
        expect(output).to include('Auto-creating label: test-label')
      end
    end

    context 'with auto_metadata functionality (both auto_versions and auto_tags)' do
      it 'creates both missing milestones and labels automatically' do
        automation_options = { auto_versions: true, auto_tags: true }
        
        # Expect both milestone and label to be created
        expect(mock_site).to receive(:create_version).with(proj, '0.3.0')
        expect(mock_site).to receive(:create_tag).with(proj, 'test-label')
        
        # Capture stdout but don't hang on complex output matching
        output = capture_stdout do
          Issuer::Ops.validate_and_prepare_resources(mock_site, proj, issues, automation_options)
        end
        
        expect(output).to include('Auto-creating milestone: 0.3.0')
        expect(output).to include('Auto-creating label: test-label')
      end
    end

    context 'with empty issues array' do
      it 'returns early without processing' do
        automation_options = { auto_versions: true, auto_tags: true }
        
        # Should not make any API calls
        expect(mock_site).not_to receive(:get_versions)
        expect(mock_site).not_to receive(:get_tags)
        
        Issuer::Ops.validate_and_prepare_resources(mock_site, proj, [], automation_options)
      end
    end

    # Helper method for capturing stdout without hanging
    def capture_stdout
      original_stdout = $stdout
      $stdout = StringIO.new
      yield
      $stdout.string
    ensure
      $stdout = original_stdout
    end
  end
end
