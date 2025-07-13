#!/usr/bin/env zsh
# Quick GitHub connectivity test for issuer CLI

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

echo
echo -e "${BLUE}🔍 GitHub Connectivity Check${NC}"
echo -e "${BLUE}=============================${NC}"
echo

# Check for GitHub tokens
echo "Checking for GitHub authentication tokens..."
token_found=false

if [[ -n "$ISSUER_API_TOKEN" ]]; then
    print_success "ISSUER_API_TOKEN found (length: ${#ISSUER_API_TOKEN})"
    token_found=true
fi

if [[ -n "$ISSUER_GITHUB_TOKEN" ]]; then
    print_success "ISSUER_GITHUB_TOKEN found (length: ${#ISSUER_GITHUB_TOKEN})"
    token_found=true
fi

if [[ -n "$GITHUB_ACCESS_TOKEN" ]]; then
    print_success "GITHUB_ACCESS_TOKEN found (length: ${#GITHUB_ACCESS_TOKEN})"
    token_found=true
fi

if [[ -n "$GITHUB_TOKEN" ]]; then
    print_success "GITHUB_TOKEN found (length: ${#GITHUB_TOKEN})"
    token_found=true
fi

if [[ "$token_found" == "false" ]]; then
    print_error "No GitHub tokens found!"
    echo
    print_info "Please set one of the following environment variables:"
    echo "  export ISSUER_API_TOKEN='your_token_here'"
    echo "  export ISSUER_GITHUB_TOKEN='your_token_here'"
    echo "  export GITHUB_ACCESS_TOKEN='your_token_here'"
    echo "  export GITHUB_TOKEN='your_token_here'"
    echo
    exit 1
fi

echo

# Test issuer CLI basic functionality
echo "Testing issuer CLI availability..."
if command -v issuer >/dev/null 2>&1; then
    print_success "issuer command found"
    
    # Test version
    echo -n "Version: "
    issuer --version || print_warning "Could not get version"
    echo
else
    print_error "issuer command not found"
    print_info "Make sure issuer is installed and in PATH"
    print_info "From project directory: bundle exec bin/issuer --version"
    echo
    exit 1
fi

# Test basic GitHub API connectivity using a minimal test
echo "Testing GitHub API connectivity..."

# Create a minimal test file
test_file=$(mktemp -t issuer-connectivity-test.XXXXXX.yml)
cat > "$test_file" << EOF
\$meta:
  proj: octocat/Hello-World  # Public GitHub repository for testing

issues:
  - summ: "[CONNECTIVITY-TEST] This is just a connectivity test"
    body: |
      # GitHub API Connectivity Test
      
      This is a test to verify that the issuer CLI can connect to GitHub API.
      
      **This should NOT be created** - we're running in dry-run mode only.
EOF

echo "Running dry-run test against GitHub API..."
if issuer "$test_file" --dry >/dev/null 2>&1; then
    print_success "GitHub API connectivity working!"
else
    print_error "GitHub API connectivity failed"
    print_info "Try running manually for more details:"
    echo "  issuer $test_file --dry"
    rm -f "$test_file"
    exit 1
fi

# Clean up
rm -f "$test_file"

echo
print_success "All connectivity checks passed! 🎉"
echo
print_info "You're ready to run the GitHub API integration tests:"
echo "  ./specs/tests/run-github-api-tests.sh --help"
echo
print_info "Or run a quick manual test:"
echo "  issuer examples/minimal-example.yml --dry"
echo
