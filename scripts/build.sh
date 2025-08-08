#!/bin/bash
# Release automation script for Ruby gem projects

set -e

# Load common build functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/build-common.sh"

# Project-specific configuration
PROJECT_NAME="issuer"
DOCKER_ORG="docopslab"

echo -e "${GREEN}🚀 ${PROJECT_NAME} Release Build Script${NC}"
echo "=================================="

# Validation
check_project_root
check_git_clean
check_main_branch
check_bundle_installed
check_docker_available

# Run tests
run_rspec_tests
test_cli_functionality

# Get current version
current_version=$(get_current_version)
echo -e "${GREEN}📋 Current version: $current_version${NC}"

# Build and test gem
build_gem
gem_file=$(test_built_gem)

# Build Docker image using the docker-specific script
echo -e "${YELLOW}🐳 Building Docker image...${NC}"
"$SCRIPT_DIR/build-docker.sh" 2>&1 | grep -E "(Building|Testing|successfully|Docker image:)" || true

# Show final success message
show_build_success "$current_version" "$gem_file"
