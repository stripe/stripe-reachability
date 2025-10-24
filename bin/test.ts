#!/usr/bin/env bun
/**
 * Stripe Reachability Testing Tool (Bun/TypeScript)
 * 
 * Cross-platform connectivity testing for Stripe domains and IPs
 * Requires Bun runtime: https://bun.sh
 */

import { $ } from "bun";
import dns from "dns/promises";
import { connect } from "net";

// Configuration
interface Config {
  timeout: number;
  verbose: boolean;
  testDomains: boolean;
  testIPs: boolean;
  testWebhooks: boolean;
}

const config: Config = {
  timeout: parseInt(process.env.TIMEOUT || "5000"),
  verbose: process.env.VERBOSE === "1",
  testDomains: process.env.TEST_DOMAINS !== "0",
  testIPs: process.env.TEST_IPS !== "0",
  testWebhooks: process.env.TEST_WEBHOOKS !== "0",
};

// Colors for output
const colors = {
  reset: "\x1b[0m",
  red: "\x1b[31m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
};

// Test counters
let totalTests = 0;
let passedTests = 0;
let failedTests = 0;

// Stripe domains
const STRIPE_DOMAINS = [
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
];

const STRIPE_TERMINAL_DOMAINS = [
  "api.emms.bbpos.com",
  "armada.stripe.com",
  "gator.stripe.com",
  "time.android.com",
  "time.cloudflare.com",
  "2.android.pool.ntp.org",
];

const STRIPE_API_IPS = [
  "13.112.224.240",
  "13.115.13.148",
  "34.200.27.109",
  "34.237.201.68",
  "52.1.23.197",
];

const STRIPE_WEBHOOK_IPS = [
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
];

// Logging functions
function logInfo(msg: string) {
  console.error(`${colors.blue}[INFO]${colors.reset} ${msg}`);
}

function logSuccess(msg: string) {
  console.error(`${colors.green}[PASS]${colors.reset} ${msg}`);
}

function logError(msg: string) {
  console.error(`${colors.red}[FAIL]${colors.reset} ${msg}`);
}

function logWarn(msg: string) {
  console.error(`${colors.yellow}[WARN]${colors.reset} ${msg}`);
}

function logDebug(msg: string) {
  if (config.verbose) {
    console.error(`${colors.blue}[DEBUG]${colors.reset} ${msg}`);
  }
}

function printSection(title: string) {
  console.log("\n========================================");
  console.log(title);
  console.log("========================================");
}

function recordTest(passed: boolean) {
  totalTests++;
  if (passed) {
    passedTests++;
  } else {
    failedTests++;
  }
}

// System information
async function checkSystem() {
  printSection("System Information");
  
  logInfo(`Platform: ${process.platform}`);
  logInfo(`Architecture: ${process.arch}`);
  logInfo(`Node Version: ${process.version}`);
  logInfo(`Bun Version: ${Bun.version}`);
  
  return true;
}

// DNS resolution
async function checkDNS(domain: string): Promise<boolean> {
  try {
    const addresses = await dns.resolve4(domain);
    logDebug(`DNS resolved ${domain} to ${addresses.join(", ")}`);
    return addresses.length > 0;
  } catch (error) {
    logDebug(`DNS resolution failed for ${domain}: ${error}`);
    return false;
  }
}

// TCP connectivity check
function checkTCP(host: string, port: number = 443): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = connect({ host, port, timeout: config.timeout }, () => {
      socket.end();
      resolve(true);
    });
    
    socket.on("error", () => {
      resolve(false);
    });
    
    socket.on("timeout", () => {
      socket.destroy();
      resolve(false);
    });
  });
}

// HTTP(S) connectivity check
async function checkHTTP(url: string): Promise<boolean> {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), config.timeout);
    
    const response = await fetch(url, {
      method: "HEAD",
      signal: controller.signal,
      redirect: "follow",
    });
    
    clearTimeout(timeoutId);
    
    // Accept various success codes
    return response.ok || [301, 302, 403].includes(response.status);
  } catch (error) {
    logDebug(`HTTP check failed for ${url}: ${error}`);
    return false;
  }
}

// Test domain
async function testDomain(domain: string): Promise<boolean> {
  logDebug(`Testing domain: ${domain}`);
  
  // DNS resolution
  const dnsOk = await checkDNS(domain);
  if (!dnsOk) {
    logError(`DNS resolution failed: ${domain}`);
    recordTest(false);
    return false;
  }
  
  // Special handling for NTP time servers (they don't serve HTTPS)
  if (domain.includes('time.android.com') || 
      domain.includes('time.cloudflare.com') || 
      domain.includes('.ntp.org')) {
    logSuccess(`DNS resolved (NTP server): ${domain}`);
    recordTest(true);
    return true;
  }
  
  // HTTP(S) check
  const httpOk = await checkHTTP(`https://${domain}`);
  if (httpOk) {
    logSuccess(`Reachable: ${domain}`);
    recordTest(true);
    return true;
  }
  
  // Fallback to TCP
  const tcpOk = await checkTCP(domain, 443);
  if (tcpOk) {
    logSuccess(`TCP reachable: ${domain}`);
    recordTest(true);
    return true;
  }
  
  logError(`Connectivity failed: ${domain}`);
  recordTest(false);
  return false;
}

// Test IP
async function testIP(ip: string): Promise<boolean> {
  logDebug(`Testing IP: ${ip}`);
  
  // TCP connectivity test
  const tcpOk = await checkTCP(ip, 443);
  if (tcpOk) {
    logSuccess(`TCP reachable: ${ip}`);
    recordTest(true);
    return true;
  }
  
  logError(`Unreachable: ${ip}`);
  recordTest(false);
  return false;
}

