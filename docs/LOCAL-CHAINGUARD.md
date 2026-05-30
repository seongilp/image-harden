# 사내 "로컬 Chainguard" 구축 기술 문서

> 목표: Chainguard가 SaaS로 제공하는 것 — **작고(minimal) · CVE 0 · 서명됨 · SBOM 포함**인 컨테이너 이미지를
> **조직 내부에서 직접 생산·유지·강제**하는 자체 하드닝 이미지 공장(internal image factory)을 세운다.
>
> 이 문서는 "어떻게 구성하는가"에 집중한 아키텍처/구성 가이드다. (실행·테스트는 별도)

---

## 0. Chainguard가 실제로 하는 일 (우리가 복제할 대상)

| Chainguard 기능 | 내부 메커니즘 | 우리가 세울 것 |
|---|---|---|
| 최소 이미지 | apko (Dockerfile 없이 패키지만 조립) | apko 빌드 파이프라인 |
| CVE 0 유지 | **매일 재빌드** + Wolfi 보안 패치 | daily rebuild 스케줄러 |
| 안전한 패키지 | Wolfi(undistro) + melange 빌드 | Wolfi 소비 + 사내 melange 패키지 |
| 변조 방지 | cosign 서명 + Rekor 투명성 로그 | keyless 서명 인프라 |
| 추적성 | SBOM + provenance attestation | SBOM 생성·첨부·보관 |
| 배포 강제 | (고객이 admission control) | Kyverno/policy-controller |

핵심 통찰: **"한 번 잘 빌드"가 아니라 "매일 다시 빌드"가 CVE 0의 비결이다.** 코드가 안 바뀌어도 베이스 패키지의 보안 패치를 매일 흡수해야 한다.

---

## 1. 전체 아키텍처

```
┌─────────────────────────────────────────────────────────────────────┐
│  (A) 정의 레포 (Git monorepo)                                          │
│      apps/<svc>/{melange.yaml, apko.yaml}  +  공용 base 정의           │
└───────────────┬─────────────────────────────────────────────────────┘
                │ push / tag / 매일 cron
                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  (B) 빌드 공장 (CI: GitHub Actions)                                    │
│   melange → .apk ──► (C) 사내 APK 저장소(선택) ──► apko → OCI 이미지     │
│                                          │                            │
│                          trivy/grype 게이트 (HIGH/CRIT=0 아니면 실패)   │
└───────────────┬─────────────────────────────────────────────────────┘
                │ 통과 시에만
                ▼
┌──────────────────────────┐   ┌──────────────────────────────────────┐
│  (D) 컨테이너 레지스트리   │   │  (E) 공급망 메타데이터                  │
│      GHCR / Harbor       │◄──│   cosign 서명(keyless) + SBOM attest    │
│      :latest :nightly-*  │   │   Fulcio(인증서) + Rekor(투명성 로그)    │
└───────────────┬──────────┘   └──────────────────────────────────────┘
                │ kubectl apply
                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  (F) 런타임 강제 (Kubernetes admission)                                │
│      Kyverno / sigstore policy-controller                            │
│      서명 검증 실패 = Pod 생성 거부                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 구성요소 요약
- **(A) 정의 레포**: 이미지의 "레시피"만 모은 monorepo. 앱 소스와 분리하거나, 앱 레포에 동거.
- **(B) 빌드 공장**: melange로 패키지화 → apko로 이미지화. CVE 게이트 내장.
- **(C) 사내 APK 저장소(선택)**: 자체 melange 패키지를 호스팅하는 사설 Wolfi-호환 저장소. 처음엔 생략 가능(`@local`).
- **(D) 레지스트리**: 결과 이미지 보관. GHCR로 시작.
- **(E) 공급망 메타데이터**: 서명·SBOM·provenance. 공개 sigstore 또는 사내 sigstore.
- **(F) 런타임 강제**: 서명 안 된/우리 신원 아닌 이미지는 클러스터에서 거부.

---

## 2. 레포 구조 (정의 monorepo)

많은 Python·Java 앱을 다루므로 **재사용 + 일관성**이 핵심. 권장 구조:

```
hardened-images/                      # 정의 monorepo
├── apps/
│   ├── billing-api/      (java)  melange.yaml  apko.yaml
│   ├── auth-svc/         (python) melange.yaml apko.yaml
│   └── gateway/          (go)    melange.yaml  apko.yaml
├── lib/
│   ├── base/             # 공용 apko 베이스(런타임 공통: ca-certs, tz 등)
│   ├── runtime-java.yaml # JRE21 런타임 프로파일 (앱들이 상속/참조)
│   └── runtime-python.yaml
├── .github/workflows/
│   ├── build.yml         # 재사용 워크플로 (1개 앱 빌드·서명·스캔·push)
│   ├── harden.yml        # push/tag → 변경된 앱만 빌드
│   └── daily-rebuild.yml # cron → 전체 재빌드
├── deploy/
│   ├── policy/           # Kyverno / policy-controller
│   └── k8s/              # 예시 매니페스트
└── scripts/              # 헬퍼 (matrix 생성, 버전 범프)
```

**언어 프로파일 표준화**: 모든 Java 앱은 동일한 `runtime-java`(openjdk-21-jre, JAVA_HOME, non-root) 패턴을, 모든 Python 앱은 동일한 `runtime-python`(python-3.13, pip vendoring) 패턴을 따른다. 앱마다 melange/apko를 처음부터 쓰지 말고 **템플릿에서 생성**(scripts/scaffold)하라.

---

## 3. Layer B — 빌드 공장 상세

### 3.1 빌드 2단계 (불변)
1. **melange**: 소스 → 서명된 `.apk`. 빌드 도구(JDK/Gradle/pip/컴파일러)는 *이 단계에만* 존재.
2. **apko**: 선언한 패키지만 조립 → 이미지. `RUN`/셸/패키지매니저 없음.

> 분리 원칙: **빌드 타임 의존성이 런타임 이미지에 절대 새지 않는다.** 이것이 CVE 표면을 0으로 만드는 구조적 이유.

### 3.2 언어별 melange 패턴 (검증됨)

**Go** — `go/build` 내장 파이프라인, 정적 바이너리:
```yaml
pipeline:
  - uses: go/build
    with: { modroot: app-go, packages: ., output: app }
