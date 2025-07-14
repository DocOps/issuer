require "bundler/setup"
require "issuer"
require "yaml"
require "tempfile"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

# Helper methods for tests
def create_temp_yaml_file content
  file = Tempfile.new(['test', '.yml'])
  if content.is_a?(Hash)
    file.write(YAML.dump(content))
  else
    file.write(content)
  end
  file.close
  file.path
end

def sample_imyml_content
  {
    '$meta' => {
      'proj' => 'test/repo',
      'defaults' => {
        'vrsn' => '1.0.0',
        'user' => 'testuser',
        'tags' => ['enhancement', '+automated'],
        'stub' => true,
        'head' => 'HEADER TEXT',
        'body' => 'DEFAULT BODY',
        'tail' => 'FOOTER TEXT'
      }
    },
    'issues' => [
      {
        'summ' => 'Test issue 1',
        'body' => 'Test description',
        'tags' => ['bug'],
        'stub' => false
      },
      'Simple string issue'
    ]
  }
end
