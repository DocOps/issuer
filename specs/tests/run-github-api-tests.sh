#!/usr/bin/env zsh
# GitHub API Integration Test Runner
# Comprehensive testing suite for issuer CLI GitHub integration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
TEST_DIR="$(dirname "$0")"
TESTS_DIR="${TEST_DIR}/github-api"
CONFIG_FILE="${TESTS_DIR}/config.yml"
RESULTS_DIR="${TEST_DIR}/results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULTS_FILE="${RESULTS_DIR}/test_results_${TIMESTAMP}.log"

# Default configuration (override with config.yml)
TEST_REPO=""
TEST_USERNAME=""
DRY_RUN_FIRST=true
CLEANUP_AFTER_TESTS=false
VERBOSE=false
INTERACTIVE=true

# Test tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Functions
print_header() {
    echo
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}  🧪 GitHub API Integration Test Suite  ${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo
}

print_section() {
    echo
    echo -e "${PURPLE}📋 $1${NC}"
    echo -e "${PURPLE}$(printf '=%.0s' {1..50})${NC}"
}

print_test() {
    echo -e "${CYAN}🔍 Test: $1${NC}"
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

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        print_info "Loading configuration from $CONFIG_FILE"
        # Parse YAML config (simple parsing for our needs)
        while IFS=': ' read -r key value; do
            case "$key" in
                "test_repo")
                    TEST_REPO=$(echo "$value" | tr -d '"' | tr -d "'")
                    ;;
                "test_username")
                    TEST_USERNAME=$(echo "$value" | tr -d '"' | tr -d "'")
                    ;;
                "dry_run_first")
                    DRY_RUN_FIRST=$(echo "$value" | tr -d '"' | tr -d "'")
                    ;;
                "cleanup_after_tests")
                    CLEANUP_AFTER_TESTS=$(echo "$value" | tr -d '"' | tr -d "'")
                    ;;
                "verbose_output")
                    VERBOSE=$(echo "$value" | tr -d '"' | tr -d "'")
                    ;;
            esac
        done < "$CONFIG_FILE"
    else
        print_warning "No config file found at $CONFIG_FILE"
        print_info "Run: cp ${TESTS_DIR}/config.yml.example ${CONFIG_FILE}"
        print_info "Then edit the config file with your test repository details"
    fi
}

validate_config() {
    local errors=0
    
    if [[ -z "$TEST_REPO" ]]; then
        print_error "TEST_REPO not configured"
        errors=$((errors + 1))
    fi
    
    if [[ -z "$TEST_USERNAME" ]]; then
        print_error "TEST_USERNAME not configured"
        errors=$((errors + 1))
    fi
    
    # Check for GitHub token
    if [[ -z "$GITHUB_TOKEN" && -z "$GITHUB_ACCESS_TOKEN" && -z "$ISSUER_API_TOKEN" && -z "$ISSUER_GITHUB_TOKEN" ]]; then
        print_error "No GitHub token found in environment variables"
        print_info "Set one of: GITHUB_TOKEN, GITHUB_ACCESS_TOKEN, ISSUER_API_TOKEN, ISSUER_GITHUB_TOKEN"
        errors=$((errors + 1))
    fi
    
    return $errors
}

