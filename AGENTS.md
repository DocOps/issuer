# AGENTS.md

AI Agent Guide for Issuer Development


## Philosophy: Documentation-First, Senior Engineer Mindset

As an AI agent working on Issuer, approach this codebase like an **inquisitive and opinionated senior engineer** who values:

- **Documentation-first development**: Always read the docs first, understand the architecture, then propose solutions at least in part by drafting docs changes
- **Investigative depth**: Don't assume - investigate, understand, then act
- **Architectural awareness**: Consider system-wide impacts of changes
- **Test-driven confidence**: Validate changes don't break existing functionality
- **User experience focus**: Changes should improve the developer/end-user experience


## Operations Notes

### Ephemeral Directory

There will always be an untracked `.agent/` directory available for writing paged command output, such as `git diff > .agent/current.diff && cat .agent/current.diff`.

### AsciiDoc, not Markdown

Agents have a frustrating tendency to create `.md` files when users do not want them, and you also write Markdown syntax inside `.adoc` files.
Stick to the AsciiDoc syntax and styles found in the `README.adoc` files, and you won't go too far wrong.

NEVER create `.md` files unless user asks you to.


## Essential Reading Order (Start Here!)

Before making any changes, **read these documents in order**:

### 1. Core Documentation
- **`./README.adoc`**
- Main project overview, features, and workflow examples:
  - Pay special attention to any AI prompt sections (`// tag::ai-prompt[]`...`// end::ai-prompt[]`)
  - Study the example CLI usage patterns
- Review `issuer.gemspec` and `Dockerfile` for dependencies and environment context

### 2. Architecture Understanding
- **`./specs/tests/README.adoc`** 
- Test framework and validation patterns:
  - Understand the test structure and helper functions
  - See how integration testing works with demo data
  - Note the current test coverage and planned expansions

### 3. Practical Examples
- **`./examples/`** directory contains IMYML example files
- Study the basic and advanced example files to understand IMYML format
- Check `examples/README.adoc` for examples documentation

### 4. Development Standards
- **`./.github/copilot-instructions.md`** 
- Coding style requirements:
  - AsciiDoc for ALL documentation (not Markdown)
  - Ruby style guidelines (parentheses usage, etc.)


## Codebase Architecture

### Core Components

```
lib/
├── issuer.rb           # Main module and version
├── issuer/
│   ├── cli.rb         # Thor-based CLI interface
│   ├── issue.rb       # Issue model and validation
│   ├── ops.rb         # Core operations and processing
│   └── site.rb        # GitHub API integration
exe/
└── issuer             # CLI executable
specs/
├── tests/rspec/       # RSpec unit tests
└── tests/github-api/  # Integration tests
```

### Auxiliary Components

Currently no auxiliary components are planned to be spun off as separate gems.

### Data Flow Understanding

1. **IMYML File Parsing**: CLI reads YAML file containing issue definitions
2. **Issue Processing**: `Ops.process_issues_data` converts raw data to `Issue` objects
3. **Validation**: Each issue is validated for required fields and proper format
4. **GitHub API Integration**: `Site` class handles authentication and API calls
5. **Bulk Creation**: Issues are created one by one via GitHub REST API
6. **Logging**: All operations are logged for tracking and potential cleanup

### Configuration System

Issuer uses a simpler configuration model than typical DocOps Lab projects:
- **CLI Options**: Primary configuration via command-line flags
- **IMYML Files**: Issue definitions and defaults in YAML format
- **Environment Variables**: Authentication tokens via env vars
- **No separate config files**: Configuration is embedded in IMYML `$meta` blocks


## Agent Development Approach

### Before Coding: Investigate Phase

1. **Read the relevant documentation sections** for the area you're changing
2. **Run the existing tests** to understand current behavior:
   ```bash
   bundle exec rspec specs/tests/rspec --format documentation
   ```
3. **Explore the demo** to see real usage:
   ```bash
   cd examples/
   issuer basic-example.yml --dry
   ```
4. **Check IMYML format** in example files for any format-related changes
5. **See the `Rakefile`** to get up to speed on dev workflows and automation.

### Development Patterns

#### 1.Configuration Changes
- Never hardcode defaults - use the Configuration class
- Update `specs/(data/)?config-def.yml` with new properties and their defaults
- Test configuration loading with various scenarios

#### 2. CLI Changes
- Follow Thor patterns established in `cli.rb`
- Use existing option naming conventions
   - Prefer Boolean flags over Boolean option values (ex: `--thing`/`--no-thing` instead of `--thing true|false`)

