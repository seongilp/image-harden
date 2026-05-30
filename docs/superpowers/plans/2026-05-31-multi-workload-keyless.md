# 멀티 워크로드 + keyless Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. 체크박스(`- [ ]`)로 추적.

**Goal:** 기존 Go 하드닝 파이프라인을 `APP` 변수로 파라미터화하고 Python·Java 워크로드를 추가, keyless 서명 타겟까지 더한다.

**Architecture:** Makefile을 `APP=go|python|java`로 파라미터화. 언어별 `app-*/`, `melange-*.yaml`, `apko-*.yaml`, `Dockerfile.naive-*`. melange는 명시적 `runs:` 스텝. 서명은 key-based 유지 + keyless 별도 타겟.

**Tech Stack:** Go 1.26, Python 3.13, OpenJDK 21 + Gradle 9, melange, apko, cosign(v3, key+keyless), trivy, grype.

---

### Task 1: Go 파일을 APP 파라미터 구조로 리팩터

**목표:** 동작 동일, 파일명/Makefile만 파라미터화.

- [ ] **Step 1: 파일 rename**
  - `app/` → `app-go/`
  - `melange.yaml` → `melange-go.yaml` (pipeline modroot `app` → `app-go`)
  - `apko.yaml` → `apko-go.yaml`
  - `Dockerfile.naive` → `Dockerfile.naive-go` (`COPY app/` → `COPY app-go/`)

- [ ] **Step 2: Makefile 파라미터화** — 아래 변수/타겟으로 교체:
```makefile
export DOCKER_CONFIG := $(CURDIR)/.docker-anon
APP        ?= go
ARCH       := aarch64
MELANGE    := cgr.dev/chainguard/melange:latest
APKO       := cgr.dev/chainguard/apko:latest
MELANGE_YAML := melange-$(APP).yaml
APKO_YAML    := apko-$(APP).yaml
NAIVE_IMG    := harden-$(APP):naive
WOLFI_IMG    := harden-$(APP):wolfi
REG          := localhost:5050
REG_NAME     := harden-registry

.PHONY: naive
naive:
	docker build -f Dockerfile.naive-$(APP) -t $(NAIVE_IMG) .

keys/melange.rsa:
	mkdir -p keys
	docker run --rm -v "$(CURDIR)":/work -w /work $(MELANGE) keygen keys/melange.rsa

.PHONY: pkg
pkg: keys/melange.rsa
	docker run --rm --privileged -v "$(CURDIR)":/work -w /work $(MELANGE) \
		build $(MELANGE_YAML) --arch $(ARCH) --signing-key keys/melange.rsa

.PHONY: image
image: pkg
	mkdir -p sbom-$(APP)
	docker run --rm -v "$(CURDIR)":/work -w /work $(APKO) \
		build $(APKO_YAML) $(WOLFI_IMG) /work/harden-$(APP).tar \
		--arch $(ARCH) --sbom-path /work/sbom-$(APP)
	@LOADED=$$(docker load -i harden-$(APP).tar | sed -n 's/.*Loaded image: //p'); \
		docker tag $$LOADED $(WOLFI_IMG); echo "tagged $$LOADED as $(WOLFI_IMG)"
```
  (sign/registry/scan/compare/verify 타겟은 `$(WOLFI_IMG)`/`$(NAIVE_IMG)` 변수를 쓰도록 기존 내용 유지하며 이어붙임. compare.sh/verify.sh는 Task 4에서 멀티 대응.)

- [ ] **Step 3: melange-go.yaml의 `modroot: app` → `modroot: app-go`로 수정**

- [ ] **Step 4: 검증 — go 재빌드/스캔**
  Run: `make APP=go clean 2>/dev/null; make APP=go image && make APP=go compare`
  Expected: `harden-go:wolfi` 빌드 성공, 비교 표에 go naive/wolfi 출력.

- [ ] **Step 5: 커밋** `refactor: Go 파이프라인 APP 변수 파라미터화`

---

### Task 2: Python 워크로드

**Files:** `app-python/main.py`, `app-python/requirements.txt`, `app-python/test_main.py`, `melange-python.yaml`, `apko-python.yaml`, `Dockerfile.naive-python`

- [ ] **Step 1: 앱 작성**

`app-python/requirements.txt`:
```
```
(의존성 데모용: 표준 http.server만 쓰되, pip 설치 흐름 증명을 위해 작은 패키지 하나 추가)
```
requests==2.32.3
```

