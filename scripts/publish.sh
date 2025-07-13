#!/bin/bash
# Manual publishing script for Ruby gem projects

set -e

# Parse command line arguments
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--dry-run]"
      exit 1
      ;;
  esac
done

# Load common build functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/build-common.sh"

# Project-specific configuration
PROJECT_NAME="issuer"
DOCKER_ORG="docopslab"

echo -e "${GREEN}📦 ${PROJECT_NAME} Publishing Script${NC}"
echo "=============================="

# Check for required environment variables (skip in dry-run mode)
if [ "$DRY_RUN" = false ]; then
    if [ -z "$RUBYGEMS_API_KEY" ]; then
        echo -e "${RED}❌ Error: RUBYGEMS_API_KEY environment variable not set${NC}"
        echo "Get your API key from https://rubygems.org/profile/edit"
        echo "Then run: export RUBYGEMS_API_KEY=your_key_here"
        exit 1
    fi

    if [ -z "$DOCKERHUB_USERNAME" ] || [ -z "$DOCKERHUB_TOKEN" ]; then
        echo -e "${RED}❌ Error: Docker Hub credentials not set${NC}"
        echo "Set DOCKERHUB_USERNAME and DOCKERHUB_TOKEN environment variables"
        exit 1
    fi
fi

# Get current version
current_version=$(get_current_version)
gem_file="pkg/${PROJECT_NAME}-$current_version.gem"

# Check if gem file exists
if [ ! -f "$gem_file" ]; then
    echo -e "${RED}❌ Error: Gem file $gem_file not found${NC}"
    echo "Run ./scripts/build.sh first"
    exit 1
fi

if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}🔍 Dry run mode enabled. The following actions would be performed:${NC}"
  echo "- Publish to RubyGems: gem push $gem_file"
  echo "- Login to Docker Hub and push Docker images"
else
  # Publish to RubyGems
  echo -e "${YELLOW}💎 Publishing to RubyGems...${NC}"
  mkdir -p ~/.gem
  echo ":rubygems_api_key: $RUBYGEMS_API_KEY" > ~/.gem/credentials
  chmod 0600 ~/.gem/credentials
  gem push "$gem_file"
  echo -e "${GREEN}✅ Published to RubyGems successfully${NC}"

  # Login to Docker Hub
  echo -e "${YELLOW}🐳 Logging in to Docker Hub...${NC}"
  echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin

  # Push Docker images
  echo -e "${YELLOW}🐳 Pushing Docker images...${NC}"
  docker push ${DOCKER_ORG}/${PROJECT_NAME}:$current_version
  docker push ${DOCKER_ORG}/${PROJECT_NAME}:latest
  echo -e "${GREEN}✅ Pushed Docker images successfully${NC}"
fi

echo
echo -e "${GREEN}🎉 Publishing completed successfully!${NC}"
echo "=============================="
echo -e "Gem: ${YELLOW}https://rubygems.org/gems/${PROJECT_NAME}/versions/$current_version${NC}"
echo -e "Docker: ${YELLOW}https://hub.docker.com/r/${DOCKER_ORG}/${PROJECT_NAME}${NC}"
echo
echo "Verify installation:"
echo "  gem install ${PROJECT_NAME}"
echo "  docker pull ${DOCKER_ORG}/${PROJECT_NAME}:$current_version"