```

**Python** — pip 의존성을 패키지에 vendoring:
```yaml
environment:
  contents:
    packages: [busybox, python-3.13, py3.13-pip]
pipeline:
  - runs: |
      SP="${{targets.destdir}}/usr/lib/python3.13/site-packages"
      mkdir -p "$SP" "${{targets.destdir}}/usr/bin"
      python3.13 -m pip install --no-cache-dir --target="$SP" -r requirements.txt
      install -m644 main.py "${{targets.destdir}}/usr/bin/app"
```

**Java** — 빌드는 JDK+Gradle, 런타임은 JRE만:
```yaml
environment:
  contents:
    packages: [busybox, openjdk-21-default-jdk, gradle-9]
pipeline:
  - runs: |
      gradle --no-daemon jar
      mkdir -p "${{targets.destdir}}/usr/share/app"
      install -m644 build/libs/app.jar "${{targets.destdir}}/usr/share/app/app.jar"
```

### 3.3 언어별 apko 패턴 (런타임 최소화)
- **공통**: non-root(uid 65532), entrypoint 명시, 선언 패키지 최소.
- **Java 주의**: Wolfi `openjdk-21-jre`는 `java`를 `/usr/bin`에 심볼릭하지 않음 → entrypoint에 `/usr/lib/jvm/java-21-openjdk/bin/java` 전체 경로 + `JAVA_HOME`/`PATH` env 지정.

### 3.4 CVE 게이트
빌드 직후 push 전에 차단:
```bash
trivy image --input image.tar --severity HIGH,CRITICAL --exit-code 1 --ignore-unfixed
# exit 1 = 빌드 실패 → push 안 됨
```
- `--ignore-unfixed`: 패치 없는 취약점은 게이트에서 제외(정책에 따라 조정).
- grype를 2차 스캐너로 병행해 오탐/누락 교차검증 권장.

### 3.5 이미지 push 메커니즘 (검증됨)
apko는 OCI tar를 만든다. CI에서 레지스트리로:
```bash
skopeo copy docker-archive:image.tar docker://ghcr.io/<org>/<svc>:<tag> \
  --dest-creds "$USER:$TOKEN"
