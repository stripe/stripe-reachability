# stripe-reachability

A bash script to check if your computer can reach `api.stripe.com`.

## Usage

From the root of the repository run the test script.


    ./bin/test.sh

If successful, you should see output similar to the text below.

```
========================================
Checking os...
OK: os check
========================================
Checking dns...
OK: dns check
========================================
Checking ping...
OK: ping check
========================================
Checking mtr...
OK: mtr check
========================================
Checking curl_https...
OK: curl_https check
========================================
Checking curl_http...
OK: curl_http check
========================================
```
