# Stripe Reachability Testing Tools

Cross-platform connectivity testing tools for Stripe domains and IP addresses. This directory contains three implementations optimized for different use cases.

## Available Implementations

### 1. Bash Script (`/bin/test.sh`)
**Best for:** Unix/Linux systems, CI/CD pipelines, quick testing

**Pros:**
- No dependencies beyond standard Unix tools
- Works on any Unix-like system (Linux, macOS, BSD)
- Portable across most servers
- Easy to read and modify
- Small footprint

**Cons:**
- Limited to Unix-like systems
- Slower than compiled alternatives
- Less robust error handling
- Sequential execution for some operations

**Usage:**
```bash
# Make executable
chmod +x bin/test.sh

# Run all tests
./bin/test.sh

# Run with verbose output
./bin/test.sh --verbose

# Test only domains
./bin/test.sh --domains-only

# Custom timeout
./bin/test.sh --timeout 10

# Using environment variables
TIMEOUT=10 VERBOSE=1 ./bin/test.sh
```

### 2. Bun/TypeScript (`/bin/test.ts`)
**Best for:** Modern JavaScript/TypeScript environments, rapid development

**Pros:**
- True cross-platform (Windows, macOS, Linux)
- Fast execution with Bun runtime
- Modern async/await patterns
- Native TypeScript support
- Easy to extend and maintain
- Parallel execution by default
- Clean, readable code

**Cons:**
- Requires Bun runtime installation
- Larger runtime footprint than compiled binary
- Less portable than Bash for traditional Unix environments

**Installation:**
```bash
# Install Bun (if not already installed)
curl -fsSL https://bun.sh/install | bash

# Or on macOS with Homebrew
brew install oven-sh/bun/bun

# Or on Windows with PowerShell
powershell -c "irm bun.sh/install.ps1 | iex"
```

**Usage:**
```bash
# Run all tests
bun run bin/test.ts

# Run with verbose output
bun run bin/test.ts --verbose

# Test only domains
bun run bin/test.ts --domains-only

# Custom timeout (in milliseconds)
bun run bin/test.ts --timeout 10000

# Make it executable
chmod +x bin/test.ts
./bin/test.ts
```

### 3. Go Binary (`/bin/test.go`)
**Best for:** Production environments, maximum performance and portability

**Pros:**
- Single compiled binary (no dependencies)
- True cross-platform (compile for any OS/architecture)
- Fastest execution
- Excellent concurrency with goroutines
- Small binary size (~5-10MB)
- Most robust and production-ready
- Native parallelism

**Cons:**
- Requires Go toolchain to build
- Binary needs recompilation for code changes
- Slightly more complex to modify

**Building:**
```bash
# Build for current platform
go build -o stripe-reachability bin/test.go

# Build for specific platform
GOOS=linux GOARCH=amd64 go build -o stripe-reachability-linux bin/test.go
GOOS=darwin GOARCH=amd64 go build -o stripe-reachability-macos bin/test.go
GOOS=windows GOARCH=amd64 go build -o stripe-reachability.exe bin/test.go

# Build optimized binary (smaller size)
go build -ldflags="-s -w" -o stripe-reachability bin/test.go
```

**Usage:**
```bash
# Run all tests
./stripe-reachability

# Run with verbose output
./stripe-reachability --verbose

# Test only domains
./stripe-reachability --domains-only

# Custom timeout and parallel workers
./stripe-reachability --timeout 10 --parallel 20
```

## Feature Comparison

| Feature | Bash | Bun/TypeScript | Go |
|---------|------|----------------|-----|
| Cross-platform | Unix only | ✅ Full | ✅ Full |
| No dependencies | ✅ | Requires Bun | ✅ Binary |
| Performance | Moderate | Fast | Fastest |
| Parallel execution | Limited | ✅ | ✅ Best |
| Easy to modify | ✅ | ✅ | Moderate |
| Production-ready | Good | Good | ✅ Best |
| Binary size | N/A | ~50MB runtime | ~5-10MB |
| Windows support | ❌ | ✅ | ✅ |
| Error handling | Basic | Good | ✅ Excellent |

## What Gets Tested

All implementations test connectivity to:

### Core Stripe Domains
- `api.stripe.com` - Main API endpoint
- `files.stripe.com` - File uploads
- `hooks.stripe.com` - Webhooks
- `js.stripe.com` - Stripe.js library
- `dashboard.stripe.com` - Dashboard
- And 30+ other Stripe services

### Stripe Terminal Domains
- `armada.stripe.com` - Terminal management
- `gator.stripe.com` - Terminal configuration
- NTP time servers
- Terminal device communication

### IP Addresses
- Sample Stripe API IP addresses
- All webhook source IP addresses
- Tests both DNS resolution and TCP connectivity

### Additional Checks
- DNS resolution
- TCP port 443 connectivity
- HTTPS/TLS validation
- API health endpoint
- Network route tracing (when available)
- Public IP detection

## Common Options

All implementations support similar options:

```bash
# Help
--help, -h

# Verbose output
--verbose, -v

# Custom timeout
--timeout N  # seconds for bash/go, milliseconds for bun

# Skip domain tests
--no-domains

# Skip IP tests
--no-ips

# Skip webhook IP tests
--no-webhooks

# Test only domains
--domains-only

# Test only IPs
--ips-only
```

## Testing All Stripe IPs

Currently, the tools test a **sample** of Stripe API IPs for performance. To test ALL IPs:

### Bash
```bash
# Download full IP list
curl -s https://stripe.com/files/ips/ips_api.txt > stripe_ips.txt

# Modify test.sh to read from file
# Add loop to test each IP
```

### Bun/TypeScript
```typescript
// Fetch IPs dynamically
const response = await fetch('https://stripe.com/files/ips/ips_api.json');
const ips = await response.json();
// Test all IPs
```

### Go
```go
// Fetch and test all IPs
resp, _ := http.Get("https://stripe.com/files/ips/ips_api.json")
// Parse JSON and test each IP
```

## License

These tools are provided as-is for testing Stripe connectivity.