DIGEST=$(skopeo inspect docker://ghcr.io/<org>/<svc>:<tag> --format '{{.Digest}}' --creds "$USER:$TOKEN")
```
(대안: apko `publish`로 빌드+push 일괄. 게이트를 push 전에 두려면 build→scan→copy 순서가 명확.)

---

## 4. Layer E — 서명·SBOM 공급망

### 4.1 key-based vs keyless (둘 다 가능, CI는 keyless 권장)

| | key-based | **keyless (권장)** |
|---|---|---|
| 키 관리 | 개인키 보관·교체 부담 | 보관 키 없음(10분 임시 인증서) |
| 신뢰 근거 | 공개키 파일 | **워크플로 신원(OIDC)** + Rekor |
| CI 적합성 | 시크릿 필요 | GitHub OIDC로 무인 자동 |

### 4.2 keyless 서명 체인 (CI에서)
```bash
# GitHub Actions: permissions: id-token: write 필요
cosign sign --yes ghcr.io/<org>/<svc>@${DIGEST}
cosign attest --yes --type spdxjson \
  --predicate sbom/sbom-x86_64.spdx.json ghcr.io/<org>/<svc>@${DIGEST}
```
- `cosign sign`: Fulcio가 워크플로 신원에 묶인 임시 인증서 발급 → 서명 → Rekor에 기록.
- `cosign attest`: apko가 만든 SBOM을 이미지에 attestation으로 첨부.

### 4.3 검증 (어디서나)
```bash
cosign verify ghcr.io/<org>/<svc>@${DIGEST} \
  --certificate-identity-regexp "^https://github.com/<org>/hardened-images/" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

### 4.4 공개 vs 사내 sigstore
- **시작**: 공개 sigstore(Fulcio/Rekor `*.sigstore.dev`) 사용 — 무료, 설정 최소.
- **격리/규제 환경**: 자체 호스팅 — `fulcio`, `rekor`, `timestamp-authority`를 사내 배포하고 cosign에 `--fulcio-url`/`--rekor-url`/TUF 루트 지정. (운영 부담 ↑, 외부 의존 0)

---

## 5. Layer F — 런타임 강제 (K8s admission)

서명만 하고 강제하지 않으면 의미가 절반. **서명 검증 실패 = Pod 거부**를 클러스터에 건다.

### 5.1 Kyverno (권장, 가독성↑)
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: require-hardened-signatures }
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-keyless
      match: { any: [{ resources: { kinds: [Pod] } }] }
      verifyImages:
        - imageReferences: ["ghcr.io/<org>/*"]
          attestors:
            - entries:
                - keyless:
                    subject: "https://github.com/<org>/hardened-images/.github/workflows/*"
                    issuer: "https://token.actions.githubusercontent.com"
                    rekor: { url: "https://rekor.sigstore.dev" }
```
→ 우리 GitHub Actions 워크플로 신원으로 서명된 이미지만 실행 허용. 그 외 전부 거부.

### 5.2 sigstore policy-controller (sigstore 네이티브, 대안)
```yaml
apiVersion: policy.sigstore.dev/v1beta1
kind: ClusterImagePolicy
metadata: { name: hardened-images }
spec:
  images: [{ glob: "ghcr.io/<org>/**" }]
  authorities:
    - keyless:
        identities:
          - issuer: "https://token.actions.githubusercontent.com"
            subjectRegExp: "https://github.com/<org>/hardened-images/.github/workflows/.+"
```

### 5.3 추가 런타임 하드닝 (PodSecurity)
이미지가 작아도 런타임 설정으로 마무리:
```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities: { drop: [ALL] }
  seccompProfile: { type: RuntimeDefault }
```

---

## 6. Daily Rebuild — CVE 0의 진짜 비결

코드가 안 바뀌어도 **매일 전체 재빌드**한다. melange/apko가 `packages.wolfi.dev`(또는 사내 미러)에서 *최신* 패키지를 받으므로, 어제 0이던 CVE가 오늘 새로 공개돼도 **패치된 패키지로 자동 교체**된다.

```yaml
# .github/workflows/daily-rebuild.yml (개념)
on:
  schedule: [{ cron: "0 6 * * *" }]   # 매일 06:00 UTC
jobs:
  build:
    uses: ./.github/workflows/build.yml
    with: { tag: latest, extra_tag: "nightly-<date>" }   # latest 갱신 + 날짜 태그 보존
