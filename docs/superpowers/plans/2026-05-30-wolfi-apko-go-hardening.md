# Wolfi/apko Go 이미지 하드닝 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 최소 Go HTTP 서버를 melange로 apk 패키지화하고 apko로 Dockerfile 없이 하드닝 이미지로 조립한 뒤, cosign 서명·SBOM·취약점 스캔으로 일반 golang 이미지 대비 하드닝 효과를 증명한다.

**Architecture:** 두 갈래로 같은 앱을 이미지화한다 — (1) before: 표준 `golang` 베이스를 그대로 쓴 `Dockerfile.naive`, (2) after: melange(`.apk` 빌드) → apko(이미지 조립) → 로컬 registry push → cosign 서명. 마지막에 trivy/grype로 양쪽을 스캔해 크기·CVE를 표로 비교한다. melange/apko는 로컬 설치 없이 Chainguard 공식 Docker 이미지로 실행한다.

**Tech Stack:** Go 1.26, Docker, cgr.dev/chainguard/melange, cgr.dev/chainguard/apko, cosign, trivy, grype, syft, registry:2, GNU Make.

---

## 환경 전제 (모든 Task 공통)

- **arm64 Mac.** 모든 melange/apko 빌드는 `--arch aarch64`로 호스트 아키텍처만 대상으로 한다.
- **cgr.dev credential helper 함정:** `~/.docker/config.json`에 `credHelpers.cgr.dev=cgr`가 설정돼 있으나 `docker-credential-cgr`가 미설치 → cgr.dev 익명 pull이 실패한다. 해결: 프로젝트 로컬 빈 docker config(`.docker-anon/config.json = {}`)를 만들고 `DOCKER_CONFIG`를 거기로 지정한다. 모든 대상 이미지(golang, melange, apko, registry)는 public이라 익명 pull로 충분하다.
- **melange는 `--privileged` 필요** (빌드 샌드박스 생성). apko는 불필요.

## File Structure

```
image-harden/
├── app/
│   ├── main.go              # 최소 Go HTTP 서버
│   ├── main_test.go         # 핸들러 단위 테스트
│   └── go.mod               # module hello
├── melange.yaml             # apk 패키지 빌드 정의
├── apko.yaml                # 이미지 조립 정의 (non-root, entrypoint)
├── Dockerfile.naive         # 비교용 "before" 이미지
├── Makefile                 # 전 단계 오케스트레이션 (Task마다 타겟 추가)
├── scripts/
│   ├── compare.sh           # 크기 + CVE 비교 표
│   └── verify.sh            # cosign verify + SBOM 확인
├── .docker-anon/config.json # 빈 docker config (credential helper 우회)
├── keys/                    # melange/cosign 키 (.gitignore)
├── packages/                # melange 산출물 (.gitignore)
├── sbom/                    # apko SBOM 산출물 (.gitignore)
└── README.md               # 단계별 학습 설명서
```

`.gitignore`는 spec 커밋 시 이미 생성됨(`keys/`, `*.apk`, `packages/`, `sbom-*`, `*.sig`). 이 계획에서 `sbom/`, `.docker-anon/`, `*.tar` 항목을 추가한다.

---

### Task 1: Go HTTP 서버 + 단위 테스트 (TDD)

**Files:**
- Create: `app/go.mod`
- Create: `app/main.go`
- Test: `app/main_test.go`

- [ ] **Step 1: go.mod 작성**

`app/go.mod`:
```
module hello

go 1.26
```

- [ ] **Step 2: 실패하는 테스트 작성**

`app/main_test.go`:
```go
package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRootHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()

	rootHandler(rec, req)

	res := rec.Result()
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", res.StatusCode)
	}
	body, _ := io.ReadAll(res.Body)
	if !strings.Contains(string(body), "hello, hardened") {
		t.Fatalf("unexpected body: %q", string(body))
	}
}
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `cd app && go test ./...`
Expected: FAIL — `undefined: rootHandler`

- [ ] **Step 4: 최소 구현 작성**

`app/main.go`:
```go
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func rootHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintln(w, "hello, hardened")
}

