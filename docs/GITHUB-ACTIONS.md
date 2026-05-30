# GitHub Actions로 이미지 하드닝 자동화 — 메커니즘 & 설정

이 레포의 go/python/java 하드닝을 **커밋마다 자동 빌드·서명·push**하고, **매일 재빌드로 CVE 0을 유지**한다.

---

## 1. 메커니즘 (CI 한 사이클에 일어나는 일)

```
checkout ─► melange(.apk) ─► apko(이미지+SBOM) ─► trivy 게이트 ─► GHCR push ─► cosign keyless 서명 ─► SBOM attest ─► verify
                                                     │
                                            HIGH/CRIT 있으면 여기서 실패 (push 안 됨)
```

| 단계 | 도구 | 핵심 |
|---|---|---|
| ① 패키지화 | `melange build` | 소스 → 서명된 `.apk`. 빌드 도구(JDK·pip·컴파일러)는 이 단계에만 존재 |
| ② 이미지화 | `apko build` | 선언한 패키지만 조립 → OCI tar + SBOM. Dockerfile·셸 없음 |
| ③ CVE 게이트 | `trivy --input` | HIGH/CRITICAL 발견 시 `exit 1` → 워크플로 실패 → **push 차단** |
| ④ push | `skopeo copy docker-archive:` | apko tar를 GHCR로. digest 확보 |
| ⑤ 서명 | `cosign sign` (keyless) | 보관 키 없이 **워크플로 신원(OIDC)**으로 서명, Rekor 기록 |
| ⑥ SBOM | `cosign attest` | 이미지에 SBOM attestation 첨부 |

**왜 keyless인가**: `id-token: write` 권한으로 GitHub이 발급하는 OIDC 토큰 → Fulcio가 "이 워크플로가 서명함"을 증명하는 10분짜리 임시 인증서 발급 → 서명. **개인키를 레포 시크릿에 둘 필요가 없다.**

**왜 daily rebuild가 CVE 0의 핵심인가**: melange/apko는 매번 `packages.wolfi.dev`에서 *최신* 패키지를 받는다. 코드가 안 바뀌어도 매일 재빌드하면 어제 공개된 새 CVE의 패치가 자동 반영된다.

---

## 2. 워크플로 파일 3개

| 파일 | 트리거 | 역할 |
|---|---|---|
| `.github/workflows/build.yml` | `workflow_call` (재사용) | 실제 빌드·게이트·서명 로직 (go/python/java matrix) |
| `.github/workflows/harden.yml` | push(main) / tag(v*) | 변경 시 빌드 → `latest`(또는 `v1.2.3`) + sha 태그 |
| `.github/workflows/daily-rebuild.yml` | cron 매일 06:00 UTC | 전체 재빌드 → `latest` 갱신 + `nightly-YYYYMMDD` 보존 |

`harden.yml`/`daily-rebuild.yml`은 둘 다 `build.yml`을 호출만 한다(로직 1곳, DRY).

---

## 3. 설정 (이대로만 하면 동작)

### 3.1 권한 — 이미 워크플로에 박혀 있음
```yaml
permissions:
  contents: read
  packages: write     # GHCR push
  id-token: write     # keyless 서명 (이게 없으면 cosign sign 실패)
```

### 3.2 GHCR — 추가 시크릿 불필요
- push 인증은 자동 제공되는 `secrets.GITHUB_TOKEN` 사용 (별도 PAT 안 만들어도 됨).
- 첫 push 후 패키지가 **private**으로 생김. 조직 정책에 맞게 visibility 조정:
  Repo → Packages → 해당 패키지 → Package settings → visibility / linked repo.

### 3.3 이미지 이름
`ghcr.io/<owner>/<repo>-<app>` 형태로 자동 생성됨 (예: `ghcr.io/acme/hardened-images-java`).
별도 치환 없이 `${GITHUB_REPOSITORY}` 기반으로 소문자화되어 들어간다.

### 3.4 빌드 아키텍처
CI는 `x86_64`(`--arch x86_64`)로 빌드 — GitHub 러너가 x86_64라 네이티브. (로컬은 arm64라 `--arch aarch64`; apko/melange 설정에서 `archs`를 빼 두어 `--arch` 플래그로 제어됨.)

### 3.5 끝. 커밋하면 동작
```bash
git add .github/workflows
git commit -m "ci: 하드닝 자동화 (build/harden/daily-rebuild)"
git push
# Actions 탭에서 harden 워크플로 실행 확인
```

---

## 4. 배포측 검증 (선택, 권장)

이미지를 쓰는 쪽에서 **우리 워크플로가 서명한 것만** 신뢰:
```bash
cosign verify ghcr.io/<owner>/<repo>-go@<digest> \
  --certificate-identity-regexp "^https://github.com/<owner>/<repo>/.github/workflows/" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```
Kubernetes에서 이걸 **강제**(서명 없으면 Pod 거부)하려면 Kyverno/policy-controller 정책으로 위 신원을 검사한다. (구성은 `docs/LOCAL-CHAINGUARD.md` §5 참고)

---

## 5. 자주 막히는 곳

| 증상 | 원인 / 해결 |
|---|---|
| `cosign sign` 권한 오류 | `id-token: write` 누락. 재사용 워크플로 호출 job에도 permissions 명시 필요 |
| GHCR push 403 | `packages: write` 누락 또는 패키지가 다른 레포에 linked |
| melange 빌드 실패(샌드박스) | `docker run`에 `--privileged` 필요 (build.yml에 이미 포함) |
| trivy 게이트가 항상 실패 | 정상일 수 있음 — 실제 HIGH/CRIT 존재. `ignore-unfixed`/severity 정책 조정 |
| SBOM attest 파일 없음 | apko `--sbom-path`의 `sbom-x86_64.spdx.json` 경로/아키텍처 확인 |
