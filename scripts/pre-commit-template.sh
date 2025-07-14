#!/usr/bin/env bash
# Pre-commit hook for Vale linting

set -e

echo "🔍 Running Vale pre-commit check..."

# Check if Vale is installed
if ! command -v vale &> /dev/null; then
  echo "⚠️  Vale not found. Skipping documentation linting."
  echo "   Install Vale to enable documentation quality checks."
  exit 0
fi

# Get list of staged files that we care about (excluding copilot instructions)
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(md|adoc|asciidoc)$' | grep -v '^\.github/copilot-instructions\.md$' || true)

if [[ -z "$STAGED_FILES" ]]; then
  echo "ℹ️  No documentation files staged for commit."
  exit 0
fi

echo "📄 Checking staged documentation files:"
echo "$STAGED_FILES"

# Run Vale on staged files
TEMP_DIR=$(mktemp -d)
EXIT_CODE=0

for file in $STAGED_FILES; do
  if [[ -f "$file" ]]; then
    # Copy staged version to temp location
    git show :"$file" > "$TEMP_DIR/$(basename "$file")"
    
    echo "🔍 Linting: $file"
    if ! vale "$TEMP_DIR/$(basename "$file")"; then
        EXIT_CODE=1
    fi
  fi
done

# Cleanup
rm -rf "$TEMP_DIR"

if [[ $EXIT_CODE -ne 0 ]]; then
  echo ""
  echo "❌ Vale found documentation issues in staged files."
  echo "   Please fix the issues above before committing."
  echo "   Or use 'git commit --no-verify' to bypass this check."
  exit 1
fi

echo "✅ Documentation quality check passed!"
exit 0
