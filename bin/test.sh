#!/usr/bin/env bash
#
# Stripe Reachability Testing Script
# Tests connectivity to all Stripe domains and IP addresses
# Designed for maximum portability across Unix-like systems
#

set -eu

# Color output (with fallback for systems without tput)
if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
    RED=$(tput setaf 1 2>/dev/null || echo '')
    GREEN=$(tput setaf 2 2>/dev/null || echo '')
    YELLOW=$(tput setaf 3 2>/dev/null || echo '')
    BLUE=$(tput setaf 4 2>/dev/null || echo '')
    RESET=$(tput sgr0 2>/dev/null || echo '')
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    RESET=''
fi

# Configuration
TIMEOUT="${TIMEOUT:-5}"
VERBOSE="${VERBOSE:-0}"
TEST_DOMAINS="${TEST_DOMAINS:-1}"
TEST_IPS="${TEST_IPS:-1}"
TEST_WEBHOOKS="${TEST_WEBHOOKS:-1}"

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Stripe domains (core services)
STRIPE_DOMAINS=(
    "api.stripe.com"
    "files.stripe.com"
    "hooks.stripe.com"
    "js.stripe.com"
    "dashboard.stripe.com"
    "checkout.stripe.com"
    "connect.stripe.com"
    "payments.stripe.com"
    "manage.stripe.com"
    "atlas.stripe.com"
    "auth.stripe.com"
    "billing.stripe.com"
    "buy.stripe.com"
    "climate.stripe.com"
    "connect-js.stripe.com"
    "express.stripe.com"
    "invoice.stripe.com"
    "invoicedata.stripe.com"
    "m.stripe.com"
    "m.stripe.network"
    "merchant-ui-api.stripe.com"
    "pay.stripe.com"
    "q.stripe.com"
    "qr.stripe.com"
    "r.stripe.com"
    "stripe.com"
    "uploads.stripe.com"
    "verify.stripe.com"
    "hcaptcha.com"
)

# Stripe Terminal domains
STRIPE_TERMINAL_DOMAINS=(
    "api.emms.bbpos.com"
    "armada.stripe.com"
    "gator.stripe.com"
    "time.android.com"
    "time.cloudflare.com"
    "1.android.pool.ntp.org"
    "2.android.pool.ntp.org"
    "3.android.pool.ntp.org"
)

# Sample Stripe API IP addresses (subset for testing)
STRIPE_API_IPS=(
    "13.112.224.240"
    "13.115.13.148"
    "34.200.27.109"
    "34.237.201.68"
    "52.1.23.197"
)

# Stripe webhook IP addresses
STRIPE_WEBHOOK_IPS=(
    "3.18.12.63"
    "3.130.192.231"
    "13.235.14.237"
    "13.235.122.149"
    "18.211.135.69"
    "35.154.171.200"
    "52.15.183.38"
    "54.88.130.119"
    "54.88.130.237"
    "54.187.174.169"
    "54.187.205.235"
    "54.187.216.72"
)

# Logging functions
log_info() {
    echo "${BLUE}[INFO]${RESET} $*" >&2
}

log_success() {
    echo "${GREEN}[PASS]${RESET} $*" >&2
}

log_error() {
    echo "${RED}[FAIL]${RESET} $*" >&2
}

log_warn() {
    echo "${YELLOW}[WARN]${RESET} $*" >&2
}

log_debug() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo "${BLUE}[DEBUG]${RESET} $*" >&2
    fi
}

run_cmd() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo "${BLUE}+ $*${RESET}" >&2
    fi
    "$@"
}

# Increment test counters
record_test() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ "$1" -eq 0 ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Print section header
print_section() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
}

# Check if command exists (portable)
has_command() {
    command -v "$1" >/dev/null 2>&1
}

# Detect OS
check_os() {
    print_section "System Information"
    
    uname_s="$(uname -s 2>/dev/null || echo 'Unknown')"
    uname_m="$(uname -m 2>/dev/null || echo 'Unknown')"
    
    log_info "Operating System: $uname_s"
    log_info "Architecture: $uname_m"
    
    case "$uname_s" in
        Linux)
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                log_info "Distribution: $NAME ${VERSION:-}"
            fi
            ;;
        Darwin)
            version="$(sw_vers -productVersion 2>/dev/null || echo 'Unknown')"
            log_info "macOS Version: $version"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            log_info "Windows (Unix-like environment)"
            ;;
        *)
            log_warn "Untested operating system: $uname_s"
            ;;
    esac
    
    return 0
}

# Check available tools
check_tools() {
    print_section "Available Tools"
    
    local tools=("curl" "wget" "nc" "telnet" "ping" "dig" "nslookup" "host" "traceroute" "mtr")
    local found=0
    
    for tool in "${tools[@]}"; do
        if has_command "$tool"; then
            log_success "$tool: available"
            found=$((found + 1))
        else
            log_debug "$tool: not found"
        fi
    done
    
    if [ $found -eq 0 ]; then
        log_error "No network testing tools found!"
        return 1
    fi
    
    log_info "Found $found network tools"
    return 0
}