`app-python/main.py`:
```python
import http.server, socketserver

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"hello, hardened (python)\n")

def main():
    with socketserver.TCPServer(("", 8080), H) as s:
        print("listening on :8080")
        s.serve_forever()

if __name__ == "__main__":
    main()
```

`app-python/test_main.py`:
```python
from main import H

def test_handler_exists():
    assert hasattr(H, "do_GET")
```

- [ ] **Step 2: 테스트 실행** Run: `cd app-python && python3 -m pytest -q || python3 -m unittest` Expected: 통과(없으면 간단 import 확인)

- [ ] **Step 3: Dockerfile.naive-python**
```dockerfile
FROM python:3.13
WORKDIR /app
COPY app-python/ ./
RUN pip install --no-cache-dir -r requirements.txt
EXPOSE 8080
CMD ["python", "main.py"]
```

- [ ] **Step 4: melange-python.yaml**
```yaml
package:
  name: hello-py
  version: 1.0.0
  epoch: 0
  description: "minimal hardened python http server"
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
      - python-3.13
      - py3.13-pip
pipeline:
  - runs: |
      SP="${{targets.destdir}}/usr/lib/python3.13/site-packages"
      mkdir -p "$SP" "${{targets.destdir}}/usr/bin"
      python3.13 -m pip install --no-cache-dir --target="$SP" -r app-python/requirements.txt
      install -m644 app-python/main.py "${{targets.destdir}}/usr/bin/hello-py"
```

- [ ] **Step 5: apko-python.yaml**
```yaml
contents:
  keyring:
    - https://packages.wolfi.dev/os/wolfi-signing.rsa.pub
    - keys/melange.rsa.pub
  repositories:
    - https://packages.wolfi.dev/os
    - '@local /work/packages'
  packages:
    - python-3.13
    - hello-py@local
accounts:
  groups: [{groupname: nonroot, gid: 65532}]
  users: [{username: nonroot, uid: 65532, gid: 65532}]
  run-as: 65532
entrypoint:
  command: python3.13 /usr/bin/hello-py
archs:
  - aarch64
```

- [ ] **Step 6: 빌드 + 동작 확인**
  Run: `make APP=python image && docker run -d --rm -p 8083:8080 --name py-test harden-python:wolfi && sleep 2 && curl -s localhost:8083/ ; docker stop py-test`
  Expected: `hello, hardened (python)`

- [ ] **Step 7: 셸 없음 + 스캔**
  Run: `make APP=python compare`
  Expected: naive(수백 MB) vs wolfi 표.

- [ ] **Step 8: 커밋** `feat: Python 워크로드 하드닝(melange pip vendoring + apko)`

---

### Task 3: Java 워크로드 (JRE+jar, Gradle)

**Files:** `app-java/settings.gradle`, `app-java/build.gradle`, `app-java/src/main/java/hello/Main.java`, `melange-java.yaml`, `apko-java.yaml`, `Dockerfile.naive-java`

- [ ] **Step 1: Gradle 앱 작성**

`app-java/settings.gradle`:
```groovy
rootProject.name = 'hello'
```

`app-java/build.gradle`:
```groovy
plugins {
    id 'application'
}
application {
    mainClass = 'hello.Main'
}
jar {
    manifest { attributes 'Main-Class': 'hello.Main' }
}
```

`app-java/src/main/java/hello/Main.java`:
```java
package hello;

import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;

public class Main {
    public static void main(String[] args) throws Exception {
        HttpServer server = HttpServer.create(new InetSocketAddress(8080), 0);
        server.createContext("/", ex -> {
            byte[] body = "hello, hardened (java)\n".getBytes();
            ex.sendResponseHeaders(200, body.length);
            ex.getResponseBody().write(body);
            ex.close();
        });
        System.out.println("listening on :8080");
        server.start();
    }
}
```

- [ ] **Step 2: Dockerfile.naive-java**
```dockerfile
FROM gradle:9-jdk21
WORKDIR /app
COPY app-java/ ./
RUN gradle --no-daemon jar
EXPOSE 8080
CMD ["java", "-jar", "build/libs/hello.jar"]
```

- [ ] **Step 3: melange-java.yaml**
```yaml
package:
  name: hello-java
  version: 1.0.0
  epoch: 0
  description: "minimal hardened java http server"
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
      - openjdk-21-default-jdk
      - gradle-9
pipeline:
  - runs: |
      cd app-java
      gradle --no-daemon --offline=false jar
      mkdir -p "${{targets.destdir}}/usr/share/hello"
      install -m644 build/libs/hello.jar "${{targets.destdir}}/usr/share/hello/app.jar"
```

