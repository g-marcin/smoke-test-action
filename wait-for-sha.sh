#!/usr/bin/env bash
# wait-for-sha.sh HEALTH_URL EXPECTED_SHA [WAIT_SECONDS=60] [HEADER=X-Git-Sha]
# Polls HEALTH_URL until HEADER equals EXPECTED_SHA, i.e. the freshly deployed process is serving.
set -uo pipefail

url="$1" expected="$2" wait="${3:-60}" header="${4:-X-Git-Sha}"
interval=5
attempts=$(( (wait + interval - 1) / interval ))
header_lc="$(echo "$header" | tr '[:upper:]' '[:lower:]')"

for i in $(seq 1 "$attempts"); do
    sha="$(curl -s --max-time 5 -o /dev/null -D - "$url" | tr -d '\r' | awk -F': ' -v h="$header_lc" 'tolower($1)==h{print $2}')"
    if [[ "$sha" == "$expected" ]]; then
        echo "Live on $sha"
        exit 0
    fi
    echo "Attempt $i/$attempts: $header='${sha:-none}', waiting..."
    sleep "$interval"
done

echo "::error::$url did not report $expected in $header within ${wait}s"
exit 1
