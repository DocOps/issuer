#!/bin/bash
# Docker-only build script - idempotent and safe for local testing

set -e

# Load common build functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/build-common.sh"

# Project-specific configuration
PROJECT_NAME="issuer"
DOCKER_ORG="docopslab"

echo -e "${GREEN}🐳 ${PROJECT_NAME} Docker Build Script${NC}"
echo "=================================="

# Validation
check_project_root
check_docker_available

# Get current version
current_version=$(get_current_version)
echo -e "${GREEN}📋 Current version: $current_version${NC}"

# Check if gem exists in pkg/, if not build it
gem_file="pkg/${PROJECT_NAME}-$current_version.gem"
if [ ! -f "$gem_file" ]; then
    echo -e "${YELLOW}🔨 Gem not found in pkg/. Building gem first...${NC}"
    check_bundle_installed
    build_gem
    echo -e "${GREEN}✅ Gem built: $gem_file${NC}"
else
    echo -e "${GREEN}📋 Using existing gem: $gem_file${NC}"
fi

# Build and test Docker image
build_docker_image "$current_version"
test_docker_image "$current_version"

# Show success message
show_docker_success "$current_version"

echo
echo "Test the image with:"
echo "  docker run --rm -v \$(pwd):/workdir ${DOCKER_ORG}/${PROJECT_NAME}:$current_version --version"
echo "  docker run --rm -v \$(pwd):/workdir -e GITHUB_TOKEN=\$GITHUB_TOKEN ${DOCKER_ORG}/${PROJECT_NAME}:$current_version your-file.yml --dry"