// Get public IP
async function getPublicIP() {
  printSection("Public IP Address");
  
  try {
    const response = await fetch("https://api.ipify.org?format=json", {
      signal: AbortSignal.timeout(config.timeout),
    });
    const data = await response.json();
    logSuccess(`Public IPv4: ${data.ip}`);
    return true;
  } catch (error) {
    logWarn("Could not determine public IP");
    return false;
  }
}

// Test all domains
async function testAllDomains() {
  printSection("Testing Stripe Core Domains");
  
  const results = await Promise.all(
    STRIPE_DOMAINS.map(domain => testDomain(domain))
  );
  
  printSection("Testing Stripe Terminal Domains");
  await Promise.all(
    STRIPE_TERMINAL_DOMAINS.map(domain => testDomain(domain))
  );
  
  return results;
}

// Test sample IPs
async function testSampleIPs() {
  printSection("Testing Sample Stripe API IPs");
  
  logInfo(`Testing subset of ${STRIPE_API_IPS.length} API IPs`);
  await Promise.all(
    STRIPE_API_IPS.map(ip => testIP(ip))
  );
}

// Test webhook IPs
async function testWebhookIPs() {
  printSection("Testing Stripe Webhook IPs");
  
  logInfo(`Testing all ${STRIPE_WEBHOOK_IPS.length} webhook IPs`);
  await Promise.all(
    STRIPE_WEBHOOK_IPS.map(ip => testIP(ip))
  );
}

// Test API health
async function testAPIHealth() {
  printSection("Testing Stripe API Health");
  
  try {
    logInfo("Checking api.stripe.com/healthcheck");
    const response = await fetch("https://api.stripe.com/healthcheck", {
      signal: AbortSignal.timeout(config.timeout),
    });
    
    if (response.ok) {
      logSuccess("API health check passed");
      recordTest(true);
      return true;
    } else {
      logError(`API health check failed: ${response.status}`);
      recordTest(false);
      return false;
    }
  } catch (error) {
    logError(`API health check failed: ${error}`);
    recordTest(false);
    return false;
  }
}

// Print summary
function printSummary() {
  printSection("Test Summary");
  
  console.log(`Total Tests:  ${totalTests}`);
  console.log(`${colors.green}Passed:       ${passedTests}${colors.reset}`);
  if (failedTests > 0) {
    console.log(`${colors.red}Failed:       ${failedTests}${colors.reset}`);
  } else {
    console.log(`Failed:       ${failedTests}`);
  }
  
  if (totalTests > 0) {
    const successRate = Math.round((passedTests / totalTests) * 100);
    console.log(`Success Rate: ${successRate}%`);
  }
  
  console.log();
  if (failedTests === 0) {
    logSuccess("All tests passed!");
    return true;
  } else {
    logError("Some tests failed. Check your network configuration.");
    return false;
  }
}

// Usage information
function printUsage() {
  console.log(`
Usage: bun run test.ts [OPTIONS]

Test connectivity to Stripe domains and IP addresses.

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -t, --timeout MS    Set timeout in milliseconds (default: 5000)
    --no-domains        Skip domain tests
    --no-ips            Skip IP tests
    --no-webhooks       Skip webhook IP tests
    --domains-only      Test only domains
    --ips-only          Test only IPs

ENVIRONMENT VARIABLES:
    TIMEOUT             Timeout in milliseconds (default: 5000)
    VERBOSE             Enable verbose mode (0 or 1)
    TEST_DOMAINS        Test domains (0 or 1, default: 1)
    TEST_IPS            Test IPs (0 or 1, default: 1)
    TEST_WEBHOOKS       Test webhook IPs (0 or 1, default: 1)

EXAMPLES:
    bun run test.ts                     # Run all tests
    bun run test.ts --verbose           # Run with verbose output
    bun run test.ts --domains-only      # Test only domains
    bun run test.ts --timeout 10000     # Use 10 second timeout
`);
}

// Parse arguments
function parseArgs() {
  const args = process.argv.slice(2);
  
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    
    switch (arg) {
      case "-h":
      case "--help":
        printUsage();
        process.exit(0);
        break;
      case "-v":
      case "--verbose":
        config.verbose = true;
        break;
      case "-t":
      case "--timeout":
        config.timeout = parseInt(args[++i]);
        break;
      case "--no-domains":
        config.testDomains = false;
        break;
      case "--no-ips":
        config.testIPs = false;
        break;
      case "--no-webhooks":
        config.testWebhooks = false;
        break;
      case "--domains-only":
        config.testDomains = true;
        config.testIPs = false;
        config.testWebhooks = false;
        break;
      case "--ips-only":
        config.testDomains = false;
        config.testIPs = true;
        config.testWebhooks = true;
        break;
      default:
        logError(`Unknown option: ${arg}`);
        printUsage();
        process.exit(1);
    }
  }
}

// Main function
async function main() {
  parseArgs();
  
  logInfo("Starting Stripe Reachability Tests");
  logInfo(`Timeout: ${config.timeout}ms`);
  console.log();
  
  await checkSystem();
  await getPublicIP();
  
  if (config.testDomains) {
    await testAllDomains();
  }
  
  if (config.testIPs) {
    await testSampleIPs();
  }
  
  if (config.testWebhooks) {
    await testWebhookIPs();
  }
  
  await testAPIHealth();
  
  const success = printSummary();
  process.exit(success ? 0 : 1);
}

// Run main function
main().catch((error) => {
  logError(`Unhandled error: ${error}`);
  process.exit(1);
});
