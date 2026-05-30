#!/usr/bin/env bash
set -euo pipefail

REG=localhost:5050

echo "== cosign verify =="
DIGEST=$(docker inspect --format='{{range .RepoDigests}}{{println .}}{{end}}' "$REG/harden:wolfi" | grep "^$REG/" | head -1)
# 로컬 키 서명이라 투명성 로그(tlog)를 쓰지 않으므로 검증 시에도 무시한다.
cosign verify --key keys/cosign.pub --insecure-ignore-tlog --allow-insecure-registry "$DIGEST"

echo
echo "== SBOM 패키지 목록 (apko 생성) =="
SBOM=$(ls sbom/sbom-*.spdx.json | head -1)
echo "file: $SBOM"
python3 -c "import sys,json; d=json.load(open('$SBOM')); [print(' -', p.get('name'), p.get('versionInfo','')) for p in d.get('packages',[])]"
