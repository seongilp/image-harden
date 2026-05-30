# 설계: 멀티 워크로드 하드닝 + keyless 서명

**작성일:** 2026-05-31
**확장 대상:** 기존 Go 하드닝 실습에 Python·Java 워크로드 추가 + keyless 서명 추가
**결정 사항:** Java = JRE+jar (Gradle 빌드) / Python = 인터프리터+pip 의존성 / 서명 = key-based 유지 + keyless 추가

---

## 1. APP 변수 파라미터화 (DRY)

기존 Go 파일을 `*-go`로 정리하고 같은 패턴을 python/java로 복제. Makefile은 `APP` 변수 하나로 전부 처리.

```
image-harden/
├── app-go/        main.go, main_test.go, go.mod   (기존 app/ 이름변경)
├── app-python/    main.py, requirements.txt, test_main.py
├── app-java/      build.gradle, settings.gradle, src/main/java/hello/Main.java
├── melange-go.yaml / melange-python.yaml / melange-java.yaml
├── apko-go.yaml   / apko-python.yaml   / apko-java.yaml
├── Dockerfile.naive-go / Dockerfile.naive-python / Dockerfile.naive-java
└── Makefile       (APP=go|python|java)
```

Makefile 변수:
```
APP       ?= go
MELANGE_YAML = melange-$(APP).yaml
APKO_YAML    = apko-$(APP).yaml
WOLFI_IMG    = harden-$(APP):wolfi
NAIVE_IMG    = harden-$(APP):naive
```

사용:
```bash
make APP=python image
make APP=java all
make compare-all        # 세 언어 한 표로
make all-go / all-python / all-java
```

## 2. 확인된 Wolfi 패키지 (조회 완료)

- Java 빌드: `openjdk-21-default-jdk`, `gradle-9`
- Java 런타임: `openjdk-21-jre`
- Python 런타임: `python-3.13`
- Python pip: `py3.13-pip`

melange는 python/java 내장 파이프라인 대신 **명시적 `runs:` 셸 스텝** 사용 (안정적·학습용).

## 3. 언어별 melange/apko 차이

**Python**
- melange env: `python-3.13`, `py3.13-pip`, `busybox`
- 빌드: `python3.13 -m pip install --no-cache-dir --target=<destdir>/usr/lib/python3.13/site-packages -r requirements.txt` + `main.py`를 `<destdir>/usr/bin/hello-py`로 설치
- apko: 패키지 `python-3.13` + `hello-py@local`, entrypoint `["python3.13","/usr/bin/hello-py"]`
- 예상 ~50–70MB

**Java (JRE+jar, Gradle)**
- melange env: `openjdk-21-default-jdk`, `gradle-9`, `busybox`
- 빌드: `gradle --no-daemon build` → 생성된 jar를 `<destdir>/usr/share/hello/app.jar`로 설치
- apko: 패키지 `openjdk-21-jre` + `hello-java@local`, entrypoint `["java","-jar","/usr/share/hello/app.jar"]`
- 예상 ~180–230MB

세 경우 모두 non-root(uid 65532) + 셸 없음 + SBOM 자동 + 서명 동일 적용.

## 4. keyless 서명 추가

- 기존 `make sign`(key-based) 유지. 추가 타겟:
  - `make sign-keyless` — `cosign sign <digest>` (OIDC 브라우저 로그인 → Fulcio 임시 인증서 → Rekor 기록, 보관 키 없음)
  - `make verify-keyless` — `cosign verify --certificate-identity <EMAIL> --certificate-oidc-issuer <ISSUER>`
  - `make keyless-doctor` — `~/.sigstore` 권한·cosign 버전 점검 후 안내
- **현실적 제약(정직하게 문서화):**
  1. 인터랙티브(브라우저 OIDC) → `make all`에 미포함, 별도 타겟. CI(GitHub Actions)에선 무인 자동화됨을 README 설명.
  2. `~/.sigstore`가 root 소유라 막힘 → `sudo chown -R $(whoami) ~/.sigstore` 선행 필요(사용자가 직접 실행). `keyless-doctor`가 점검.
- key-based와 keyless 차이를 README 표로 정리.

## 5. 비교 산출물

`make compare-all` → 언어별 naive vs wolfi 크기·CVE 표.

| 언어 | naive 크기/CVE | wolfi 크기/CVE |
|---|---|---|
| go | 1.41GB / 85 | 8.94MB / 0 |
| python | 측정 | 측정 |
| java | 측정 | 측정 |

## 6. 검증 (완료 기준)

각 언어: 이미지 `docker run`+요청 동작 확인 → 셸 없음 확인 → trivy/grype 스캔 → key-based 서명·검증 통과 → SBOM에 선언 패키지만. keyless는 환경 준비되면 `keyless-doctor` 통과 후 별도 검증.

## 7. 범위 밖 (YAGNI)

- Java native-image(GraalVM) — JRE+jar만
- Maven — Gradle만
- 멀티아키 — aarch64만
- keyless를 기본 파이프라인에 강제 포함 — 인터랙티브라 별도 유지
