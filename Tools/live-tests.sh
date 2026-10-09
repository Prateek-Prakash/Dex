#!/bin/zsh
# Runs DexTests/WebUILiveTests against the real Open WebUI server.
#
# The account comes from the login Keychain, never a file. Once:
#   security add-generic-password -s "Dex Live Tests" -a you@example.com -w
# (it asks for the password). Then: Tools/live-tests.sh [extra xcodebuild args]
# Set DEX_LIVE_SERVER to test another server than https://webui.teek.dev.
set -euo pipefail
cd "$(dirname "$0")/.."

service="Dex Live Tests"
email=$(security find-generic-password -s "$service" 2>/dev/null | awk -F'"' '/"acct"/ { print $4 }') || true
if [[ -z "${email:-}" ]]; then
  echo "No \"$service\" item in the Keychain. Add one with:" >&2
  echo "  security add-generic-password -s \"$service\" -a you@example.com -w" >&2
  exit 1
fi
password=$(security find-generic-password -s "$service" -w)

# TEST_RUNNER_ variables reach the test process without the prefix.
TEST_RUNNER_DEX_LIVE=1 \
TEST_RUNNER_DEX_LIVE_EMAIL="$email" \
TEST_RUNNER_DEX_LIVE_PASSWORD="$password" \
TEST_RUNNER_DEX_LIVE_SERVER="${DEX_LIVE_SERVER:-https://webui.teek.dev}" \
xcodebuild test -scheme Dex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:DexTests/WebUILiveTests "$@"
