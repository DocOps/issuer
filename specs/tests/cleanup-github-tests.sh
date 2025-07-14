#!/usr/bin/env zsh
# GitHub Test Cleanup Script
# Helps clean up test issues, milestones, and labels created during testing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TEST_REPO=""
DRY_RUN=false
INTERACTIVE=true

print_header() {
    echo
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}  🧹 GitHub Test Cleanup Script          ${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo
}

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

show_help() {
    echo "GitHub Test Cleanup Script"
    echo
    echo "Usage: $0 [options] REPOSITORY"
    echo
    echo "Arguments:"
    echo "  REPOSITORY          GitHub repository (user/repo or org/repo)"
    echo
    echo "Options:"
    echo "  --help, -h          Show this help message"
    echo "  --dry-run, -n       Show what would be done without making changes"
    echo "  --non-interactive   Run without prompts"
    echo "  --issues-only       Only clean up issues, not milestones/labels"
    echo "  --milestones-only   Only clean up milestones"
    echo "  --labels-only       Only clean up labels"
    echo
    echo "Environment Variables:"
    echo "  GITHUB_TOKEN        GitHub personal access token (required)"
    echo
    echo "Examples:"
    echo "  $0 myuser/test-repo                    # Interactive cleanup"
    echo "  $0 --dry-run myuser/test-repo          # Show what would be cleaned"
    echo "  $0 --issues-only myuser/test-repo     # Only close test issues"
    echo
}

cleanup_issues() {
    local repo="$1"
    
    print_info "Searching for test issues in $repo..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN: Would search for and close issues with titles containing '[TEST]'"
        echo "Command that would be run:"
        echo "  gh issue list --repo $repo --search '[TEST]' --state open"
        echo "  gh issue close --repo $repo [issue_numbers]"
    else
        # Get open test issues
        local issue_numbers
        issue_numbers=$(gh issue list --repo "$repo" --search '[TEST]' --state open --json number --jq '.[].number' 2>/dev/null || echo "")
        
        if [[ -z "$issue_numbers" ]]; then
            print_info "No open test issues found to close"
        else
            print_info "Found open test issues to close:"
            echo "$issue_numbers" | while read number; do
                [[ -n "$number" ]] && echo "  - Issue #$number"
            done
            
            if [[ "$INTERACTIVE" == "true" ]]; then
                echo -n "Proceed with closing test issues? [y/N] "
                read -r response
                if [[ ! "$response" =~ ^[Yy]$ ]]; then
                    print_info "Issue cleanup skipped by user"
                    return
                fi
            fi
            
            print_info "Closing test issues..."
            echo "$issue_numbers" | while read number; do
                if [[ -n "$number" ]]; then
                    echo "  Closing issue #$number"
                    if gh issue close --repo "$repo" "$number" >/dev/null 2>&1; then
                        print_success "Closed issue #$number"
                    else
                        print_error "Failed to close issue #$number"
                    fi
                fi
            done
        fi
    fi
}

cleanup_milestones() {
    local repo="$1"
    
    print_info "Searching for test milestones in $repo..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN: Would search for and delete milestones containing 'test'"
        echo "Test milestone patterns to look for:"
        echo "  - test-milestone-*"
        echo "  - *-test-*"
        echo "  - auto-test-*"
        echo "  - complex-test-*"
    else
        # Get test milestones using GitHub API
        local milestones
        milestones=$(gh api "repos/$repo/milestones" 2>/dev/null | jq -r '.[] | select(.title | test("test|auto-test|complex-test|alias-test|individual-test")) | "\(.number) \(.title)"' 2>/dev/null || echo "")
        
        if [[ -z "$milestones" ]]; then
            print_info "No test milestones found to delete"
        else
            print_info "Found test milestones to delete:"
            echo "$milestones" | while read number title; do
                [[ -n "$number" ]] && echo "  - $title (#$number)"
            done
            
            if [[ "$INTERACTIVE" == "true" ]]; then
                echo -n "Proceed with deleting test milestones? [y/N] "
                read -r response
                if [[ ! "$response" =~ ^[Yy]$ ]]; then
                    print_info "Milestone cleanup skipped by user"
                    return
                fi
            fi
            
            print_info "Deleting test milestones..."
            echo "$milestones" | while read number title; do
                if [[ -n "$number" && -n "$title" ]]; then
                    echo "  Deleting milestone: $title (#$number)"
                    if gh api -X DELETE "repos/$repo/milestones/$number" >/dev/null 2>&1; then
                        print_success "Deleted milestone: $title"
                    else
                        print_error "Failed to delete milestone: $title"
                    fi
                fi
            done
        fi
    fi
}

