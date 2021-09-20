#!/bin/bash
set -eu

run() {
    echo >&2 "+ $*"
    "$@"
}

check() {
    name="$1"
    echo "========================================"
    echo "Checking $name..."

    "check_$name" && ret=$? || ret=$?
    if [ $ret -eq 0 ]; then
        echo "OK: $name check"
    else
        echo "ERROR: $name check failed"
    fi
}

check_os() {
    uname="$(uname)"
    case "$uname" in
        Linux|Darwin)
            ;;
        *)
            echo "WARNING: not tested on $uname"
            return 1
            ;;
    esac
}

check_ip() {
  run curl -4 --write-out "\n" ifconfig.co/json 
}

dig_short() {
    output="$(dig +short "$@")"
    if [ -z "$output" ]; then
        echo >&2 "Error: command returned no output: dig +short $*"
        return 1
    fi
    echo "$output"
}

check_route() {
    if command -v mtr 2>/dev/null; then
        run mtr -n --report api.stripe.com
    elif command -v traceroute 2>/dev/null; then
        run traceroute -n -m 20 api.stripe.com
    fi
}

check_curl_https() {
    run curl -Iv https://api.stripe.com/healthcheck
}

check_curl_terminal_https() {
    run curl -Iv https://armada.stripe.com
    run curl -Iv https://gator.stripe.com
}

gethostbyname() {
    run python -c "import socket; print socket.gethostbyname('$1')"
}

auto_test_all() {
    check os
    check ip
    check route
    check curl_https
    check curl_terminal_https
}

auto_test_all
