# smoke-test-action

Post-deploy smoke tests for HTTP services:

1. Waits until the service's health endpoint reports the deployed commit (`X-Git-Sha` header), so tests hit the new process, not the old one.
2. Runs the service's own smoke script with shared helpers from `lib.sh`.

## Usage

```yaml
smoke-test:
  needs: deploy
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: g-marcin/smoke-test-action@v1
      with:
        url: https://api.example.com
```

| Input | Default | |
|---|---|---|
| `url` | required | Base URL of the deployed service |
| `expected-sha` | `github.sha` | Commit the service must report |
| `health-path` | `/healthcheck` | Endpoint returning the commit header |
| `sha-header` | `X-Git-Sha` | Header carrying the commit |
| `wait-seconds` | `60` | Max wait for the new version |
| `script` | `scripts/smoke_test.sh` | Service script, gets the URL as `$1` |

## Service contract

- Deploy passes the commit to the service (e.g. `API_GIT_SHA=${{ github.sha }}` in its env).
- Health endpoint returns it in the `X-Git-Sha` response header.

## Service script

```bash
#!/usr/bin/env bash
if [[ -n "${APP_SMOKE_TEST_LIB:-}" ]]; then source "$APP_SMOKE_TEST_LIB"
else source <(curl -fsSL https://raw.githubusercontent.com/g-marcin/smoke-test-action/v1/lib.sh); fi

smoke_init "${1:-https://api.example.com}"
check_json "healthcheck" "/healthcheck" '.status == "success"'
check_sha
check_cors "https://example.com"
check_image_from "image served" "/images/random"
check_status "metrics exposed" "/metrics"
finish
```

In CI the action sets `APP_SMOKE_TEST_LIB`; locally the pinned `v1` lib is fetched, so `scripts/smoke_test.sh http://localhost:8000` works without CI.

## Helpers

| Helper | Checks |
|---|---|
| `smoke_init URL` | Sets the base URL |
| `check_status NAME PATH [CODE=200]` | Status code |
| `check_json NAME PATH JQ` | 200 + truthy jq filter on body |
| `check_redirect NAME PATH FINAL_PATH` | Redirect chain ends at `FINAL_PATH` with 200 |
| `check_sha [PATH] [HEADER]` | Header equals `EXPECTED_SHA` (info only if unset) |
| `check_cors ORIGIN [PATH]` | `Access-Control-Allow-Origin` echoes `ORIGIN` |
| `check_image_from NAME PATH [JQ=.message]` | URL from JSON serves 200 `image/*` |
| `finish` | Summary, exit 1 on any failure |

All requests time out after `SMOKE_TIMEOUT` seconds (default 10). Keep checks read-only.

## Versioning

Consumers pin `@v1`. Move the `v1` tag for non-breaking changes; breaking changes get `v2`.
