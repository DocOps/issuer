#!/bin/bash
# Release automation script for issuer gem

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Issuer Release Build Script${NC}"
echo "=================================="

# Check if we're in the right directory
if [ ! -f "issuer.gemspec" ]; then
    echo -e "${RED}❌ Error: issuer.gemspec not found. Run this script from the project root.${NC}"
    exit 1
fi

# Check for clean git status
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${RED}❌ Error: Working directory is not clean. Commit or stash changes first.${NC}"
    git status --short
    exit 1
fi

# Check if on main branch
current_branch=$(git branch --show-current)
if [ "$current_branch" != "main" ]; then
    echo -e "${YELLOW}⚠️  Warning: Not on main branch (currently on: $current_branch)${NC}"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# Run tests
echo -e "${YELLOW}🧪 Running tests...${NC}"
bundle exec rspec specs/tests/rspec/
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Tests failed. Fix tests before releasing.${NC}"
    exit 1
fi

# Test CLI functionality
echo -e "${YELLOW}🧪 Testing CLI functionality...${NC}"
ruby -Ilib exe/issuer --version
ruby -Ilib exe/issuer examples/minimal-example.yml --dry

# Get current version
current_version=$(ruby -r './lib/issuer/version' -e 'puts Issuer::VERSION')
echo -e "${GREEN}📋 Current version: $current_version${NC}"

# Build gem
echo -e "${YELLOW}🔨 Building gem...${NC}"
mkdir -p pkg/
gem build issuer.gemspec
mv issuer-*.gem pkg/

# Test the built gem
echo -e "${YELLOW}🧪 Testing built gem...${NC}"
gem_file=$(ls pkg/issuer-*.gem | sort -V | tail -n1)
echo "Testing gem file: $gem_file"

# Create temporary directory for testing
test_dir=$(mktemp -d)
cd "$test_dir"
gem install "../$gem_file" --user-install
if ! command -v issuer &> /dev/null; then
    echo -e "${YELLOW}⚠️  issuer command not in PATH. Adding gem bin directory...${NC}"
    export PATH="$HOME/.local/share/gem/ruby/$(ruby -e 'puts RUBY_VERSION')/bin:$PATH"
fi

# Test installed gem
issuer --version
cd - > /dev/null
rm -rf "$test_dir"

echo -e "${GREEN}✅ Gem built and tested successfully: $gem_file${NC}"

# Build Docker image
echo -e "${YELLOW}🐳 Building Docker image...${NC}"
docker build -t docopslab/issuer:$current_version .
docker tag docopslab/issuer:$current_version docopslab/issuer:latest

# Test Docker image
echo -e "${YELLOW}🧪 Testing Docker image...${NC}"
docker run --rm -v $(pwd):/workdir docopslab/issuer:$current_version issuer --version
docker run --rm -v $(pwd):/workdir docopslab/issuer:$current_version issuer examples/minimal-example.yml --dry

echo -e "${GREEN}✅ Docker image built and tested successfully${NC}"

echo
echo -e "${GREEN}🎉 Build completed successfully!${NC}"
echo "=================================="
echo -e "Gem file: ${YELLOW}$gem_file${NC}"
echo -e "Docker image: ${YELLOW}docopslab/issuer:$current_version${NC}"
echo -e "Docker image: ${YELLOW}docopslab/issuer:latest${NC}"
echo
echo "Next steps:"
echo "1. Review the CHANGELOG.md"
echo "2. Push to GitHub: git push origin main"
echo "3. Create a GitHub release to trigger automated publishing"
echo "4. Or manually publish with: ./scripts/publish.sh"
