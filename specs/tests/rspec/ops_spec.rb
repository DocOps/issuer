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
end
