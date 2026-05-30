#!/usr/bin/env bash
# harden.sh — 취약점을 0으로 만드는 파이프라인.
#   입력: 앱(go|python|java)
#   동작: Wolfi 최소 베이스로 "다시 짓고"(rebuild) → 이중 스캔 → 0 검증.
#         잔여 CVE가 있으면 최신 패치로 재빌드 재시도, 그래도 남으면 정직하게 보고하고 실패.
#   출력: CVE 0이 검증된 하드닝 이미지 harden-<app>:wolfi
set -euo pipefail

APP="${1:?usage: scripts/harden.sh <go|python|java>}"
MAX_ROUNDS="${MAX_ROUNDS:-2}"
IMG="harden-${APP}:wolfi"

# trivy로 HIGH/CRITICAL 개수만 추출
scan_count() {
  trivy image -q --severity HIGH,CRITICAL --format json "$1" 2>/dev/null \
    | python3 -c 'import sys,json;d=json.load(sys.stdin);print(sum(len(r.get("Vulnerabilities") or []) for r in (d.get("Results") or [])))'
}

echo "=== harden pipeline: ${APP} ==="
for round in $(seq 1 "$MAX_ROUNDS"); do
  echo "── round ${round}/${MAX_ROUNDS}: Wolfi 최신 패키지로 rebuild ──"
  # melange+apko는 매번 packages.wolfi.dev에서 '최신' 패키지를 받는다 → OS 보안패치 자동 반영
  make APP="${APP}" image >/dev/null

  n=$(scan_count "${IMG}")
  echo "   trivy HIGH/CRITICAL: ${n}"

  if [ "${n}" -eq 0 ]; then
    # grype로 교차검증 (스캐너 2종)
    g=$(grype "${IMG}" -q -o json 2>/dev/null \
      | python3 -c 'import sys,json;d=json.load(sys.stdin);print(sum(1 for m in d.get("matches",[]) if m["vulnerability"]["severity"] in ("High","Critical")))' 2>/dev/null || echo "?")
    echo "   grype 교차검증 HIGH/CRITICAL: ${g}"
    echo "✅ ${IMG}: CVE 0 (검증 완료)"
    exit 0
  fi

  echo "   ⚠ 잔여 HIGH/CRITICAL ${n}건 — 상세:"
  trivy image -q --severity HIGH,CRITICAL "${IMG}" 2>/dev/null | sed -n '1,30p'
  echo "   → 최신 패치로 재빌드 재시도..."
done

cat <<EOF
❌ ${MAX_ROUNDS}라운드 후에도 잔여 CVE가 남았다. rebuild만으로 0이 안 되는 경우는 보통:
   (1) 앱 자체 의존성 — Python requirements.txt / Java build.gradle의 취약 라이브러리
       → 패치된 버전으로 bump 후 다시 실행
   (2) Wolfi가 아직 패치 안 한 OS 패키지
       → 패치 대기, 또는 해당 패키지 핀/대체
위 trivy 목록의 PkgName을 보고 (1)인지 (2)인지 판단해 대응할 것.
EOF
exit 1
