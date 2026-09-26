#!/usr/bin/env bash
# Smoke-test helpers. Source this from a service's smoke script:
#
#   # In CI the action sets APP_SMOKE_TEST_LIB; locally the pinned version is fetched.
#   if [[ -n "${APP_SMOKE_TEST_LIB:-}" ]]; then source "$APP_SMOKE_TEST_LIB"
#   else source <(curl -fsSL https://raw.githubusercontent.com/g-marcin/smoke-test-action/v1/lib.sh); fi
#   smoke_init "${1:-https://api.example.com}"
#   check_json "healthcheck" "/healthcheck" '.status == "success"'
#   finish
#
# Env:
#   EXPECTED_SHA    check_sha fails unless the health endpoint reports this commit
#   SMOKE_TIMEOUT   per-request timeout in seconds (default 10)

set -uo pipefail

SMOKE_BASE=""
SMOKE_FAILED=0

pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s -- %s\n' "$1" "$2"; SMOKE_FAILED=$((SMOKE_FAILED + 1)); }
info() { printf '  INFO %s\n' "$1"; }

# All requests time out so a hung service fails the run instead of stalling it.
http() { curl -s --max-time "${SMOKE_TIMEOUT:-10}" "$@"; }

# header_value URL HEADER [curl args...]: prints the value of a response header (case-insensitive).
header_value() {
    local url="$1" name="$2"; shift 2
    http -o /dev/null -D - "$@" "$url" | tr -d '\r' \
        | awk -F': ' -v h="$(echo "$name" | tr '[:upper:]' '[:lower:]')" 'tolower($1)==h{print $2}'
}

# smoke_init BASE_URL
smoke_init() {
    SMOKE_BASE="${1%/}"
    echo "Smoke testing $SMOKE_BASE"
}

# check_status NAME PATH [EXPECTED_CODE=200]
check_status() {
    local name="$1" path="$2" want="${3:-200}" code
    code="$(http -o /dev/null -w '%{http_code}' "$SMOKE_BASE$path")"
    [[ "$code" == "$want" ]] && pass "$name" || fail "$name" "HTTP $code, expected $want"
}

# check_json NAME PATH JQ_FILTER: expects 200 and a truthy jq filter on the body.
check_json() {
    local name="$1" path="$2" filter="$3" body code
    body="$(http -w '\n%{http_code}' "$SMOKE_BASE$path")"
    code="${body##*$'\n'}"
    body="${body%$'\n'*}"
    if [[ "$code" != "200" ]]; then
        fail "$name" "HTTP $code"
    elif ! echo "$body" | jq -e "$filter" >/dev/null 2>&1; then
        fail "$name" "unexpected body: ${body:0:120}"
    else
        pass "$name"
    fi
}

# check_redirect NAME PATH EXPECTED_FINAL_PATH: follows redirects, expects 200 at SMOKE_BASE+EXPECTED_FINAL_PATH.
check_redirect() {
    local name="$1" path="$2" want="$SMOKE_BASE$3" code url
    read -r code url < <(http -o /dev/null -L -w '%{http_code} %{url_effective}\n' "$SMOKE_BASE$path")
    [[ "$code" == "200" && "$url" == "$want" ]] && pass "$name" || fail "$name" "ended at $url with HTTP $code"
}

# check_sha [HEALTH_PATH=/healthcheck] [HEADER=X-Git-Sha]: compares the deployed commit with EXPECTED_SHA.
check_sha() {
    local path="${1:-/healthcheck}" header="${2:-X-Git-Sha}" sha
    sha="$(header_value "$SMOKE_BASE$path" "$header")"
    if [[ -z "${EXPECTED_SHA:-}" ]]; then
        info "deployed commit: ${sha:-unknown}"
    elif [[ "$sha" == "$EXPECTED_SHA" ]]; then
        pass "deployed commit is $EXPECTED_SHA"
    else
        fail "deployed commit" "expected $EXPECTED_SHA, got '${sha:-none}'"
    fi
}

# check_cors ORIGIN [PATH=/healthcheck]: expects Access-Control-Allow-Origin to echo ORIGIN.
check_cors() {
    local origin="$1" path="${2:-/healthcheck}" acao
    acao="$(header_value "$SMOKE_BASE$path" "access-control-allow-origin" -H "Origin: $origin")"
    [[ "$acao" == "$origin" ]] && pass "CORS allows $origin" || fail "CORS" "access-control-allow-origin is '${acao:-missing}' for $origin"
}

# check_image_from NAME PATH [JQ_URL_FILTER=.message]: takes an image URL from a JSON endpoint and fetches it.
check_image_from() {
    local name="$1" path="$2" filter="${3:-.message}" img code ctype
    img="$(http "$SMOKE_BASE$path" | jq -r "$filter // empty" 2>/dev/null)"
    if [[ -z "$img" ]]; then
        fail "$name" "no image URL at $path ($filter)"
        return
    fi
    read -r code ctype < <(http -o /dev/null -w '%{http_code} %{content_type}\n' "$img")
    [[ "$code" == "200" && "$ctype" == image/* ]] && pass "$name ($ctype)" || fail "$name" "$img -> HTTP $code, ${ctype:-no content-type}"
}

# finish: prints the summary and exits non-zero if any check failed.
finish() {
    echo
    if [[ "$SMOKE_FAILED" -gt 0 ]]; then
        echo "$SMOKE_FAILED check(s) failed"
        exit 1
    fi
    echo "All checks passed"
}