cleanup_labels() {
    local repo="$1"
    
    print_info "Searching for test labels in $repo..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN: Would search for and delete labels containing 'test'"
        echo "Test label patterns to look for:"
        echo "  - test-*"
        echo "  - *-test"
        echo "  - auto-test-*"
        echo "  - comprehensive-test"
    else
        # Get test labels using gh CLI
        local labels
        labels=$(gh label list --repo "$repo" 2>/dev/null | grep -E "(test|auto-test|brand-new|individual|alias|comprehensive)" | cut -f1 2>/dev/null || echo "")
        
        if [[ -z "$labels" ]]; then
            print_info "No test labels found to delete"
        else
            print_info "Found test labels to delete:"
            echo "$labels" | while read label; do
                [[ -n "$label" ]] && echo "  - $label"
            done
            
            if [[ "$INTERACTIVE" == "true" ]]; then
                echo -n "Proceed with deleting test labels? [y/N] "
                read -r response
                if [[ ! "$response" =~ ^[Yy]$ ]]; then
                    print_info "Label cleanup skipped by user"
                    return
                fi
            fi
            
            print_info "Deleting test labels..."
            echo "$labels" | while read label; do
                if [[ -n "$label" ]]; then
                    echo "  Deleting label: $label"
                    if gh label delete --repo "$repo" "$label" --yes >/dev/null 2>&1; then
                        print_success "Deleted label: $label"
                    else
                        print_error "Failed to delete label: $label"
                    fi
                fi
            done
        fi
    fi
}

generate_cleanup_commands() {
    local repo="$1"
    local script_file="cleanup_commands_$(date +%Y%m%d_%H%M%S).sh"
    
    print_info "Generating cleanup commands script: $script_file"
    
    cat > "$script_file" << EOF
#!/usr/bin/env zsh
# Generated cleanup commands for GitHub test artifacts
# Repository: $repo
# Generated: $(date)

set -e

echo "🧹 Cleaning up test artifacts for $repo"
echo

# Close all test issues
echo "📋 Closing test issues..."
gh issue list --repo $repo --search '[TEST]' --state open --json number,title | \\
  jq -r '.[] | "gh issue close --repo $repo \\(.number) # \\(.title)"' | \\
  while read -r cmd; do
    echo "Running: \$cmd"
    eval "\$cmd"
  done

echo

# List milestones to review (manual deletion required)
echo "🎯 Test milestones to review:"
gh api "repos/$repo/milestones" | jq -r '.[] | select(.title | test("test|auto-test|complex-test")) | "Milestone: \\(.title) (\\(.open_issues) open issues)"'

echo
echo "⚠️  Please manually delete test milestones from the repository web interface"

echo

# List labels to review (manual deletion required)  
echo "🏷️  Test labels to review:"
gh api "repos/$repo/labels" | jq -r '.[] | select(.name | test("test|auto-test|comprehensive-test")) | "Label: \\(.name) (\\(.description // "no description"))"'

echo
echo "⚠️  Please manually delete test labels from the repository web interface"

echo
echo "✅ Test issue cleanup completed!"
echo "🔗 Repository: https://github.com/$repo"
EOF

    chmod +x "$script_file"
    print_success "Cleanup script generated: $script_file"
    print_info "Run this script to execute the cleanup commands"
}

main() {
    local cleanup_issues=true
    local cleanup_milestones=true
    local cleanup_labels=true
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --dry-run|-n)
                DRY_RUN=true
                shift
                ;;
            --non-interactive)
                INTERACTIVE=false
                shift
                ;;
            --issues-only)
                cleanup_milestones=false
                cleanup_labels=false
                shift
                ;;
            --milestones-only)
                cleanup_issues=false
                cleanup_labels=false
                shift
                ;;
            --labels-only)
                cleanup_issues=false
                cleanup_milestones=false
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$TEST_REPO" ]]; then
                    TEST_REPO="$1"
                else
                    print_error "Multiple repositories specified"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$TEST_REPO" ]]; then
        print_error "Repository not specified"
        show_help
        exit 1
    fi
    
    # Validate repository format
    if [[ ! "$TEST_REPO" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
        print_error "Invalid repository format. Use: user/repo or org/repo"
        exit 1
    fi
    
    print_header
    
    print_info "Repository: $TEST_REPO"
    print_info "Dry run: $DRY_RUN"
    print_info "Interactive: $INTERACTIVE"
    
    if [[ "$DRY_RUN" == "false" && "$INTERACTIVE" == "true" ]]; then
        echo
        echo -n "Proceed with cleanup? [y/N] "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    echo
    
    # Run cleanup operations
    if [[ "$cleanup_issues" == "true" ]]; then
        cleanup_issues "$TEST_REPO"
        echo
    fi
    
    if [[ "$cleanup_milestones" == "true" ]]; then
        cleanup_milestones "$TEST_REPO"
        echo
    fi
    
    if [[ "$cleanup_labels" == "true" ]]; then
        cleanup_labels "$TEST_REPO"
        echo
    fi
    
    # Generate cleanup script if not in dry-run mode
    if [[ "$DRY_RUN" == "false" ]]; then
        generate_cleanup_commands "$TEST_REPO"
    fi
    
    print_success "Cleanup process completed!"
}

main "$@"
