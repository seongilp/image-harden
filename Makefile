# 모든 docker 호출에 빈 config를 써서 cgr.dev credential helper를 우회한다.
export DOCKER_CONFIG := $(CURDIR)/.docker-anon

# 워크로드 선택: go | python | java
APP        ?= go

ARCH       := aarch64
MELANGE    := cgr.dev/chainguard/melange:latest
APKO       := cgr.dev/chainguard/apko:latest

MELANGE_YAML := melange-$(APP).yaml
APKO_YAML    := apko-$(APP).yaml
NAIVE_IMG    := harden-$(APP):naive
WOLFI_IMG    := harden-$(APP):wolfi
REPO         := harden-$(APP)
SBOM_DIR     := sbom-$(APP)
TAR          := harden-$(APP).tar

# macOS는 5000을 AirPlay(ControlCenter)가 점유하므로 5050 사용
REG        := localhost:5050
REG_NAME   := harden-registry

.PHONY: naive
naive:
	docker build -f Dockerfile.naive-$(APP) -t $(NAIVE_IMG) .
	@echo "built $(NAIVE_IMG)"

keys/melange.rsa:
	mkdir -p keys
	docker run --rm -v "$(CURDIR)":/work -w /work $(MELANGE) keygen keys/melange.rsa

.PHONY: pkg
pkg: keys/melange.rsa
	docker run --rm --privileged -v "$(CURDIR)":/work -w /work $(MELANGE) \
		build $(MELANGE_YAML) --arch $(ARCH) --signing-key keys/melange.rsa
	@echo "built package:"; ls packages/$(ARCH)/*.apk

.PHONY: image
image: pkg
	mkdir -p $(SBOM_DIR)
	docker run --rm -v "$(CURDIR)":/work -w /work $(APKO) \
		build $(APKO_YAML) $(WOLFI_IMG) /work/$(TAR) \
		--arch $(ARCH) --sbom-path /work/$(SBOM_DIR)
	@LOADED=$$(docker load -i $(TAR) | sed -n 's/.*Loaded image: //p'); \
		docker tag $$LOADED $(WOLFI_IMG); \
		echo "tagged $$LOADED as $(WOLFI_IMG)"

.PHONY: registry
registry:
	@if [ "$$(docker inspect -f '{{.State.Running}}' $(REG_NAME) 2>/dev/null)" != "true" ]; then \
		docker rm -f $(REG_NAME) >/dev/null 2>&1 || true; \
		docker run -d -p 5050:5000 --restart=always --name $(REG_NAME) registry:2; \
	fi
	@echo "registry up at $(REG)"

keys/cosign.key:
	mkdir -p keys
	cd keys && COSIGN_PASSWORD="" cosign generate-key-pair

.PHONY: sign
sign: image registry keys/cosign.key
	docker tag $(WOLFI_IMG) $(REG)/$(REPO):wolfi
	docker push $(REG)/$(REPO):wolfi
	@DIGEST=$$(docker inspect --format='{{range .RepoDigests}}{{println .}}{{end}}' $(REG)/$(REPO):wolfi | grep '^$(REG)/' | head -1); \
		echo "signing $$DIGEST"; \
		COSIGN_PASSWORD="" cosign sign --yes --key keys/cosign.key \
			--use-signing-config=false --tlog-upload=false \
			--allow-insecure-registry $$DIGEST

.PHONY: scan
scan: naive image
	@echo "=== trivy: $(NAIVE_IMG) ==="; trivy image -q --severity HIGH,CRITICAL $(NAIVE_IMG) || true
	@echo "=== trivy: $(WOLFI_IMG) ==="; trivy image -q --severity HIGH,CRITICAL $(WOLFI_IMG) || true
	@echo "=== grype: $(WOLFI_IMG) ==="; grype $(WOLFI_IMG) || true

.PHONY: compare
compare: naive image
	./scripts/compare.sh $(APP)

.PHONY: verify
verify: sign
	./scripts/verify.sh $(APP)

.PHONY: all
all: naive image sign scan compare verify

# ---- 멀티 워크로드 편의 타겟 ----
.PHONY: all-go all-python all-java compare-all
all-go:
	$(MAKE) APP=go all
all-python:
	$(MAKE) APP=python all
all-java:
	$(MAKE) APP=java all
compare-all:
	./scripts/compare-all.sh

# ---- keyless 서명 (인터랙티브: 브라우저 OIDC) ----
.PHONY: keyless-doctor sign-keyless verify-keyless
keyless-doctor:
	@echo "cosign:"; cosign version 2>/dev/null | grep GitVersion || true
	@OWN=$$(stat -f '%Su' $$HOME/.sigstore 2>/dev/null); \
		if [ -n "$$OWN" ] && [ "$$OWN" != "$$(whoami)" ]; then \
			echo "⚠ ~/.sigstore 소유자=$$OWN → 실행: sudo chown -R $$(whoami) ~/.sigstore"; \
		else echo "✓ ~/.sigstore OK (없으면 자동 생성됨)"; fi

sign-keyless: image registry
	docker tag $(WOLFI_IMG) $(REG)/$(REPO):wolfi
	docker push $(REG)/$(REPO):wolfi
	@DIGEST=$$(docker inspect --format='{{range .RepoDigests}}{{println .}}{{end}}' $(REG)/$(REPO):wolfi | grep '^$(REG)/' | head -1); \
		echo "keyless signing $$DIGEST (브라우저 OIDC 로그인 필요)"; \
		cosign sign --yes --allow-insecure-registry $$DIGEST

# 사용: make verify-keyless APP=go IDENTITY=you@gmail.com ISSUER=https://accounts.google.com
verify-keyless:
	@DIGEST=$$(docker inspect --format='{{range .RepoDigests}}{{println .}}{{end}}' $(REG)/$(REPO):wolfi | grep '^$(REG)/' | head -1); \
		cosign verify --allow-insecure-registry \
			--certificate-identity "$(IDENTITY)" \
			--certificate-oidc-issuer "$(ISSUER)" $$DIGEST

.PHONY: clean clean-all
clean:
	-docker rmi $(NAIVE_IMG) $(WOLFI_IMG) $(WOLFI_IMG)-arm64 $(REG)/$(REPO):wolfi 2>/dev/null
	-rm -rf $(SBOM_DIR) $(TAR)
	@echo "cleaned $(APP) (keys/ 보존)"

clean-all:
	$(MAKE) APP=go clean; $(MAKE) APP=python clean; $(MAKE) APP=java clean
	-docker rm -f $(REG_NAME) 2>/dev/null
	-rm -rf packages
	@echo "cleaned all"
