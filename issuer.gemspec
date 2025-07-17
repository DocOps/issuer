require_relative 'lib/issuer/version'

Gem::Specification.new do |spec|
  spec.name          = "issuer"
  spec.version       = Issuer::VERSION
  spec.authors       = ["DocOps Lab"]
  spec.email         = ["codewriter@protonmail.com"]

  spec.summary       = "Bulk GitHub issue creator from YAML definitions"
  spec.description   = "CLI tool for creating multiple GitHub issues from a single YAML file (IMYML format). Define all your issues in one place, apply defaults, and post them to GitHub in bulk."
  spec.homepage      = "https://github.com/DocOps/issuer"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/DocOps/issuer"
  spec.metadata["changelog_uri"] = "https://github.com/DocOps/issuer/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://gemdocs.org/gems/issuer/#{Issuer::VERSION}"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir['lib/**/*.rb'] +
               ['exe/issuer'] +
               ['README.adoc', 'LICENSE', 'issuer.gemspec'] +
               Dir['examples/*.yml']
  
  spec.bindir = "exe"
  spec.executables = ["issuer"]
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "octokit", "~> 8.0"
  spec.add_dependency "thor", "~> 1.0"
  spec.add_dependency "faraday-retry", "~> 2.0"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "asciidoctor", "~> 2.0"
end
