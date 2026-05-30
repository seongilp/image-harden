# 설계: Wolfi/apko Go 이미지 하드닝 실습

**작성일:** 2026-05-30
**목표 형태:** Chainguard가 실제로 쓰는 Wolfi + apko + melange 방식을 직접 따라 만들며 원리를 학습·재현
**예제 워크로드:** Go 정적 바이너리 (최소 HTTP 서버)
**도구 실행:** apko/melange는 로컬 설치 없이 Chainguard 공식 Docker 이미지로 실행
**증명 범위:** 크기 + 취약점 스캔 비교 + cosign 서명 + SBOM 검증까지 (전체 supply-chain)

---

## 1. 목표 & 학습 흐름

"평범한 `golang` Dockerfile 이미지"와 "Wolfi/apko 하드닝 이미지"를 **둘 다 만들어 나란히 비교**한다.
손으로 melange → apko → cosign → scan 전 과정을 돌려보며 "왜 작고 왜 CVE가 없는지"를 눈으로 확인하는 것이 핵심.

```
[before] Dockerfile.naive ─ docker build ─→ harden:naive  (수백 MB, CVE 다수)
[after]  app + melange.yaml ─ melange ─→ hello.apk
                              ─ apko ─→ harden:wolfi      (~10MB, CVE 0)
                              ─ cosign 서명 + SBOM 검증
              둘을 trivy/grype로 스캔 → 비교 표 출력
```

## 2. 개념 정리 (학습 대상)

| 역할 | 도구 | 설명 |
|---|---|---|
| 컨테이너 전용 리눅스 (undistro) | **Wolfi** | 군더더기 0, 매일 보안 패치, glibc 기반, 커널 없음, 잘게 쪼갠 패키지 |
| 소스 → `.apk` 패키지 빌더 | **melange** | 격리 환경에서 빌드 + 서명. 빌드 도구는 이 단계에만 존재 |
| 패키지 → 이미지 조립기 | **apko** | Dockerfile/RUN 없이 선언한 패키지만 조립. SBOM 자동, 재현 가능, 멀티아키 |

> melange = 안전한 apk 패키지 빌더 / apko = 그 패키지들로 Dockerfile 없이 최소 이미지 조립.
> 이 둘이 Chainguard 이미지가 "작고 + CVE 없고 + 서명됨"인 비결.

## 3. 디렉토리 구조 (many small files 원칙)

```
image-harden/
├── app/
│   ├── main.go            # 최소 Go HTTP 서버 (/ → "hello, hardened")
│   └── go.mod
├── melange.yaml           # apk 패키지 빌드 정의
├── apko.yaml              # 이미지 조립 정의 (non-root, entrypoint)
├── Dockerfile.naive       # 비교용 "before" 이미지
├── Makefile               # 모든 단계를 make 타겟으로 (내부는 docker run)
├── scripts/
│   ├── compare.sh         # 두 이미지 크기 + 취약점 비교 표
│   └── verify.sh          # cosign verify + SBOM 확인
├── keys/                  # melange/cosign 키 (.gitignore)
└── README.md             # 단계별 설명서(학습 내러티브)
```

## 4. 핵심 컴포넌트별 동작

**app/main.go** — 외부 의존성 없는 표준 라이브러리만 사용하는 최소 HTTP 서버. `/` 요청에 `"hello, hardened"` 응답. 정적 바이너리로 컴파일.

**melange.yaml** — Go 소스를 `hello.apk`로 빌드. `go/build` 파이프라인 사용. 빌드 도구(Go 컴파일러)는 이 단계에만 존재하고 최종 이미지엔 따라가지 않음. melange가 생성한 키로 패키지 서명.

**apko.yaml** — `contents.packages`에 `hello` + 최소 런타임(`ca-certificates-bundle` 등)만 선언. `accounts`로 non-root 유저 지정, `entrypoint`로 바이너리 실행. 셸·패키지매니저 없음. SBOM 자동 생성.

**Dockerfile.naive** — 비교용 "before". 표준 `golang` 베이스 이미지를 그대로 사용해 빌드(멀티스테이지 없이 의도적으로 무겁게). before/after 대비를 명확히 하기 위함.

**Makefile 타겟:**
- `make naive` — 비교용 golang 이미지 빌드 (`harden:naive`)
- `make pkg` — melange로 apk 빌드 (`docker run --privileged cgr.dev/chainguard/melange`)
- `make image` — apko로 하드닝 이미지 빌드 (`cgr.dev/chainguard/apko` → `harden:wolfi`)
- `make sign` — cosign 서명 (로컬 `registry:2` 컨테이너에 push 후 digest 서명)
- `make scan` — trivy + grype로 양쪽 스캔
- `make compare` — 크기/CVE 비교 표 출력
- `make verify` — cosign verify + SBOM 확인
- `make all` — 전체 파이프라인
- `make clean` — 산출물/컨테이너 정리

## 5. 실행 환경 디테일 (현실적 gotcha)

- **arm64 Mac**: melange/apko에 `--arch aarch64` 지정해 호스트 아키텍처로 빌드.
- **melange는 `--privileged` 필요**: Docker 안에서 빌드 샌드박스(bubblewrap)를 생성하기 때문. apko는 불필요.
- **cosign 서명**: 레지스트리 없이 로컬 서명이 까다로워서, `registry:2` 컨테이너를 `localhost:5000`에 띄워 push → digest 서명 → verify. 실제 supply-chain 흐름과 동일해 학습에 유리.
- **서명 키**: 학습용이라 keyless(OIDC/Fulcio) 대신 **로컬 키 기반**(`cosign generate-key-pair`, `melange keygen`). `keys/`는 gitignore.
- **환경 확인됨**: Docker 29.5.2, Go 1.26.3, cosign, trivy, grype, syft 전부 로컬 보유. apko/melange만 Docker 이미지로 실행.

## 6. 검증 방법 (완료 기준)

- `make image` 후 `docker run` + `curl`로 앱이 실제 동작하는지 확인 (HTTP 200 + 기대 응답).
- `make compare` 출력에서 naive(수백 MB·CVE 다수) vs wolfi(~10MB·CVE 0/소수) 차이를 표로 확인.
- `make verify`로 cosign verify 성공 + SBOM에 우리 패키지만 들어있음을 확인.
- README의 단계를 따라 처음부터 재현 가능.

## 7. 범위 밖 (YAGNI)

- 멀티아키(amd64+arm64 동시) 빌드 — 호스트 아키텍처만.
- keyless(OIDC) 서명 — 로컬 키 기반으로 충분.
- CI 파이프라인 연동 — 로컬 학습이 목표.
- 실제 외부 레지스트리 push — 로컬 `registry:2`로 한정.