func main() {
	http.HandleFunc("/", rootHandler)
	addr := ":8080"
	log.Printf("listening on %s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Println(err)
		os.Exit(1)
	}
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `cd app && go test ./...`
Expected: PASS — `ok  	hello`

- [ ] **Step 6: 커밋**

```bash
git add app/
git commit -m "feat: 최소 Go HTTP 서버 + 핸들러 테스트"
```

---

### Task 2: 비교용 naive 이미지 + Makefile 기초

**Files:**
- Create: `Dockerfile.naive`
- Create: `Makefile`
- Create: `.docker-anon/config.json`
- Modify: `.gitignore`

- [ ] **Step 1: 빈 docker config 작성 (credential helper 우회)**

`.docker-anon/config.json`:
```json
{}
```

- [ ] **Step 2: .gitignore에 추가 항목 반영**

기존 `.gitignore` 끝에 다음 줄을 덧붙인다:
```
sbom/
.docker-anon/
*.tar
```

- [ ] **Step 3: Dockerfile.naive 작성 (의도적으로 무거운 before)**

`Dockerfile.naive`:
```dockerfile
# 비교 기준점: 표준 golang 베이스를 그대로 런타임에 사용 (멀티스테이지 X)
FROM golang:1.26
WORKDIR /src
COPY app/ ./
RUN go build -o /usr/local/bin/hello .
EXPOSE 8080
CMD ["hello"]
```

- [ ] **Step 4: Makefile 작성 (공통 변수 + naive 타겟)**

`Makefile`:
```makefile
# 모든 docker 호출에 빈 config를 써서 cgr.dev credential helper를 우회한다.
export DOCKER_CONFIG := $(CURDIR)/.docker-anon

ARCH       := aarch64
MELANGE    := cgr.dev/chainguard/melange:latest
APKO       := cgr.dev/chainguard/apko:latest
NAIVE_IMG  := harden:naive
WOLFI_IMG  := harden:wolfi
REG        := localhost:5000
REG_NAME   := harden-registry

.PHONY: naive
naive:
	docker build -f Dockerfile.naive -t $(NAIVE_IMG) .
	@echo "built $(NAIVE_IMG)"
```

- [ ] **Step 5: naive 이미지 빌드 및 동작 확인**

Run:
```bash
make naive
docker run -d --rm -p 8081:8080 --name naive-test harden:naive
sleep 1
curl -s localhost:8081/
docker stop naive-test
```
Expected: `make naive` 성공, curl 응답 `hello, hardened`

- [ ] **Step 6: 커밋**

```bash
git add Dockerfile.naive Makefile .docker-anon/config.json .gitignore
git commit -m "feat: 비교용 naive golang 이미지 + Makefile 기초"
```

---

### Task 3: melange로 apk 패키지 빌드

**Files:**
- Create: `melange.yaml`
- Modify: `Makefile`

- [ ] **Step 1: melange.yaml 작성**

`melange.yaml`:
```yaml
package:
  name: hello
  version: 1.0.0
  epoch: 0
  description: "minimal hardened go http server"
  copyright:
    - license: Apache-2.0

environment:
  contents:
    keyring:
      - https://packages.wolfi.dev/os/wolfi-signing.rsa.pub
    repositories:
      - https://packages.wolfi.dev/os
    packages:
      - busybox
      - ca-certificates-bundle
      - go

pipeline:
  - uses: go/build
    with:
      modroot: app
      packages: .
      output: hello
```

- [ ] **Step 2: Makefile에 keygen + pkg 타겟 추가**

`Makefile` 끝에 추가:
```makefile
keys/melange.rsa:
	mkdir -p keys
	docker run --rm -v "$(CURDIR)":/work -w /work $(MELANGE) keygen keys/melange.rsa

.PHONY: pkg
pkg: keys/melange.rsa
	docker run --rm --privileged -v "$(CURDIR)":/work -w /work $(MELANGE) \
		build melange.yaml --arch $(ARCH) --signing-key keys/melange.rsa
	@echo "built package:"; ls packages/$(ARCH)/*.apk
```

- [ ] **Step 3: 패키지 빌드 실행**

Run: `make pkg`
Expected: `packages/aarch64/hello-1.0.0-r0.apk` 생성, `keys/melange.rsa` 및 `keys/melange.rsa.pub` 생성. 마지막 줄에 apk 경로 출력.

- [ ] **Step 4: 패키지 내용 확인 (바이너리가 /usr/bin/hello에 있는지)**

Run:
```bash
tar -tzf packages/aarch64/hello-1.0.0-r0.apk 2>/dev/null | grep usr/bin/hello
```
Expected: `usr/bin/hello` 라인 출력

- [ ] **Step 5: 커밋**

```bash
git add melange.yaml Makefile
git commit -m "feat: melange로 hello apk 패키지 빌드"
```

---

### Task 4: apko로 하드닝 이미지 조립

**Files:**
- Create: `apko.yaml`
- Modify: `Makefile`

- [ ] **Step 1: apko.yaml 작성**

`apko.yaml`:
```yaml
contents:
  keyring:
    - https://packages.wolfi.dev/os/wolfi-signing.rsa.pub
    - keys/melange.rsa.pub
  repositories:
    - https://packages.wolfi.dev/os
    - '@local /work/packages'
  packages:
    - ca-certificates-bundle
    - hello@local

accounts:
  groups:
    - groupname: nonroot
      gid: 65532
  users:
    - username: nonroot
      uid: 65532
      gid: 65532
  run-as: 65532

entrypoint:
  command: /usr/bin/hello

archs:
  - aarch64
```

- [ ] **Step 2: Makefile에 image 타겟 추가**

`Makefile` 끝에 추가:
```makefile
.PHONY: image
image: pkg
	mkdir -p sbom
	docker run --rm -v "$(CURDIR)":/work -w /work $(APKO) \
		build apko.yaml $(WOLFI_IMG) /work/harden-wolfi.tar \
		--arch $(ARCH) --sbom-path /work/sbom
	@LOADED=$$(docker load -i harden-wolfi.tar | sed -n 's/.*Loaded image: //p'); \
		docker tag $$LOADED $(WOLFI_IMG); \
		echo "tagged $$LOADED as $(WOLFI_IMG)"
```

- [ ] **Step 3: 이미지 빌드 + 로드**

Run: `make image`
Expected: `harden-wolfi.tar` 생성, `sbom/` 아래 `sbom-aarch64.spdx.json` 류 파일 생성, 마지막 줄 `tagged ... as harden:wolfi`

- [ ] **Step 4: 이미지가 실제 동작하는지 확인**

Run:
```bash
docker run -d --rm -p 8082:8080 --name wolfi-test harden:wolfi
sleep 1
curl -s localhost:8082/
docker stop wolfi-test
```
Expected: curl 응답 `hello, hardened`

- [ ] **Step 5: 셸이 없음을 확인 (하드닝 증거)**

Run: `docker run --rm --entrypoint /bin/sh harden:wolfi -c "echo hi"`
Expected: 실패 — `/bin/sh` 없음 (셸·패키지매니저 미포함 = 공격 표면 최소)

- [ ] **Step 6: 커밋**

```bash
git add apko.yaml Makefile
git commit -m "feat: apko로 non-root 하드닝 이미지 조립"
```

---

### Task 5: 로컬 레지스트리 + cosign 서명

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Makefile에 registry + sign 타겟 추가**

`Makefile` 끝에 추가:
```makefile
.PHONY: registry
registry:
	@docker inspect $(REG_NAME) >/dev/null 2>&1 || \
		docker run -d -p 5000:5000 --restart=always --name $(REG_NAME) registry:2
	@echo "registry up at $(REG)"

keys/cosign.key:
	mkdir -p keys
	cd keys && COSIGN_PASSWORD="" cosign generate-key-pair

.PHONY: sign
sign: image registry keys/cosign.key
	docker tag $(WOLFI_IMG) $(REG)/harden:wolfi
	docker push $(REG)/harden:wolfi
	@DIGEST=$$(docker inspect --format='{{index .RepoDigests 0}}' $(REG)/harden:wolfi); \
		echo "signing $$DIGEST"; \
		COSIGN_PASSWORD="" cosign sign --yes --key keys/cosign.key \
			--allow-insecure-registry $$DIGEST
```

주의: `cosign generate-key-pair`는 cwd에 `cosign.key`/`cosign.pub`를 만들므로 `cd keys`로 들어가 실행한다 → `keys/cosign.key`, `keys/cosign.pub`.

- [ ] **Step 2: 서명 실행**

Run: `make sign`
Expected: registry 컨테이너 기동, 이미지 push, `keys/cosign.key`/`keys/cosign.pub` 생성, `cosign sign` 성공 (`Pushing signature to: localhost:5000/harden`).

- [ ] **Step 3: 서명이 레지스트리에 올라갔는지 확인**

Run:
```bash
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' localhost:5000/harden:wolfi)
cosign verify --key keys/cosign.pub --allow-insecure-registry "$DIGEST" 2>&1 | head -3
```
Expected: `Verification for ...harden... --` + `The cosign claims were validated`

- [ ] **Step 4: 커밋**

```bash
git add Makefile
git commit -m "feat: 로컬 레지스트리 push + cosign 서명"
```

---

### Task 6: 취약점 스캔 + before/after 비교

**Files:**
- Create: `scripts/compare.sh`
- Modify: `Makefile`

- [ ] **Step 1: compare.sh 작성**

`scripts/compare.sh`:
```bash
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
```

- [ ] **Step 2: 실행 권한 부여**

Run: `chmod +x scripts/compare.sh`

- [ ] **Step 3: Makefile에 scan + compare 타겟 추가**

`Makefile` 끝에 추가:
```makefile
.PHONY: scan
scan: naive image
	@echo "=== trivy: $(NAIVE_IMG) ==="; trivy image -q --severity HIGH,CRITICAL $(NAIVE_IMG) || true
	@echo "=== trivy: $(WOLFI_IMG) ==="; trivy image -q --severity HIGH,CRITICAL $(WOLFI_IMG) || true
	@echo "=== grype: $(WOLFI_IMG) ==="; grype $(WOLFI_IMG) || true

.PHONY: compare
compare: naive image
	./scripts/compare.sh
```

- [ ] **Step 4: 비교 실행**

Run: `make compare`
Expected: 표 출력. `harden:naive`는 수백 MB·HIGH+CRIT CVE 다수, `harden:wolfi`는 ~10MB대·CVE 0 또는 소수.

- [ ] **Step 5: 커밋**

```bash
git add scripts/compare.sh Makefile
git commit -m "feat: trivy/grype 스캔 + before/after 비교 표"
```

---

### Task 7: 서명/SBOM 검증 스크립트

**Files:**
- Create: `scripts/verify.sh`
- Modify: `Makefile`

- [ ] **Step 1: verify.sh 작성**

`scripts/verify.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

REG=localhost:5000

echo "== cosign verify =="
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$REG/harden:wolfi")
cosign verify --key keys/cosign.pub --allow-insecure-registry "$DIGEST"

echo
echo "== SBOM 패키지 목록 (apko 생성) =="
SBOM=$(ls sbom/*.spdx.json | head -1)
echo "file: $SBOM"
python3 -c "import sys,json; d=json.load(open('$SBOM')); [print(' -', p.get('name'), p.get('versionInfo','')) for p in d.get('packages',[])]"
```

- [ ] **Step 2: 실행 권한 부여**

Run: `chmod +x scripts/verify.sh`

- [ ] **Step 3: Makefile에 verify 타겟 추가**

`Makefile` 끝에 추가:
```makefile
.PHONY: verify
verify: sign
	./scripts/verify.sh
```

- [ ] **Step 4: 검증 실행**

Run: `make verify`
Expected: `The cosign claims were validated` 출력 + SBOM 패키지 목록에 `hello`, `ca-certificates-bundle` 등 우리가 선언한 패키지만 등장 (셸·컴파일러 없음).

- [ ] **Step 5: 커밋**

```bash
git add scripts/verify.sh Makefile
git commit -m "feat: cosign verify + SBOM 검증 스크립트"
```

---

### Task 8: 전체 파이프라인 타겟 + README

**Files:**
- Modify: `Makefile`
- Create: `README.md`

- [ ] **Step 1: Makefile에 all + clean 타겟 추가**

`Makefile` 끝에 추가:
```makefile
.PHONY: all
all: naive image sign scan compare verify

.PHONY: clean
clean:
	-docker rmi $(NAIVE_IMG) $(WOLFI_IMG) $(REG)/harden:wolfi 2>/dev/null
	-docker rm -f $(REG_NAME) 2>/dev/null
	-rm -rf packages sbom harden-wolfi.tar
	@echo "cleaned (keys/ 는 보존)"
```

- [ ] **Step 2: README.md 작성**

`README.md`:
````markdown
# image-harden — Wolfi/apko Go 이미지 하드닝 실습

Chainguard가 쓰는 **Wolfi + melange + apko** 방식을 직접 따라 하며,
일반 `golang` 이미지 대비 크기·취약점이 얼마나 줄어드는지 손으로 확인하는 학습 프로젝트.

## 개념 한 줄 요약
- **Wolfi**: 컨테이너 전용으로 새로 만든 리눅스(undistro). 군더더기 0, 매일 보안 패치.
- **melange**: 소스 → 서명된 `.apk` 패키지 빌더. 빌드 도구는 이 단계에만 존재.
- **apko**: Dockerfile 없이 선언한 패키지만 모아 최소 이미지로 조립. SBOM 자동.

## 사전 요구사항
Docker, Go 1.26, cosign, trivy, grype, syft. (melange/apko는 Docker로 실행하므로 설치 불필요)

> **참고:** `~/.docker/config.json`의 cgr.dev credential helper 때문에 익명 pull이 막히면,
> 이 프로젝트는 `.docker-anon/` 빈 config로 우회한다 (Makefile이 자동 처리).

## 빠른 시작
```bash
make all      # 전체: naive 빌드 → 패키지 → 이미지 → 서명 → 스캔 → 비교 → 검증
```

## 단계별 실행
| 명령 | 하는 일 |
|---|---|
| `make naive`   | 비교용 무거운 golang 이미지 빌드 |
| `make pkg`     | melange로 `hello.apk` 빌드 (`--privileged`) |
| `make image`   | apko로 non-root 하드닝 이미지 조립 + SBOM |
| `make sign`    | 로컬 레지스트리 push 후 cosign 서명 |
| `make scan`    | trivy/grype로 양쪽 취약점 스캔 |
| `make compare` | 크기 + HIGH/CRIT CVE 비교 표 |
| `make verify`  | cosign verify + SBOM 패키지 목록 확인 |
| `make clean`   | 산출물·컨테이너 정리 (keys 보존) |

## 무엇을 보게 되나
- `make compare`: naive(수백 MB·CVE 다수) vs wolfi(~10MB·CVE 0~소수)
- `make image` 후 `docker run --entrypoint /bin/sh harden:wolfi`: **셸이 없어 실패** = 공격 표면 최소
- `make verify`: 서명 검증 통과 + SBOM에 우리가 선언한 패키지만 존재

## 파일 안내
- `app/` — 최소 Go HTTP 서버
- `melange.yaml` — apk 패키지 빌드 정의
- `apko.yaml` — 이미지 조립 정의 (non-root, entrypoint, 셸 없음)
- `Dockerfile.naive` — 비교 기준점
````

- [ ] **Step 3: 전체 파이프라인 처음부터 재현**

Run:
```bash
make clean
make all
```
Expected: 모든 단계 통과. 최종 `make verify` 출력에 `The cosign claims were validated` + SBOM 목록.

- [ ] **Step 4: 커밋**

```bash
git add Makefile README.md
git commit -m "feat: 전체 파이프라인(all/clean) 타겟 + README 학습 가이드"
```

---

## Self-Review 결과

**Spec coverage:**
- spec §1 학습 흐름 → Task 2(naive) + Task 3~4(after) + Task 6(비교) ✓
- spec §2 개념(Wolfi/melange/apko) → README(Task 8) + 각 yaml 주석 ✓
- spec §3 디렉토리 구조 → File Structure 및 각 Task의 파일 경로 ✓
- spec §4 컴포넌트 동작(melange/apko/naive/Makefile) → Task 1~5 ✓
- spec §5 실행 디테일(arm64, --privileged, 로컬 registry, 로컬 키) → 환경 전제 + Task 3/5 ✓
- spec §5 credential helper 함정 → Task 2 Step 1(.docker-anon) ✓
- spec §6 검증(curl 동작, 비교 표, cosign verify, SBOM) → Task 4/6/7 ✓
- spec §7 YAGNI(멀티아키·keyless·CI 제외) → 단일 aarch64, 로컬 키 기반 유지 ✓

**Placeholder scan:** TBD/TODO/"적절히 처리" 없음. 모든 코드·명령·기대 출력 명시. ✓

**Type/이름 일관성:** `rootHandler`(Task1), 이미지 태그 `harden:naive`/`harden:wolfi`(Task2,4,6), 키 경로 `keys/melange.rsa`·`keys/cosign.key`(Task3,5), 패키지명 `hello`(melange/apko/SBOM) 전 Task 일치. ✓