- [ ] **Step 4: apko-java.yaml**
```yaml
contents:
  keyring:
    - https://packages.wolfi.dev/os/wolfi-signing.rsa.pub
    - keys/melange.rsa.pub
  repositories:
    - https://packages.wolfi.dev/os
    - '@local /work/packages'
  packages:
    - openjdk-21-jre
    - hello-java@local
accounts:
  groups: [{groupname: nonroot, gid: 65532}]
  users: [{username: nonroot, uid: 65532, gid: 65532}]
  run-as: 65532
entrypoint:
  command: java -jar /usr/share/hello/app.jar
archs:
  - aarch64
```

- [ ] **Step 5: 빌드 + 동작 확인**
  Run: `make APP=java image && docker run -d --rm -p 8084:8080 --name java-test harden-java:wolfi && sleep 3 && curl -s localhost:8084/ ; docker stop java-test`
  Expected: `hello, hardened (java)`

- [ ] **Step 6: 스캔/비교** Run: `make APP=java compare`

- [ ] **Step 7: 커밋** `feat: Java 워크로드 하드닝(Gradle jar + JRE apko)`

---

### Task 4: compare-all + keyless + 문서 갱신

**Files:** `scripts/compare-all.sh`, Makefile, README.md, report.html

- [ ] **Step 1: compare-all.sh** — go/python/java 각각 naive/wolfi 크기·CVE를 한 표로. (compare.sh의 count_vulns 재사용, 이미지명 `harden-<lang>`.)

- [ ] **Step 2: Makefile에 멀티/keyless 타겟 추가**
```makefile
.PHONY: all-go all-python all-java compare-all
all-go:     ; $(MAKE) APP=go all
all-python: ; $(MAKE) APP=python all
all-java:   ; $(MAKE) APP=java all
compare-all: ; ./scripts/compare-all.sh

.PHONY: keyless-doctor sign-keyless verify-keyless
keyless-doctor:
	@echo "cosign:"; cosign version 2>/dev/null | grep GitVersion || true
	@OWN=$$(stat -f '%Su' $$HOME/.sigstore 2>/dev/null); \
		if [ -n "$$OWN" ] && [ "$$OWN" != "$$(whoami)" ]; then \
			echo "⚠ ~/.sigstore 소유자=$$OWN → 실행: sudo chown -R $$(whoami) ~/.sigstore"; \
		else echo "✓ ~/.sigstore OK (또는 없음, 자동 생성됨)"; fi

sign-keyless: image registry
	docker tag $(WOLFI_IMG) $(REG)/harden-$(APP):wolfi
	docker push $(REG)/harden-$(APP):wolfi
	@DIGEST=$$(docker inspect --format='{{range .RepoDigests}}{{println .}}{{end}}' $(REG)/harden-$(APP):wolfi | grep '^$(REG)/' | head -1); \
		echo "keyless signing $$DIGEST (브라우저 OIDC 로그인 필요)"; \
		cosign sign --yes --allow-insecure-registry $$DIGEST

verify-keyless:
	@DIGEST=$$(docker inspect --format='{{range .RepoDigests}}{{println .}}{{end}}' $(REG)/harden-$(APP):wolfi | grep '^$(REG)/' | head -1); \
		cosign verify --allow-insecure-registry \
			--certificate-identity "$(IDENTITY)" \
			--certificate-oidc-issuer "$(ISSUER)" $$DIGEST
```

- [ ] **Step 3: compare-all 실행 + 표 확보** Run: `make compare-all`

- [ ] **Step 4: keyless-doctor 실행 (안내 확인)** Run: `make keyless-doctor`

- [ ] **Step 5: README.md / report.html 갱신** — 멀티 워크로드 결과표 + key vs keyless 비교 섹션 추가.

- [ ] **Step 6: 커밋** `feat: compare-all + keyless 타겟 + 문서 갱신`

---

## Self-Review
- spec §1 파라미터화 → Task 1 ✓ / §3 Python → Task 2 ✓ / §3 Java → Task 3 ✓ / §4 keyless → Task 4 ✓ / §5 비교 → Task 4 compare-all ✓
- 리스크: (a) melange pip --target 경로/버전 일치, (b) gradle 빌드 네트워크, (c) keyless 인터랙티브 → 각 Task 검증 스텝에서 확인, 실패 시 STOP & 조정.
- 이미지명 일관성: `harden-$(APP):{naive,wolfi}` 전 Task 통일. 패키지명 `hello-py`/`hello-java`.