update_test_files() {
    print_section "Updating test files with configuration"
    
    # Update all test files with the correct repository and username
    for test_file in "${TESTS_DIR}"/*.yml; do
        if [[ -f "$test_file" ]]; then
            # Create a backup
            cp "$test_file" "${test_file}.bak"
            
            # Update repository
            sed -i "s|your-username/issuer-test-repo|${TEST_REPO}|g" "$test_file"
            
            # Update username
            sed -i "s|your-username|${TEST_USERNAME}|g" "$test_file"
            
            print_info "Updated $(basename "$test_file")"
        fi
    done
}

restore_test_files() {
    print_info "Restoring original test files"
    for backup_file in "${TESTS_DIR}"/*.yml.bak; do
        if [[ -f "$backup_file" ]]; then
            original_file="${backup_file%.bak}"
            mv "$backup_file" "$original_file"
        fi
    done
}

run_single_test() {
    local test_file="$1"
    local test_name="$2"
    local flags="$3"
    local should_succeed="$4"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    print_test "Running $test_name"
    
    # Create results directory if it doesn't exist
    mkdir -p "$RESULTS_DIR"
    
    # Run the test
    local output_file="${RESULTS_DIR}/$(basename "$test_file" .yml)_${TIMESTAMP}.log"
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo "Command: bundle exec ruby -I lib exe/issuer \"$test_file\" $flags"
    fi
    
    # Execute the command and capture output with timeout
    if timeout 120 bundle exec ruby -I lib exe/issuer "$test_file" $flags > "$output_file" 2>&1; then
        local exit_code=0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            echo "Test timed out after 120 seconds" >> "$output_file"
            print_error "$test_name timed out (120s timeout)"
        fi
    fi
    
    # Check results
    if [[ "$should_succeed" == "true" ]]; then
        if [[ $exit_code -eq 0 ]]; then
            print_success "$test_name passed"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            echo "✅ PASS: $test_name" >> "$RESULTS_FILE"
        else
            print_error "$test_name failed (exit code: $exit_code)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            echo "❌ FAIL: $test_name (exit code: $exit_code)" >> "$RESULTS_FILE"
            if [[ "$VERBOSE" == "true" ]]; then
                echo "Output:"
                cat "$output_file"
            fi
        fi
    else
        # Test should fail (e.g., error tests)
        if [[ $exit_code -ne 0 ]]; then
            print_success "$test_name failed as expected"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            echo "✅ PASS: $test_name (failed as expected)" >> "$RESULTS_FILE"
        else
            print_error "$test_name should have failed but succeeded"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            echo "❌ FAIL: $test_name (should have failed)" >> "$RESULTS_FILE"
        fi
    fi
    
    # Save detailed output
    echo "=== $test_name ===" >> "$RESULTS_FILE"
    cat "$output_file" >> "$RESULTS_FILE"
    echo >> "$RESULTS_FILE"
}

run_test_suite() {
    print_section "Running Test Suite"
    
    # Initialize results file
    mkdir -p "$RESULTS_DIR"
    echo "GitHub API Integration Test Results" > "$RESULTS_FILE"
    echo "Timestamp: $(date)" >> "$RESULTS_FILE"
    echo "Test Repository: $TEST_REPO" >> "$RESULTS_FILE"
    echo "Test Username: $TEST_USERNAME" >> "$RESULTS_FILE"
    echo "======================================" >> "$RESULTS_FILE"
    echo >> "$RESULTS_FILE"
    
    # Test 1: Authentication and Connection (dry-run first)
    if [[ "$DRY_RUN_FIRST" == "true" ]]; then
        run_single_test "${TESTS_DIR}/01-auth-connection.yml" "01-auth-connection (dry-run)" "--dry" true
    fi
    run_single_test "${TESTS_DIR}/01-auth-connection.yml" "01-auth-connection" "" true
    
    # Test 2: Basic Issues (dry-run first)
    if [[ "$DRY_RUN_FIRST" == "true" ]]; then
        run_single_test "${TESTS_DIR}/02-basic-issues.yml" "02-basic-issues (dry-run)" "--dry" true
    fi
    run_single_test "${TESTS_DIR}/02-basic-issues.yml" "02-basic-issues" "" true
    
    # Test 3: Milestone Tests
    if [[ "$DRY_RUN_FIRST" == "true" ]]; then
        run_single_test "${TESTS_DIR}/03-milestone-tests.yml" "03-milestone-tests (dry-run)" "--dry" true
    fi
    run_single_test "${TESTS_DIR}/03-milestone-tests.yml" "03-milestone-tests (manual)" "" true
    run_single_test "${TESTS_DIR}/03-milestone-tests.yml" "03-milestone-tests (auto)" "--auto-metadata" true
    
    # Test 4: Label Tests
    if [[ "$DRY_RUN_FIRST" == "true" ]]; then
        run_single_test "${TESTS_DIR}/04-label-tests.yml" "04-label-tests (dry-run)" "--dry" true
    fi
    run_single_test "${TESTS_DIR}/04-label-tests.yml" "04-label-tests (manual)" "" true
    run_single_test "${TESTS_DIR}/04-label-tests.yml" "04-label-tests (auto)" "--auto-metadata" true
    
    # Test 5: Assignment Tests
    if [[ "$DRY_RUN_FIRST" == "true" ]]; then
        run_single_test "${TESTS_DIR}/05-assignment-tests.yml" "05-assignment-tests (dry-run)" "--dry" true
    fi
    run_single_test "${TESTS_DIR}/05-assignment-tests.yml" "05-assignment-tests" "" true
    
    # Test 6: Automation Tests
    if [[ "$DRY_RUN_FIRST" == "true" ]]; then
        run_single_test "${TESTS_DIR}/06-automation-tests.yml" "06-automation-tests (dry-run)" "--dry" true
    fi
    run_single_test "${TESTS_DIR}/06-automation-tests.yml" "06-automation-tests (--auto-metadata)" "--auto-metadata" true
    run_single_test "${TESTS_DIR}/06-automation-tests.yml" "06-automation-tests (--auto-versions --auto-tags)" "--auto-versions --auto-tags" true
    run_single_test "${TESTS_DIR}/06-automation-tests.yml" "06-automation-tests (--auto-milestones --auto-labels)" "--auto-milestones --auto-labels" true
    
    # Test 7: Error Tests (should fail)
    run_single_test "${TESTS_DIR}/07-error-tests.yml" "07-error-tests (should fail)" "" false
    run_single_test "${TESTS_DIR}/07-error-tests.yml" "07-error-tests (dry-run should fail)" "--dry" false
    
    # Test 8: Complex Tests
    if [[ "$DRY_RUN_FIRST" == "true" ]]; then
        run_single_test "${TESTS_DIR}/08-complex-tests.yml" "08-complex-tests (dry-run)" "--dry" true
    fi
    run_single_test "${TESTS_DIR}/08-complex-tests.yml" "08-complex-tests (auto)" "--auto-metadata" true
}

print_summary() {
    print_section "Test Results Summary"
    
    echo -e "${BLUE}Total Tests:  ${TOTAL_TESTS}${NC}"
    echo -e "${GREEN}Passed:       ${PASSED_TESTS}${NC}"
    echo -e "${RED}Failed:       ${FAILED_TESTS}${NC}"
    echo -e "${YELLOW}Skipped:      ${SKIPPED_TESTS}${NC}"
    echo
    
    local success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    echo -e "${BLUE}Success Rate: ${success_rate}%${NC}"
    echo
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        print_success "All tests passed! 🎉"
    else
        print_error "Some tests failed. Check the results file: $RESULTS_FILE"
    fi
    
    echo
    print_info "Detailed results saved to: $RESULTS_FILE"
    
    # Add summary to results file
    echo >> "$RESULTS_FILE"
    echo "=== SUMMARY ===" >> "$RESULTS_FILE"
    echo "Total Tests: $TOTAL_TESTS" >> "$RESULTS_FILE"
    echo "Passed: $PASSED_TESTS" >> "$RESULTS_FILE"
    echo "Failed: $FAILED_TESTS" >> "$RESULTS_FILE"
    echo "Success Rate: ${success_rate}%" >> "$RESULTS_FILE"
}

cleanup_tests() {
    if [[ "$CLEANUP_AFTER_TESTS" == "true" ]]; then
        print_section "Cleaning up test artifacts"
        print_warning "Cleanup functionality not yet implemented"
        print_info "You may want to manually close/delete test issues in the repository"
    fi
}

main() {
    # Handle command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                echo "GitHub API Integration Test Runner"
                echo
                echo "Usage: $0 [options]"
                echo
                echo "Options:"
                echo "  --help, -h          Show this help message"
                echo "  --config FILE       Use specific config file"
                echo "  --verbose, -v       Verbose output"
                echo "  --no-dry-run        Skip dry-run tests"
                echo "  --cleanup           Clean up after tests"
                echo "  --non-interactive   Run without prompts"
                echo
                echo "Environment Variables:"
                echo "  GITHUB_TOKEN        GitHub personal access token"
                echo "  GITHUB_ACCESS_TOKEN Alternative token variable"
                echo "  ISSUER_API_TOKEN    Issuer-specific token variable"
                echo
                exit 0
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --no-dry-run)
                DRY_RUN_FIRST=false
                shift
                ;;
            --cleanup)
                CLEANUP_AFTER_TESTS=true
                shift
                ;;
            --non-interactive)
                INTERACTIVE=false
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    print_header
    
    # Load and validate configuration
    load_config
    
    if ! validate_config; then
        print_error "Configuration validation failed"
        print_info "Please check your configuration and try again"
        exit 1
    fi
    
    print_info "Test Repository: $TEST_REPO"
    print_info "Test Username: $TEST_USERNAME"
    print_info "Dry-run first: $DRY_RUN_FIRST"
    print_info "Cleanup after: $CLEANUP_AFTER_TESTS"
    
    # Interactive confirmation
    if [[ "$INTERACTIVE" == "true" ]]; then
        echo
        echo -n "Proceed with running tests? [y/N] "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Tests cancelled by user"
            exit 0
        fi
    fi
    
    # Update test files with configuration
    update_test_files
    
    # Trap to restore files on exit
    trap restore_test_files EXIT
    
    # Run the test suite
    run_test_suite
    
    # Print summary
    print_summary
    
    # Cleanup if requested
    cleanup_tests
    
    # Exit with appropriate code
    if [[ $FAILED_TESTS -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
