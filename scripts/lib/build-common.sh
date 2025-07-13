#!/bin/bash
# Common build functions for Ruby gem projects
# This library provides reusable functions for building gems and Docker images

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Project configuration - these should be set by the calling script
PROJECT_NAME="${PROJECT_NAME:-$(basename $(pwd))}"
DOCKER_ORG="${DOCKER_ORG:-docopslab}"
GEMSPEC_FILE="${GEMSPEC_FILE:-${PROJECT_NAME}.gemspec}"
CLI_EXECUTABLE="${CLI_EXECUTABLE:-exe/${PROJECT_NAME}}"
EXAMPLE_FILE="${EXAMPLE_FILE:-examples/minimal-example.yml}"
TEST_SPEC_PATH="${TEST_SPEC_PATH:-specs/tests/rspec/}"

# Common validation functions
check_project_root() {
    if [ ! -f "$GEMSPEC_FILE" ]; then
        echo -e "${RED}❌ Error: $GEMSPEC_FILE not found. Run this script from the project root.${NC}"
        exit 1
    fi
}

check_docker_available() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Error: Docker is not installed or not in PATH${NC}"
        exit 1
    fi
}

check_git_clean() {
    if [ -n "$(git status --porcelain)" ]; then
        echo -e "${RED}❌ Error: Working directory is not clean. Commit or stash changes first.${NC}"
        git status --short
        exit 1
    fi
}

check_main_branch() {
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
}

check_bundle_installed() {
    if [ ! -f "Gemfile" ]; then
        echo -e "${YELLOW}⚠️  Warning: No Gemfile found. Some operations may require dependencies.${NC}"
        return
    fi
    
    if ! bundle check > /dev/null 2>&1; then
        echo -e "${YELLOW}📦 Installing gem dependencies...${NC}"
        bundle install
    fi
}

# Get current version from README.adoc by parsing directly
get_current_version() {
    grep '^:this_prod_vrsn:' README.adoc | sed 's/^:this_prod_vrsn:[[:space:]]*//' | tr -d '\r'
}

# Get next version from README.adoc by parsing directly
get_next_version() {
    grep '^:next_prod_vrsn:' README.adoc | sed 's/^:next_prod_vrsn:[[:space:]]*//' | tr -d '\r'
}

# Docker build and test functions
build_docker_image() {
    local version=$1
    local docker_args="${2:-}"
    
    echo -e "${YELLOW}🐳 Building Docker image...${NC}"
    docker build $docker_args -t ${DOCKER_ORG}/${PROJECT_NAME}:${version} .
    docker tag ${DOCKER_ORG}/${PROJECT_NAME}:${version} ${DOCKER_ORG}/${PROJECT_NAME}:latest
}

test_docker_image() {
    local version=$1
    local image_name="${DOCKER_ORG}/${PROJECT_NAME}:${version}"
    
    echo -e "${YELLOW}🧪 Testing Docker image...${NC}"
    docker run --rm -v $(pwd):/workdir ${image_name} --version
    
    if [ -f "$EXAMPLE_FILE" ]; then
        docker run --rm -v $(pwd):/workdir ${image_name} ${EXAMPLE_FILE} --dry
    fi
}

# Test functions
run_rspec_tests() {
    echo -e "${YELLOW}🧪 Running tests...${NC}"
    bundle exec rspec $TEST_SPEC_PATH
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Tests failed. Fix tests before releasing.${NC}"
        exit 1
    fi
}

test_cli_functionality() {
    echo -e "${YELLOW}🧪 Testing CLI functionality...${NC}"
    bundle exec ruby -Ilib $CLI_EXECUTABLE --version
    
    if [ -f "$EXAMPLE_FILE" ]; then
        bundle exec ruby -Ilib $CLI_EXECUTABLE $EXAMPLE_FILE --dry
    fi
}

# Gem build functions
build_gem() {
    echo -e "${YELLOW}🔨 Building gem...${NC}"
    mkdir -p pkg/
    gem build $GEMSPEC_FILE
    mv ${PROJECT_NAME}-*.gem pkg/
}

test_built_gem() {
    echo -e "${YELLOW}🧪 Testing built gem...${NC}"
    gem_file=$(ls pkg/${PROJECT_NAME}-*.gem | sort -V | tail -n1)
    echo "Testing gem file: $gem_file"
    
    # Create temporary directory for testing
    test_dir=$(mktemp -d)
    cd "$test_dir"
    gem install "../$gem_file" --user-install
    
    if ! command -v $PROJECT_NAME &> /dev/null; then
        echo -e "${YELLOW}⚠️  $PROJECT_NAME command not in PATH. Adding gem bin directory...${NC}"
        export PATH="$HOME/.local/share/gem/ruby/$(ruby -e 'puts RUBY_VERSION')/bin:$PATH"
    fi
    
    # Test installed gem
    $PROJECT_NAME --version
    cd - > /dev/null
    rm -rf "$test_dir"
    
    echo -e "${GREEN}✅ Gem built and tested successfully: $gem_file${NC}"
    echo "$gem_file"
}

# Display functions
show_docker_success() {
    local version=$1
    echo -e "${GREEN}✅ Docker image built and tested successfully${NC}"
    echo
    echo -e "${GREEN}🎉 Docker build completed successfully!${NC}"
    echo "=================================="
    echo -e "Docker image: ${YELLOW}${DOCKER_ORG}/${PROJECT_NAME}:${version}${NC}"
    echo -e "Docker image: ${YELLOW}${DOCKER_ORG}/${PROJECT_NAME}:latest${NC}"
}

show_build_success() {
    local version=$1
    local gem_file=$2
    echo
    echo -e "${GREEN}🎉 Build completed successfully!${NC}"
    echo "=================================="
    echo -e "Gem file: ${YELLOW}$gem_file${NC}"
    echo -e "Docker image: ${YELLOW}${DOCKER_ORG}/${PROJECT_NAME}:${version}${NC}"
    echo -e "Docker image: ${YELLOW}${DOCKER_ORG}/${PROJECT_NAME}:latest${NC}"
    echo
    echo "Next steps:"
    echo "1. Review the CHANGELOG.md"
    echo "2. Push to GitHub: git push origin main"
    echo "3. Create a GitHub release to trigger automated publishing"
    echo "4. Or manually publish with: ./scripts/publish.sh"
}