#### 3. IMYML Format Changes
- Follow existing IMYML structure in `examples/`
- Update documentation when extending the format
- Maintain backward compatibility with existing files

#### 4. GitHub API Integration
- Use existing Site class patterns for API calls
- Handle rate limiting and error responses gracefully
- Test with actual GitHub API when possible

### Testing Strategy

1. **Run existing tests first**: `bundle exec rspec`
2. **Add tests for new functionality** (see examples and locate an appropriate file (or create anew) in `specs/tests/rspec/`)
3. **Test with demo data**: Use `examples/` directory files to validate real-world scenarios
4. **Validate configuration changes**: Ensure config loading still works

### Code Quality Standards

#### Documentation
- **AsciiDoc for prose documentation and structure** (README files, config comments, etc.)
- **README.adoc attributes for core data** README.adoc is single source of truth for core non-config data (version, key URLs, etc)
- **YAML definition/schema files** for all reference data outside README
- **Ruby comments** for code explanation and Ruby RDoc/YARD markup (to be implemented)
- **Update relevant documentation** when adding features

#### Ruby Style  
- **No parentheses in block/class definitions**: `def method_name arg1, arg2:`
- **Use parentheses in method calls**: `method_call(arg)`
- **Follow existing patterns** for consistency

#### Architecture
- **Separation of concerns**: Keep CLI, operations, and data processing separate
- **Configuration-driven**: Make features configurable rather than hardcoded
- **Error handling**: Provide helpful error messages with context
- **Logging**: via structured logging to config directories

## Common Development Scenarios

### Adding a New CLI Option

1. **Investigate**: Check existing options in `cli.rb` and their patterns
2. **Document**: CLI messages are first recorded as AsciiDoc attributes in `README.adoc`
   - Something like: `{cli_option_<keyname>_message}`
3. **Thor CLI** in `lib/issuer/cli.rb`: Add to Thor options with proper description from generated attributes
4. **Process**: Handle the option in the appropriate method (usually `default`)
5. **Test**: Add CLI tests in `specs/tests/rspec/cli_spec.rb`
6. **Double-check the docs**: Make sure any changes made since the initial docs are reflected.
7. **Search and fix references** that may be affected by this change throughout existing docs (`.adoc`) and scripts (`.rb`, `.sh`, `Rakefile`)


## Debugging and Investigation Tools

### Understanding Current State
```bash
# Test CLI functionality
issuer --version

# Test with example data
issuer examples/basic-example.yml --dry

# Run all tests to understand current functionality
bundle exec rspec specs/tests/rspec --format documentation
```

### Key Files for Understanding
- `lib/issuer.rb` - Main module, logging, core setup
- `lib/issuer/cli.rb` - All CLI logic and option processing
- `lib/issuer/issue.rb` - Issue model and validation
- `lib/issuer/ops.rb` - Core operations and processing
- `lib/issuer/site.rb` - GitHub API integration
- `examples/` - IMYML format examples and documentation
- Test files in `specs/tests/rspec/` - Show expected behaviors


## Working with Demo Data

The `examples/` directory contains various IMYML files demonstrating different features:

- `basic-example.yml` - Simple issue creation
- `advanced-example.yml` - Complex configurations with defaults
- Use these files with `--dry` flag to test changes without creating real issues


## Agent Responsibilities

### As a Senior Engineer Agent:

1. **Question Requirements**: Ask clarifying questions about specifications
2. **Propose Better Solutions**: If you see architectural improvements, suggest them
3. **Consider Edge Cases**: Think about error conditions and unusual inputs  
4. **Maintain Backward Compatibility**: Don't break existing workflows
5. **Improve Documentation**: Update docs when adding features
6. **Test Thoroughly**: Use both unit tests and demo validation

### Be Opinionated About:

- Code architecture and separation of concerns
- Configuration management patterns  
- Error handling and user experience
- Documentation quality and completeness
- Test coverage and quality

### Be Inquisitive About:

- Why existing patterns were chosen
- What the user experience implications are
- How changes affect different API platforms
- Whether configuration is flexible enough
- What edge cases might exist


## Remember

Issuer is designed for project managers and developers who need to create GitHub Issues in bulk from structured definitions. The primary users are teams managing software development cycles using Git tools and GitHub Issues.

1. **Reliability**: Don't break existing functionality
2. **Usability**: Make the CLI intuitive and helpful
3. **Flexibility**: Support diverse team workflows and preferences  
4. **Performance**: Respect rate limits, cache intelligently
5. **Documentation**: Keep the docs current and comprehensive

**Most importantly**: Read the documentation first, understand the system, then propose thoughtful solutions that improve the overall architecture and user experience.
