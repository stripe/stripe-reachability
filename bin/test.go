package main

import (
	"context"
	"crypto/tls"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"runtime"
	"strings"
	"sync"
	"time"
)

// Configuration
type Config struct {
	Timeout      time.Duration
	Verbose      bool
	TestDomains  bool
	TestIPs      bool
	TestWebhooks bool
	Parallel     int
}

// Test results
type TestResults struct {
	sync.Mutex
	Total  int
	Passed int
	Failed int
}

// ANSI color codes
const (
	ColorReset  = "\033[0m"
	ColorRed    = "\033[31m"
	ColorGreen  = "\033[32m"
	ColorYellow = "\033[33m"
	ColorBlue   = "\033[34m"
)

// Stripe domains
var stripeDomains = []string{
	"api.stripe.com",
	"files.stripe.com",
	"hooks.stripe.com",
	"js.stripe.com",
	"dashboard.stripe.com",
	"checkout.stripe.com",
	"connect.stripe.com",
	"payments.stripe.com",
	"manage.stripe.com",
	"atlas.stripe.com",
	"auth.stripe.com",
	"billing.stripe.com",
	"buy.stripe.com",
	"climate.stripe.com",
	"connect-js.stripe.com",
	"express.stripe.com",
	"invoice.stripe.com",
	"invoicedata.stripe.com",
	"m.stripe.com",
	"m.stripe.network",
	"merchant-ui-api.stripe.com",
	"pay.stripe.com",
	"q.stripe.com",
	"qr.stripe.com",
	"r.stripe.com",
	"stripe.com",
	"terminal.stripe.com",
	"uploads.stripe.com",
	"verify.stripe.com",
	"a.stripecdn.com",
	"b.stripecdn.com",
	"c.stripecdn.com",
	"f.stripecdn.com",
	"hcaptcha.com",
}

var stripeTerminalDomains = []string{
	"api.emms.bbpos.com",
	"armada.stripe.com",
	"gator.stripe.com",
	"time.android.com",
	"time.cloudflare.com",
	"2.android.pool.ntp.org",
}

var stripeAPIIPs = []string{
	"13.112.224.240",
	"13.115.13.148",
	"34.200.27.109",
	"34.237.201.68",
	"52.1.23.197",
}

var stripeWebhookIPs = []string{
	"3.18.12.63",
	"3.130.192.231",
	"13.235.14.237",
	"13.235.122.149",
	"18.211.135.69",
	"35.154.171.200",
	"52.15.183.38",
	"54.88.130.119",
	"54.88.130.237",
	"54.187.174.169",
	"54.187.205.235",
	"54.187.216.72",
}

var (
	config  Config
	results TestResults
)

// Logging functions
func logInfo(msg string) {
	fmt.Fprintf(os.Stderr, "%s[INFO]%s %s\n", ColorBlue, ColorReset, msg)
}

func logSuccess(msg string) {
	fmt.Fprintf(os.Stderr, "%s[PASS]%s %s\n", ColorGreen, ColorReset, msg)
}

func logError(msg string) {
	fmt.Fprintf(os.Stderr, "%s[FAIL]%s %s\n", ColorRed, ColorReset, msg)
}

func logWarn(msg string) {
	fmt.Fprintf(os.Stderr, "%s[WARN]%s %s\n", ColorYellow, ColorReset, msg)
}

func logDebug(msg string) {
	if config.Verbose {
		fmt.Fprintf(os.Stderr, "%s[DEBUG]%s %s\n", ColorBlue, ColorReset, msg)
	}
}

func printSection(title string) {
	fmt.Println()
	fmt.Println("========================================")
	fmt.Println(title)
	fmt.Println("========================================")
}

func recordTest(passed bool) {
	results.Lock()
	defer results.Unlock()
	results.Total++
	if passed {
		results.Passed++
	} else {
		results.Failed++
	}
}

// System information
func checkSystem() {
	printSection("System Information")
	logInfo(fmt.Sprintf("OS: %s", runtime.GOOS))
	logInfo(fmt.Sprintf("Architecture: %s", runtime.GOARCH))
	logInfo(fmt.Sprintf("Go Version: %s", runtime.Version()))
	logInfo(fmt.Sprintf("CPUs: %d", runtime.NumCPU()))
}

// Get public IP
func getPublicIP() {
	printSection("Public IP Address")

	ctx, cancel := context.WithTimeout(context.Background(), config.Timeout)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, "GET", "https://api.ipify.org?format=text", nil)
	if err != nil {
		logWarn("Could not create request for public IP")
		return
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		logWarn("Could not determine public IP")
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		logWarn("Could not read public IP response")
		return
	}

	logSuccess(fmt.Sprintf("Public IPv4: %s", strings.TrimSpace(string(body))))
}

