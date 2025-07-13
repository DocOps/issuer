#!/bin/bash
# Manual publishing script for issuer gem and Docker image

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}📦 Issuer Publishing Script${NC}"
echo "=============================="

# Check for required environment variables
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

# Get current version
current_version=$(ruby -r './lib/issuer/version' -e 'puts Issuer::VERSION')
gem_file="issuer-$current_version.gem"

# Check if gem file exists
if [ ! -f "$gem_file" ]; then
    echo -e "${RED}❌ Error: Gem file $gem_file not found${NC}"
    echo "Run ./scripts/build.sh first"
    exit 1
fi

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
docker push docopslab/issuer:$current_version
docker push docopslab/issuer:latest
echo -e "${GREEN}✅ Pushed Docker images successfully${NC}"

echo
echo -e "${GREEN}🎉 Publishing completed successfully!${NC}"
echo "=============================="
echo -e "Gem: ${YELLOW}https://rubygems.org/gems/issuer/versions/$current_version${NC}"
echo -e "Docker: ${YELLOW}https://hub.docker.com/r/docopslab/issuer${NC}"
echo
echo "Verify installation:"
echo "  gem install issuer"
echo "  docker pull docopslab/issuer:$current_version"
