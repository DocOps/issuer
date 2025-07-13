#!/usr/bin/env bash
# Vale linting script for the issuer project

set -e

echo "🔍 Running Vale linter on issuer project..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Vale is installed
if ! command -v vale &> /dev/null; then
  echo -e "${RED}❌ Vale is not installed. Please install Vale first.${NC}"
  echo "   You can install it from: https://github.com/errata-ai/vale"
  exit 1
fi

# Check if .vale.ini exists
if [[ ! -f ".vale.ini" ]]; then
  echo -e "${RED}❌ .vale.ini not found in current directory${NC}"
  echo "   Please run this script from the project root."
  exit 1
fi

# Default to checking all relevant files if no arguments provided
if [[ $# -eq 0 ]]; then
  FILES=(
    "README.adoc"
    "lib/examples/*.md"
    "specs/tests/*.md" 
    "*.adoc"
    "docs/*.adoc"
  )
else
  FILES=("$@")
fi

echo "📁 Files to check: ${FILES[*]}"
echo ""

# Run Vale
EXIT_CODE=0
for pattern in "${FILES[@]}"; do
  # Use find to expand patterns and handle missing files gracefully
  while IFS= read -r -d '' file; do
    if [[ -f "$file" ]]; then
      echo -e "${YELLOW}📄 Checking: $file${NC}"
      if ! vale "$file"; then
        EXIT_CODE=1
      fi
    fi
  done < <(find . -name "$pattern" -print0 2>/dev/null)
done

if [[ $EXIT_CODE -eq 0 ]]; then
  echo -e "${GREEN}✅ Vale linting completed successfully!${NC}"
else
  echo -e "${RED}❌ Vale found issues. Please review and fix them.${NC}"
fi

exit $EXIT_CODE
