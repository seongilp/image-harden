# image-harden — Wolfi/apko 멀티 워크로드 이미지 하드닝 실습

Chainguard가 쓰는 **Wolfi + melange + apko** 방식으로 Go·Python·Java 앱을 하드닝하고,
일반 베이스 이미지 대비 크기·취약점이 얼마나 줄어드는지 손으로 확인하는 학습 프로젝트.

## 실측 결과 (이 저장소 기준)

| 언어 | naive 크기 | naive CVE | wolfi 크기 | wolfi CVE |
|---|---|---|---|---|
| **Go** | 1.41 GB | 85 | **8.94 MB** | **0** |
| **Python** | 1.62 GB | 187 | **95.8 MB** | **0** |
| **Java** (JRE+jar) | 1.34 GB | 8 | **299 MB** | **0** |

→ 세 언어 모두 **HIGH/CRITICAL CVE 0**, 크기는 최대 158배까지 축소. 셸·패키지매니저·빌드도구 없음.

## 개념 한 줄 요약
- **Wolfi**: 컨테이너 전용 리눅스(undistro). 군더더기 0, 매일 보안 패치, 커널 없음.
- **melange**: 소스 → 서명된 `.apk` 패키지 빌더. 빌드 도구(컴파일러·JDK·pip)는 이 단계에만 존재.
- **apko**: Dockerfile 없이 선언한 패키지만 모아 최소 이미지로 조립. SBOM 자동 생성.

## 사전 요구사항
Docker, cosign, trivy, grype. (melange/apko/언어 툴체인은 Docker로 실행하므로 별도 설치 불필요)

## 빠른 시작
```bash
make all-go           # Go 전체 파이프라인
make all-python       # Python
make all-java         # Java
make compare-all      # 세 언어 before/after 한 표로
```

## 워크로드 파라미터화 (APP 변수)
모든 타겟은 `APP=go|python|java`로 동작한다. 언어별 파일: `app-<lang>/`, `melange-<lang>.yaml`, `apko-<lang>.yaml`, `Dockerfile.naive-<lang>`.

| 명령 | 하는 일 |
|---|---|
| `make APP=python naive`   | 비교용 무거운 베이스 이미지 |
| `make APP=python pkg`     | melange로 apk 빌드 (`--privileged`) |
| `make APP=python image`   | apko로 non-root 하드닝 이미지 + SBOM |
| `make APP=python sign`    | 로컬 레지스트리 push + cosign **key-based** 서명 |
| `make APP=python compare` | 크기 + CVE 비교 표 |
| `make APP=python verify`  | cosign verify + SBOM 목록 |
| `make APP=java all`       | 위 전체를 한 번에 |
| `make clean-all`          | 전 언어 산출물·레지스트리 정리 (keys 보존) |

## 언어별 하드닝 포인트
- **Go**: 정적 바이너리 하나 → `FROM scratch`급 최소(8.94MB). melange `go/build` 파이프라인.
- **Python**: 런타임에 인터프리터+의존성 필요 → melange가 `pip install --target`으로 의존성을 패키지에 vendoring, apko는 `python-3.13`만 포함.
- **Java**: 빌드는 JDK+Gradle(melange 단계에만), 런타임은 **JRE만**(apko `openjdk-21-jre`). jar는 `/usr/share/hello/app.jar`. (Wolfi JRE는 `java`를 PATH에 안 올리므로 entrypoint에 전체 경로 사용.)

## 서명: key-based vs keyless

| | key-based (`make sign`) | keyless (`make sign-keyless`) |
|---|---|---|
| 개인키 | 직접 생성·보관 (`keys/cosign.key`) | **없음** (10분 임시 인증서) |
| 신뢰 기준 | 공개키 파일 | **신원(OIDC)** + Rekor 투명성 로그 |
| 실행 | 비대화식, 오프라인 | 브라우저 OIDC 로그인 필요 |
| 적합 | 로컬·학습 | **CI/CD**(GitHub Actions 등), 실제 배포 |

**keyless 사용법** (인터랙티브):
```bash
make keyless-doctor                # 환경 점검 (~/.sigstore 권한 등)
# 필요 시: sudo chown -R $(whoami) ~/.sigstore
make sign-keyless APP=go           # 브라우저 OIDC 로그인 → 서명
make verify-keyless APP=go \
     IDENTITY=you@gmail.com ISSUER=https://accounts.google.com
```
> GitHub Actions에서는 사람 로그인 없이 **워크플로 신원**으로 자동 서명된다 — 이것이 Chainguard가 실제 배포 이미지에 쓰는 방식이다.

## 하드닝 증거
```bash
docker run --rm --entrypoint /bin/sh harden-go:wolfi -c "echo hi"
# → /bin/sh: no such file or directory   (정상: 셸 미포함 = 공격 표면 최소)
make APP=go verify    # 서명 검증 통과 + SBOM에 선언한 패키지만 존재
```

## 환경 메모 (이 머신에서 겪은 함정)
- **cgr.dev credential helper**: `docker-credential-cgr` 미설치 → 빈 config(`.docker-anon/`)로 익명 pull 우회.
- **레지스트리 포트 5050**: macOS는 5000을 AirPlay가 점유.
- **cosign v3 오프라인 서명**: key-based는 `--use-signing-config=false --tlog-upload=false`, 검증은 `--insecure-ignore-tlog`.
- **`~/.sigstore` root 소유**: keyless 전 `sudo chown`으로 권한 회복 필요(`keyless-doctor`가 점검).

## 파일 안내
- `app-go/` `app-python/` `app-java/` — 각 언어 최소 HTTP 서버
- `melange-<lang>.yaml` / `apko-<lang>.yaml` — 패키지 빌드 / 이미지 조립 정의
- `Dockerfile.naive-<lang>` — 비교 기준점
- `scripts/` — compare / compare-all / verify 헬퍼
- `docs/superpowers/` — 설계 spec과 구현 계획
- `report.html` — 시각 정리 리포트
