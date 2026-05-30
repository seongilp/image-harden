# image-harden — Wolfi/apko Go 이미지 하드닝 실습

Chainguard가 쓰는 **Wolfi + melange + apko** 방식을 직접 따라 하며,
일반 `golang` 이미지 대비 크기·취약점이 얼마나 줄어드는지 손으로 확인하는 학습 프로젝트.

## 실측 결과 (이 저장소 기준)

| IMAGE | SIZE | HIGH+CRIT CVE |
|---|---|---|
| `harden:naive` (일반 golang) | **1.41 GB** | **85** |
| `harden:wolfi` (Wolfi/apko) | **8.94 MB** | **0** |

→ **약 158배 작고, HIGH/CRITICAL CVE 85개 → 0개.**

## 개념 한 줄 요약
- **Wolfi**: 컨테이너 전용으로 새로 만든 리눅스(undistro). 군더더기 0, 매일 보안 패치, 커널 없음.
- **melange**: 소스 → 서명된 `.apk` 패키지 빌더. 빌드 도구(Go 컴파일러)는 이 단계에만 존재.
- **apko**: Dockerfile 없이 선언한 패키지만 모아 최소 이미지로 조립. SBOM 자동 생성.

## 사전 요구사항
Docker, Go 1.26, cosign, trivy, grype, syft. (melange/apko는 Docker로 실행하므로 별도 설치 불필요)

## 빠른 시작
```bash
make all      # 전체: naive 빌드 → 패키지 → 이미지 → 서명 → 스캔 → 비교 → 검증
```

## 단계별 실행
| 명령 | 하는 일 |
|---|---|
| `make naive`   | 비교용 무거운 golang 이미지 빌드 |
| `make pkg`     | melange로 `hello.apk` 빌드 (`--privileged` 필요) |
| `make image`   | apko로 non-root 하드닝 이미지 조립 + SBOM 생성 |
| `make sign`    | 로컬 레지스트리 push 후 cosign 서명 |
| `make scan`    | trivy/grype로 양쪽 취약점 스캔 |
| `make compare` | 크기 + HIGH/CRIT CVE 비교 표 |
| `make verify`  | cosign verify + SBOM 패키지 목록 확인 |
| `make clean`   | 산출물·컨테이너 정리 (keys 보존) |

## 무엇을 보게 되나
- `make compare`: naive(1.41GB·CVE 85) vs wolfi(8.94MB·CVE 0)
- 셸이 없어 공격 표면 최소 — 확인:
  ```bash
  docker run --rm --entrypoint /bin/sh harden:wolfi -c "echo hi"
  # → /bin/sh: no such file or directory  (정상: 셸 미포함)
  ```
- `make verify`: 서명 검증 통과 + SBOM에 우리가 선언한 패키지(`hello`, `ca-certificates-bundle`, `wolfi-baselayout`)만 존재.

## 환경 메모 (이 머신에서 겪은 함정)
- **cgr.dev credential helper**: `~/.docker/config.json`에 `docker-credential-cgr`가 설정만 되고 미설치 → 익명 pull 실패. 프로젝트 로컬 빈 config(`.docker-anon/`)로 우회한다(Makefile이 `DOCKER_CONFIG`로 자동 지정).
- **레지스트리 포트 5050**: macOS는 5000을 AirPlay(ControlCenter)가 점유하므로 5050 사용.
- **cosign 오프라인 서명**: 로컬 키 기반이라 sigstore 투명성 로그(tlog)를 쓰지 않는다. 서명은 `--use-signing-config=false --tlog-upload=false`, 검증은 `--insecure-ignore-tlog`로 진행.

## 파일 안내
- `app/` — 최소 Go HTTP 서버 (`/` → `hello, hardened`)
- `melange.yaml` — apk 패키지 빌드 정의
- `apko.yaml` — 이미지 조립 정의 (non-root uid 65532, entrypoint, 셸 없음)
- `Dockerfile.naive` — 비교 기준점
- `scripts/compare.sh` / `scripts/verify.sh` — 비교·검증 헬퍼
- `docs/superpowers/` — 설계 spec과 구현 계획
