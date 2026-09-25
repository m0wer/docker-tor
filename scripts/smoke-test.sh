#!/bin/bash
# Smoke test a docker-tor image: start it with the default configuration,
# wait for Tor to bootstrap, then verify that traffic through the SOCKS proxy
# exits via Tor and that a well-known onion service is reachable.
#
# Usage: scripts/smoke-test.sh [IMAGE]
set -euo pipefail

IMAGE="${1:-docker-tor:test}"
NAME="docker-tor-smoke-$$"
SOCKS_PORT="${SOCKS_PORT:-19050}"
BOOTSTRAP_TIMEOUT="${BOOTSTRAP_TIMEOUT:-300}"
# The Tor Project website onion service (https://www.torproject.org/).
ONION_URL="${ONION_URL:-http://2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion/}"
ONION_EXPECT="${ONION_EXPECT:-Tor Project}"

cleanup() {
    status=$?
    if [ "$status" -ne 0 ]; then
        echo "--- container logs ---"
        docker logs "$NAME" 2>&1 | tail -n 50 || true
    fi
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    exit "$status"
}
trap cleanup EXIT

# Retry a command up to N times with a delay, for flaky Tor circuits.
retry() {
    local attempts="$1"
    shift
    local i
    for ((i = 1; i <= attempts; i++)); do
        if "$@"; then
            return 0
        fi
        echo "Attempt $i/$attempts failed, retrying..." >&2
        sleep 10
    done
    return 1
}

echo "Starting $IMAGE"
docker run -d --name "$NAME" -p "127.0.0.1:$SOCKS_PORT:9050" "$IMAGE" >/dev/null

echo "Tor version: $(docker exec "$NAME" tor --version | head -n 1)"

echo "Waiting up to ${BOOTSTRAP_TIMEOUT}s for Tor to bootstrap"
deadline=$((SECONDS + BOOTSTRAP_TIMEOUT))
until docker logs "$NAME" 2>&1 | grep -q 'Bootstrapped 100%'; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$NAME")" != "true" ]; then
        echo "Container exited unexpectedly" >&2
        exit 1
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
        echo "Timed out waiting for bootstrap" >&2
        exit 1
    fi
    sleep 5
done
echo "Tor bootstrapped"

proxy="socks5h://127.0.0.1:$SOCKS_PORT"

# Capture bodies before matching: piping into `grep -q` makes curl fail with
# a write error under pipefail once grep exits early.
check_is_tor() {
    local body
    body="$(curl -fsS --max-time 60 --proxy "$proxy" https://check.torproject.org/api/ip)" || return 1
    echo "$body"
    grep -q '"IsTor":true' <<<"$body"
}

check_onion() {
    local body
    body="$(curl -fsSL --max-time 120 --proxy "$proxy" "$ONION_URL")" || return 1
    grep -q "$ONION_EXPECT" <<<"$body"
}

echo "Checking exit traffic goes through Tor"
retry 5 check_is_tor
echo

echo "Fetching $ONION_URL"
retry 5 check_onion
echo "Onion service reachable"

echo "Smoke test passed"