```
- 재빌드 후에도 **CVE 게이트를 다시 통과**해야 push. 통과 못 하면 알림 → 사람 개입.
- 태그 전략: `latest`(항상 최신 안전본) + `nightly-YYYYMMDD`(롤백용) + 릴리스 태그(`v1.2.3`, 불변).

---

## 7. Wolfi와의 관계: 소비 vs 미러 vs 포크

| 단계 | 방식 | 언제 |
|---|---|---|
| 시작 | `packages.wolfi.dev` 직접 소비 | 대부분의 조직 |
| 격리 | 사내 **미러**(매일 동기화) | 외부망 차단/안정성 필요 |
| 확장 | 사내 melange 패키지 + 자체 APKINDEX 호스팅 | upstream에 없는 사내 라이브러리 |
| 최대 | wolfi-os 포크 + 자체 빌드 클러스터 | 규제·완전 통제 |

**사내 APK 저장소(Layer C)** 운영 시: melange 산출 `.apk`+`APKINDEX.tar.gz`를 사설 키로 서명하고 S3/OCI/정적호스팅에 게시 → apko `repositories`에 사내 URL과 사내 공개키 추가. (처음엔 `@local`로 충분, 여러 앱이 공용 패키지를 공유할 때 도입.)

---

## 8. 단계별 구축 로드맵

| Phase | 산출물 | 검증 기준 |
|---|---|---|
| **1. 한 앱 PoC** | go/python/java 각 1개를 melange+apko로 하드닝, 로컬 비교 | 크기↓·CVE 0·셸 없음 (이 레포에서 완료) |
| **2. CI 자동화** | build.yml/harden.yml, GHCR push, CVE 게이트 | 커밋 시 자동 빌드·게이트·push |
| **3. 서명·SBOM** | keyless 서명 + SBOM attest + verify | `cosign verify` 통과 |
| **4. Daily rebuild** | cron 재빌드 + nightly 태그 | 매일 자동, 게이트 실패 시 알림 |
| **5. Admission 강제** | Kyverno 정책 적용 | 미서명 이미지 Pod 거부 확인 |
| **6. 스케일** | 정의 monorepo + 템플릿 + 미러/사내 저장소 | N개 앱을 일관 패턴으로 양산 |

---

## 9. 위협 모델 — 각 레이어가 막는 것

| 위협 | 방어 레이어 |
|---|---|
| 비대한 베이스의 알려진 CVE | apko 최소 이미지 (B) |
| 시간이 지나며 누적되는 CVE | daily rebuild (6) |
| 빌드 도구·셸을 통한 공격 | melange/apko 분리, 셸 없음 (B) |
| 레지스트리 이미지 변조 | cosign 서명 + digest 고정 (E) |
| 출처 불명 이미지 배포 | admission 신원 검증 (F) |
| 의존성 추적 불가 | SBOM attestation (E) |
| 빌드 파이프라인 위조 | keyless 워크플로 신원 (E/F) |

---

## 10. 운영 체크리스트

**구축 시 1회**
- [ ] GHCR: 패키지 쓰기 권한, 조직 visibility 설정
- [ ] GitHub Actions: `id-token: write`, `packages: write` 권한
- [ ] `<org>` / 레포명 / 워크플로 신원 정규식 확정 (정책에 박힘)
- [ ] Kyverno(또는 policy-controller) 설치 + 정책 적용
- [ ] (선택) 사내 sigstore / Wolfi 미러 / 사내 APK 저장소

**상시 운영**
- [ ] daily rebuild 게이트 실패 알림 채널 (Slack 등)
- [ ] CVE 대응 SLA 정의 (예: CRITICAL 24h 내 재빌드·배포)
- [ ] 스캐너 2종(trivy+grype) 정기 교차검증
- [ ] 정의 monorepo PR 리뷰 게이트 (이미지 정의 변경 통제)
- [ ] 릴리스 태그 불변성 + nightly 보존기간 정책

---

## 부록 — 이 레포가 제공하는 검증된 기반

이 monorepo에는 Phase 1이 **실제 동작·검증**된 상태로 들어있다:
- `app-{go,python,java}/`, `melange-*.yaml`, `apko-*.yaml`, `Makefile`(APP 파라미터화)
- 실측: go 8.94MB/0CVE, python 95.8MB/0CVE, java 299MB/0CVE (naive 대비 최대 158×↓)
- `scripts/compare-all.sh`, `verify.sh`, key-based 서명·SBOM 검증까지

Phase 2~5의 참조 템플릿은 `.github/workflows/`, `deploy/`에 둔다(아래 파일들). 환경(`<org>` 등)에 맞춰 치환해 사용.