// DNS resolution check
func checkDNS(domain string) bool {
	ctx, cancel := context.WithTimeout(context.Background(), config.Timeout)
	defer cancel()

	resolver := &net.Resolver{}
	addrs, err := resolver.LookupHost(ctx, domain)
	if err != nil {
		logDebug(fmt.Sprintf("DNS resolution failed for %s: %v", domain, err))
		return false
	}

	logDebug(fmt.Sprintf("DNS resolved %s to %v", domain, addrs))
	return len(addrs) > 0
}

// TCP connectivity check
func checkTCP(host string, port string) bool {
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, port), config.Timeout)
	if err != nil {
		logDebug(fmt.Sprintf("TCP connection failed to %s:%s: %v", host, port, err))
		return false
	}
	conn.Close()
	return true
}

// HTTP(S) connectivity check
func checkHTTP(url string) bool {
	ctx, cancel := context.WithTimeout(context.Background(), config.Timeout)
	defer cancel()

	client := &http.Client{
		Timeout: config.Timeout,
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: false,
			},
			DisableKeepAlives: true,
		},
	}

	req, err := http.NewRequestWithContext(ctx, "HEAD", url, nil)
	if err != nil {
		logDebug(fmt.Sprintf("Failed to create request for %s: %v", url, err))
		return false
	}

	resp, err := client.Do(req)
	if err != nil {
		logDebug(fmt.Sprintf("HTTP check failed for %s: %v", url, err))
		return false
	}
	defer resp.Body.Close()

	// Accept various success codes
	validCodes := map[int]bool{
		200: true, 301: true, 302: true, 403: true,
	}
	return validCodes[resp.StatusCode]
}

// Test domain
func testDomain(domain string, wg *sync.WaitGroup) {
	if wg != nil {
		defer wg.Done()
	}

	logDebug(fmt.Sprintf("Testing domain: %s", domain))

	// DNS resolution
	if !checkDNS(domain) {
		logError(fmt.Sprintf("DNS resolution failed: %s", domain))
		recordTest(false)
		return
	}

	// Special handling for NTP time servers (they don't serve HTTPS)
	if strings.Contains(domain, "time.android.com") ||
		strings.Contains(domain, "time.cloudflare.com") ||
		strings.Contains(domain, ".ntp.org") {
		logSuccess(fmt.Sprintf("DNS resolved (NTP server): %s", domain))
		recordTest(true)
		return
	}

	// HTTP(S) check
	if checkHTTP("https://" + domain) {
		logSuccess(fmt.Sprintf("Reachable: %s", domain))
		recordTest(true)
		return
	}

	// Fallback to TCP
	if checkTCP(domain, "443") {
		logSuccess(fmt.Sprintf("TCP reachable: %s", domain))
		recordTest(true)
		return
	}

	logError(fmt.Sprintf("Connectivity failed: %s", domain))
	recordTest(false)
}

// Test IP
func testIP(ip string, wg *sync.WaitGroup) {
	if wg != nil {
		defer wg.Done()
	}

	logDebug(fmt.Sprintf("Testing IP: %s", ip))

	// TCP connectivity test
	if checkTCP(ip, "443") {
		logSuccess(fmt.Sprintf("TCP reachable: %s", ip))
		recordTest(true)
		return
	}

	logError(fmt.Sprintf("Unreachable: %s", ip))
	recordTest(false)
}

// Test all domains
func testAllDomains() {
	printSection("Testing Stripe Core Domains")

	var wg sync.WaitGroup
	semaphore := make(chan struct{}, config.Parallel)

	for _, domain := range stripeDomains {
		wg.Add(1)
		semaphore <- struct{}{}
		go func(d string) {
			defer func() { <-semaphore }()
			testDomain(d, &wg)
		}(domain)
	}
	wg.Wait()

	printSection("Testing Stripe Terminal Domains")
	for _, domain := range stripeTerminalDomains {
		wg.Add(1)
		semaphore <- struct{}{}
		go func(d string) {
			defer func() { <-semaphore }()
			testDomain(d, &wg)
		}(domain)
	}
	wg.Wait()
}

// Test sample IPs
func testSampleIPs() {
	printSection("Testing Sample Stripe API IPs")
	logInfo(fmt.Sprintf("Testing subset of %d API IPs", len(stripeAPIIPs)))

	var wg sync.WaitGroup
	semaphore := make(chan struct{}, config.Parallel)

	for _, ip := range stripeAPIIPs {
		wg.Add(1)
		semaphore <- struct{}{}
		go func(i string) {
			defer func() { <-semaphore }()
			testIP(i, &wg)
		}(ip)
	}
	wg.Wait()
}

// Test webhook IPs
func testWebhookIPs() {
	printSection("Testing Stripe Webhook IPs")
	logInfo(fmt.Sprintf("Testing all %d webhook IPs", len(stripeWebhookIPs)))

	var wg sync.WaitGroup
	semaphore := make(chan struct{}, config.Parallel)

	for _, ip := range stripeWebhookIPs {
		wg.Add(1)
		semaphore <- struct{}{}
		go func(i string) {
			defer func() { <-semaphore }()
			testIP(i, &wg)
		}(ip)
	}
	wg.Wait()
}

