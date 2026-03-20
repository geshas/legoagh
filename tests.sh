#!/bin/bash

# A simple test script for lego.sh to verify its behavior and catch regressions.
# It mocks the lego binary to capture arguments.

set -e -u

# Setup mock environment
TEST_DIR="test_workspace"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
cp lego.sh "$TEST_DIR/"
cd "$TEST_DIR"

# Create a mock lego binary
cat <<EOF > lego
#!/bin/bash
# Just echo the arguments for testing
echo "ARGS: \$*"

mkdir -p ./.lego/certificates/
# Fixed: The script expects _.domain.name.crt
touch "./.lego/certificates/_.\${DOMAIN_NAME}.crt"
touch "./.lego/certificates/_.\${DOMAIN_NAME}.key"

# Find and execute the hook if it's there
# We're looking for --run-hook <command> or --renew-hook <command>
last_arg=""
for arg in "\$@"; do
    if [[ "\$last_arg" == "--run-hook" || "\$last_arg" == "--renew-hook" ]]; then
        echo "Executing hook: \$arg"
        eval "\$arg"
    fi
    last_arg="\$arg"
done
EOF
chmod +x lego

# Create a mock curl to avoid downloading
cat <<EOF > curl
#!/bin/bash
if [[ "\$*" == *"api.github.com"* ]]; then
  echo '{"browser_download_url": "https://example.com/lego_linux_amd64.tar.gz"}'
else
  touch lego.tar.gz
fi
EOF
chmod +x curl
# Create a mock tar
cat <<EOF > tar
#!/bin/bash
exit 0
EOF
chmod +x tar
export PATH=".:$PATH"

# Function to run lego.sh and check output
run_test() {
    local name="$1"
    shift
    echo "----------------------------------------"
    echo "Running test: $name"
    if env "$@" bash lego.sh > output.txt 2>&1; then
        if [ "${EXPECT_FAIL:-0}" -eq 1 ]; then
            echo "Test $name FAILED (expected failure but passed)"
            return 1
        fi
        echo "Test $name passed"
    else
        if [ "${EXPECT_FAIL:-0}" -eq 1 ]; then
            echo "Test $name passed (failed as expected)"
            return 0
        fi
        echo "Test $name FAILED (exit code $?)"
        cat output.txt
        return 0 # Continue with other tests
    fi
    # Look for the ARGS line from our mock lego
    grep "ARGS:" output.txt || echo "No ARGS found in output (maybe lego didn't run?)"
}

# Test 1: Cloudflare Happy Path
run_test "Cloudflare Happy Path" \
    DOMAIN_NAME="example.org" \
    EMAIL="user@example.org" \
    DNS_PROVIDER="cloudflare" \
    CLOUDFLARE_DNS_API_TOKEN="tok123"

# Test 2: Namedotcom (Reproduction of bug)
run_test "Namedotcom Bug Repro" \
    DOMAIN_NAME="example.org" \
    EMAIL="user@example.org" \
    DNS_PROVIDER="namedotcom" \
    NAMECOM_USERNAME="user" \
    NAMECOM_API_TOKEN="tok123" \
    SERVER="https://acme.zerossl.com" \
    EAB_KID="kid123" \
    EAB_HMAC="hmac123"

# Test 3: Dreamhost (Reproduction of bug - renew)
run_test "Dreamhost Renew Bug Repro" \
    DOMAIN_NAME="example.org" \
    EMAIL="user@example.org" \
    DNS_PROVIDER="dreamhost" \
    DREAMHOST_API_KEY="key123" \
    CMDTYPE="renew" \
    HOOK="echo 'Success'"

# Test 4: Generic Provider (New feature)
run_test "Generic Provider (porkbun)" \
    DOMAIN_NAME="example.org" \
    EMAIL="user@example.org" \
    DNS_PROVIDER="porkbun" \
    PORKBUN_API_KEY="pk123" \
    PORKBUN_SECRET_API_KEY="sk123"

# Test 5: Run Hook with spaces
run_test "Run Hook with spaces" \
    DOMAIN_NAME="example.org" \
    EMAIL="user@example.org" \
    DNS_PROVIDER="digitalocean" \
    DO_AUTH_TOKEN="tok123" \
    HOOK="/usr/bin/touch /tmp/done"

# Test 6: Invalid domain validation
EXPECT_FAIL=1 run_test "Invalid domain validation" \
    DOMAIN_NAME="example.org; echo 'HACKED'" \
    EMAIL="user@example.org" \
    DNS_PROVIDER="cloudflare" \
    CLOUDFLARE_DNS_API_TOKEN="tok123"

echo "----------------------------------------"
echo "All tests completed."
