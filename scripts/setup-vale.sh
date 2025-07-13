#!/usr/bin/env bash
# Vale setup script for new developers
# This sets up Vale documentation linting for this project

set -e

echo "🔧 Setting up Vale for issuer project..."

# Check if Vale is installed, install if needed
if ! command -v vale &> /dev/null; then
    echo "📦 Installing Vale..."
    
    if command -v brew &> /dev/null; then
        echo "   Using Homebrew..."
        brew install vale
    elif command -v wget &> /dev/null; then
        echo "   Downloading Vale binary..."
        wget -O /tmp/vale.tar.gz https://github.com/errata-ai/vale/releases/download/v3.12.0/vale_3.12.0_Linux_64-bit.tar.gz
        cd /tmp && tar -xzf vale.tar.gz
        sudo mv vale /usr/local/bin/
        rm vale.tar.gz
    else
        echo "❌ Please install Vale manually:"
        echo "   https://github.com/errata-ai/vale/releases"
        echo "   Or install Homebrew/wget and run this script again"
        exit 1
    fi
    
    echo "✅ Vale installed successfully!"
else
    echo "✅ Vale already installed ($(vale --version))"
fi

# Sync Vale style packages
echo "🔄 Syncing Vale style packages..."
vale sync

# Install pre-commit hook if it doesn't exist
HOOK_FILE=".git/hooks/pre-commit"
if [[ ! -f "$HOOK_FILE" ]]; then
    echo "🪝 Installing pre-commit hook..."
    cp "scripts/pre-commit-template.sh" "$HOOK_FILE"
    chmod +x "$HOOK_FILE"
    echo "✅ Pre-commit hook installed!"
else
    echo "ℹ️  Pre-commit hook already exists"
fi

echo ""
echo "🎉 Vale setup complete!"
echo ""
echo "📖 Available commands:"
echo "   vale README.adoc           # Lint a specific file"
echo "   rake lint_docs             # Lint all documentation"
echo "   rake lint_readme           # Lint README only"
echo "   ./scripts/lint-docs.sh     # Run comprehensive linting"
echo ""
echo "🔍 Pre-commit hook will automatically check documentation on commit"
echo "   Use 'git commit --no-verify' to skip if needed"