// Test API health
func testAPIHealth() {
	printSection("Testing Stripe API Health")

	logInfo("Checking api.stripe.com/healthcheck")

	ctx, cancel := context.WithTimeout(context.Background(), config.Timeout)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, "GET", "https://api.stripe.com/healthcheck", nil)
	if err != nil {
		logError(fmt.Sprintf("API health check failed: %v", err))
		recordTest(false)
		return
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		logError(fmt.Sprintf("API health check failed: %v", err))
		recordTest(false)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode == 200 {
		logSuccess("API health check passed")
		recordTest(true)
	} else {
		logError(fmt.Sprintf("API health check failed: %d", resp.StatusCode))
		recordTest(false)
	}
}

// Print summary
func printSummary() bool {
	printSection("Test Summary")

	fmt.Printf("Total Tests:  %d\n", results.Total)
	fmt.Printf("%sPassed:       %d%s\n", ColorGreen, results.Passed, ColorReset)
	if results.Failed > 0 {
		fmt.Printf("%sFailed:       %d%s\n", ColorRed, results.Failed, ColorReset)
	} else {
		fmt.Printf("Failed:       %d\n", results.Failed)
	}

	if results.Total > 0 {
		successRate := (results.Passed * 100) / results.Total
		fmt.Printf("Success Rate: %d%%\n", successRate)
	}

	fmt.Println()
	if results.Failed == 0 {
		logSuccess("All tests passed!")
		return true
	} else {
		logError("Some tests failed. Check your network configuration.")
		return false
	}
}

// Main function
func main() {
	// Parse flags
	var (
		timeout      int
		verbose      bool
		noDomains    bool
		noIPs        bool
		noWebhooks   bool
		domainsOnly  bool
		ipsOnly      bool
		parallel     int
		help         bool
	)

	flag.IntVar(&timeout, "timeout", 5, "Timeout in seconds")
	flag.IntVar(&timeout, "t", 5, "Timeout in seconds (shorthand)")
	flag.BoolVar(&verbose, "verbose", false, "Enable verbose output")
	flag.BoolVar(&verbose, "v", false, "Enable verbose output (shorthand)")
	flag.BoolVar(&noDomains, "no-domains", false, "Skip domain tests")
	flag.BoolVar(&noIPs, "no-ips", false, "Skip IP tests")
	flag.BoolVar(&noWebhooks, "no-webhooks", false, "Skip webhook IP tests")
	flag.BoolVar(&domainsOnly, "domains-only", false, "Test only domains")
	flag.BoolVar(&ipsOnly, "ips-only", false, "Test only IPs")
	flag.IntVar(&parallel, "parallel", 10, "Number of parallel tests")
	flag.BoolVar(&help, "help", false, "Show help message")
	flag.BoolVar(&help, "h", false, "Show help message (shorthand)")

	flag.Parse()

	if help {
		fmt.Println(`
Usage: stripe-reachability [OPTIONS]

Test connectivity to Stripe domains and IP addresses.

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -t, --timeout SEC   Set timeout in seconds (default: 5)
    --parallel NUM      Number of parallel tests (default: 10)
    --no-domains        Skip domain tests
    --no-ips            Skip IP tests
    --no-webhooks       Skip webhook IP tests
    --domains-only      Test only domains
    --ips-only          Test only IPs

EXAMPLES:
    stripe-reachability                     # Run all tests
    stripe-reachability --verbose           # Run with verbose output
    stripe-reachability --domains-only      # Test only domains
    stripe-reachability --timeout 10        # Use 10 second timeout
    stripe-reachability --parallel 20       # Use 20 parallel workers
`)
		os.Exit(0)
	}

	// Configure
	config = Config{
		Timeout:      time.Duration(timeout) * time.Second,
		Verbose:      verbose,
		TestDomains:  !noDomains && !ipsOnly,
		TestIPs:      !noIPs && !domainsOnly,
		TestWebhooks: !noWebhooks && !domainsOnly,
		Parallel:     parallel,
	}

	if domainsOnly {
		config.TestDomains = true
		config.TestIPs = false
		config.TestWebhooks = false
	}

	if ipsOnly {
		config.TestDomains = false
		config.TestIPs = true
		config.TestWebhooks = true
	}

	// Run tests
	logInfo("Starting Stripe Reachability Tests")
	logInfo(fmt.Sprintf("Timeout: %v", config.Timeout))
	logInfo(fmt.Sprintf("Parallel workers: %d", config.Parallel))
	fmt.Println()

	checkSystem()
	getPublicIP()

	if config.TestDomains {
		testAllDomains()
	}

	if config.TestIPs {
		testSampleIPs()
	}

	if config.TestWebhooks {
		testWebhookIPs()
	}

	testAPIHealth()

	success := printSummary()
	if !success {
		os.Exit(1)
	}
}
