#!/usr/bin/env bash
set -euo pipefail

count_vulns() {
  trivy image -q --severity HIGH,CRITICAL --format json "$1" 2>/dev/null \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print(sum(len(r.get("Vulnerabilities") or []) for r in (d.get("Results") or [])))'
}

printf "%-14s %-12s %s\n" "IMAGE" "SIZE" "HIGH+CRIT CVE"
printf "%-14s %-12s %s\n" "-----" "----" "-------------"
for img in harden:naive harden:wolfi; do
  size=$(docker images --format '{{.Size}}' "$img" | head -1)
  vulns=$(count_vulns "$img")
  printf "%-14s %-12s %s\n" "$img" "${size:-N/A}" "$vulns"
done