# Get current public IP
check_public_ip() {
    print_section "Public IP Address"
    
    local ip=""
    
    # Try multiple services for reliability
    if has_command curl; then
        ip=$(curl -4 -s --max-time "$TIMEOUT" https://api.ipify.org 2>/dev/null || echo "")
        if [ -n "$ip" ]; then
            log_success "Public IPv4: $ip"
            return 0
        fi
    fi
    
    if has_command wget; then
        ip=$(wget -4 -qO- --timeout="$TIMEOUT" https://api.ipify.org 2>/dev/null || echo "")
        if [ -n "$ip" ]; then
            log_success "Public IPv4: $ip"
            return 0
        fi
    fi
    
    log_warn "Could not determine public IP"
    return 1
}

# DNS resolution check
check_dns_resolution() {
    local domain="$1"
    local resolved=0
    
    # Try dig first (most reliable)
    if has_command dig; then
        if dig +short +time="$TIMEOUT" "$domain" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' >/dev/null; then
            resolved=1
        fi
    # Try nslookup
    elif has_command nslookup; then
        if nslookup -timeout="$TIMEOUT" "$domain" 2>/dev/null | grep -E '^Address: [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' >/dev/null; then
            resolved=1
        fi
    # Try host
    elif has_command host; then
        if host -W "$TIMEOUT" "$domain" 2>/dev/null | grep 'has address' >/dev/null; then
            resolved=1
        fi
    fi
    
    return $((resolved == 0))
}

# HTTP(S) connectivity check
check_http_connectivity() {
    local target="$1"
    local is_ip="${2:-0}"
    
    # Construct URL
    local url
    if [ "$is_ip" -eq 1 ]; then
        url="https://$target"
    else
        url="https://$target"
    fi
    
    # Try curl first with strict timeout
    if has_command curl; then
        if timeout "$TIMEOUT" curl -s -f -m "$TIMEOUT" --connect-timeout "$TIMEOUT" -o /dev/null "$url" 2>/dev/null; then
            return 0
        fi
        # Try with just HEAD request
        if timeout "$TIMEOUT" curl -s -I -m "$TIMEOUT" --connect-timeout "$TIMEOUT" -o /dev/null -w "%{http_code}" "$url" 2>/dev/null | grep -E '^(200|301|302|403)' >/dev/null; then
            return 0
        fi
    fi
    
    # Try wget with strict timeout
    if has_command wget; then
        if timeout "$TIMEOUT" wget --timeout="$TIMEOUT" --tries=1 -q --spider "$url" 2>/dev/null; then
            return 0
        fi
    fi
    
    return 1
}

# TCP connectivity check (fallback)
check_tcp_connectivity() {
    local host="$1"
    local port="${2:-443}"
    
    # Try nc (netcat) with timeout
    if has_command nc; then
        if timeout "$TIMEOUT" sh -c "echo '' | nc -w $TIMEOUT -z $host $port" 2>/dev/null; then
            return 0
        fi
    fi
    
    # Try telnet with timeout (less reliable)
    if has_command telnet; then
        if timeout "$TIMEOUT" sh -c "echo '' | telnet $host $port" 2>/dev/null | grep -i 'connected' >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    # Try bash TCP pseudo-device with timeout (if available)
    if timeout "$TIMEOUT" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Test domain connectivity
test_domain() {
    local domain="$1"
    local result=0
    
    log_debug "Testing domain: $domain"
    
    # DNS resolution
    if ! check_dns_resolution "$domain"; then
        log_error "DNS resolution failed: $domain"
        record_test 1
        return 1
    fi
    
    # Special handling for NTP time servers (use UDP port 123, not HTTPS)
    if echo "$domain" | grep -E '(time\.android\.com|time\.cloudflare\.com|\.ntp\.org)' >/dev/null; then
        # For time servers, DNS resolution is enough (they don't serve HTTPS)
        log_success "DNS resolved (NTP server): $domain"
        record_test 0
        return 0
    fi
    
    # HTTP(S) connectivity
    if ! check_http_connectivity "$domain" 0; then
        # Fallback to TCP check
        if ! check_tcp_connectivity "$domain" 443; then
            log_error "Connectivity failed: $domain"
            record_test 1
            return 1
        fi
    fi
    
    log_success "Reachable: $domain"
    record_test 0
    return 0
}

# Test IP connectivity
test_ip() {
    local ip="$1"
    
    log_debug "Testing IP: $ip"
    
    # Ping test (if available)
    if has_command ping; then
        # Portable ping command (works on Linux and macOS)
        if ping -c 1 -W "$TIMEOUT" "$ip" >/dev/null 2>&1; then
            log_success "Ping successful: $ip"
            record_test 0
            return 0
        fi
    fi
    
    # TCP connectivity test
    if check_tcp_connectivity "$ip" 443; then
        log_success "TCP reachable: $ip"
        record_test 0
        return 0
    fi
    
    log_error "Unreachable: $ip"
    record_test 1
    return 1
}

# Test all Stripe domains
test_all_domains() {
    print_section "Testing Stripe Core Domains"
    
    local failed=0
    for domain in "${STRIPE_DOMAINS[@]}"; do
        test_domain "$domain" || failed=$((failed + 1))
    done
    
    if [ "${#STRIPE_TERMINAL_DOMAINS[@]}" -gt 0 ]; then
        print_section "Testing Stripe Terminal Domains"
        for domain in "${STRIPE_TERMINAL_DOMAINS[@]}"; do
            test_domain "$domain" || failed=$((failed + 1))
        done
    fi
    
    return 0
}

# Test sample IPs
test_sample_ips() {
    print_section "Testing Sample Stripe API IPs"
    
    log_info "Testing subset of ${#STRIPE_API_IPS[@]} API IPs"
    
    for ip in "${STRIPE_API_IPS[@]}"; do
        test_ip "$ip"
    done
    
    return 0
}

# Test webhook IPs
test_webhook_ips() {
    print_section "Testing Stripe Webhook IPs"
    
    log_info "Testing all ${#STRIPE_WEBHOOK_IPS[@]} webhook IPs"
    
    for ip in "${STRIPE_WEBHOOK_IPS[@]}"; do
        test_ip "$ip"
    done
    
    return 0
}

# Test Stripe API health endpoint
test_api_health() {
    print_section "Testing Stripe API Health"
    
    if has_command curl; then
        log_info "Checking api.stripe.com/healthcheck"
        if curl -v -m "$TIMEOUT" https://api.stripe.com/healthcheck 2>&1 | tee /tmp/stripe_health.log | grep -i '200 OK' >/dev/null; then
            log_success "API health check passed"
            record_test 0
            return 0
        else
            log_error "API health check failed"
            record_test 1
            return 1
        fi
    else
        log_warn "curl not available, skipping API health check"
        return 0
    fi
}

# Trace route to Stripe
check_route() {
    print_section "Network Route to Stripe API"
    
    local target="api.stripe.com"
    
    if has_command mtr; then
        log_info "Using mtr for route analysis"
        run_cmd mtr -n -c 3 --report "$target"
    elif has_command traceroute; then
        log_info "Using traceroute for route analysis"
        run_cmd traceroute -n -m 20 -w "$TIMEOUT" "$target"
    else
        log_warn "No route tracing tools available (mtr, traceroute)"
    fi
    
    return 0
}

# Print summary
print_summary() {
    print_section "Test Summary"
    
    echo "Total Tests:  $TOTAL_TESTS"
    echo "${GREEN}Passed:       $PASSED_TESTS${RESET}"
    if [ $FAILED_TESTS -gt 0 ]; then
        echo "${RED}Failed:       $FAILED_TESTS${RESET}"
    else
        echo "Failed:       $FAILED_TESTS"
    fi
    
    if [ $TOTAL_TESTS -gt 0 ]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
        echo "Success Rate: ${success_rate}%"
    fi
    
    echo ""
    if [ $FAILED_TESTS -eq 0 ]; then
        log_success "All tests passed!"
        return 0
    else
        log_error "Some tests failed. Check your network configuration."
        return 1
    fi
}

# Main test suite
run_all_tests() {
    log_info "Starting Stripe Reachability Tests"
    log_info "Timeout: ${TIMEOUT}s"
    echo ""
    
    check_os
    check_tools
    check_public_ip
    
    if [ "$TEST_DOMAINS" -eq 1 ]; then
        test_all_domains
    fi
    
    if [ "$TEST_IPS" -eq 1 ]; then
        test_sample_ips
    fi
    
    if [ "$TEST_WEBHOOKS" -eq 1 ]; then
        test_webhook_ips
    fi
    
    test_api_health
    check_route
    
    print_summary
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Test connectivity to Stripe domains and IP addresses.

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -t, --timeout SEC   Set timeout in seconds (default: 5)
    --no-domains        Skip domain tests
    --no-ips            Skip IP tests
    --no-webhooks       Skip webhook IP tests
    --domains-only      Test only domains
    --ips-only          Test only IPs

ENVIRONMENT VARIABLES:
    TIMEOUT             Timeout in seconds (default: 5)
    VERBOSE             Enable verbose mode (0 or 1)
    TEST_DOMAINS        Test domains (0 or 1, default: 1)
    TEST_IPS            Test IPs (0 or 1, default: 1)
    TEST_WEBHOOKS       Test webhook IPs (0 or 1, default: 1)

EXAMPLES:
    $0                          # Run all tests
    $0 --verbose                # Run with verbose output
    $0 --domains-only           # Test only domains
    $0 --timeout 10             # Use 10 second timeout
    TIMEOUT=10 VERBOSE=1 $0     # Use environment variables

EOF
}

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --no-domains)
            TEST_DOMAINS=0
            shift
            ;;
        --no-ips)
            TEST_IPS=0
            shift
            ;;
        --no-webhooks)
            TEST_WEBHOOKS=0
            shift
            ;;
        --domains-only)
            TEST_DOMAINS=1
            TEST_IPS=0
            TEST_WEBHOOKS=0
            shift
            ;;
        --ips-only)
            TEST_DOMAINS=0
            TEST_IPS=1
            TEST_WEBHOOKS=1
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run the test suite
run_all_tests
exit $?
