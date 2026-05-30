#!/usr/bin/env bash
set -euo pipefail

count_vulns() {
  trivy image -q --severity HIGH,CRITICAL --format json "$1" 2>/dev/null \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print(sum(len(r.get("Vulnerabilities") or []) for r in (d.get("Results") or [])))'
}

size_of() { docker images --format '{{.Size}}' "$1" 2>/dev/null | head -1; }

printf "%-8s | %-10s %-6s | %-10s %-6s\n" "LANG" "naive" "CVE" "wolfi" "CVE"
printf "%-8s-+-%-10s-%-6s-+-%-10s-%-6s\n" "--------" "----------" "------" "----------" "------"
for lang in go python java; do
  ni="harden-$lang:naive"; wi="harden-$lang:wolfi"
  ns=$(size_of "$ni"); ws=$(size_of "$wi")
  nv=$(count_vulns "$ni"); wv=$(count_vulns "$wi")
  printf "%-8s | %-10s %-6s | %-10s %-6s\n" "$lang" "${ns:-N/A}" "${nv:-?}" "${ws:-N/A}" "${wv:-?}"
done
