# 모든 docker 호출에 빈 config를 써서 cgr.dev credential helper를 우회한다.
export DOCKER_CONFIG := $(CURDIR)/.docker-anon

ARCH       := aarch64
MELANGE    := cgr.dev/chainguard/melange:latest
APKO       := cgr.dev/chainguard/apko:latest
NAIVE_IMG  := harden:naive
WOLFI_IMG  := harden:wolfi
# macOS는 5000을 AirPlay(ControlCenter)가 점유하므로 5050 사용
REG        := localhost:5050
REG_NAME   := harden-registry

.PHONY: naive
naive:
	docker build -f Dockerfile.naive -t $(NAIVE_IMG) .
	@echo "built $(NAIVE_IMG)"

keys/melange.rsa:
	mkdir -p keys
	docker run --rm -v "$(CURDIR)":/work -w /work $(MELANGE) keygen keys/melange.rsa

.PHONY: pkg
pkg: keys/melange.rsa
	docker run --rm --privileged -v "$(CURDIR)":/work -w /work $(MELANGE) \
		build melange.yaml --arch $(ARCH) --signing-key keys/melange.rsa
	@echo "built package:"; ls packages/$(ARCH)/*.apk

.PHONY: image
image: pkg
	mkdir -p sbom
	docker run --rm -v "$(CURDIR)":/work -w /work $(APKO) \
		build apko.yaml $(WOLFI_IMG) /work/harden-wolfi.tar \
		--arch $(ARCH) --sbom-path /work/sbom
	@LOADED=$$(docker load -i harden-wolfi.tar | sed -n 's/.*Loaded image: //p'); \
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
	docker tag $(WOLFI_IMG) $(REG)/harden:wolfi
	docker push $(REG)/harden:wolfi
	@DIGEST=$$(docker inspect --format='{{range .RepoDigests}}{{println .}}{{end}}' $(REG)/harden:wolfi | grep '^$(REG)/' | head -1); \
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
	./scripts/compare.sh

.PHONY: verify
verify: sign
	./scripts/verify.sh

.PHONY: all
all: naive image sign scan compare verify

.PHONY: clean
clean:
	-docker rmi $(NAIVE_IMG) $(WOLFI_IMG) $(WOLFI_IMG)-arm64 $(REG)/harden:wolfi 2>/dev/null
	-docker rm -f $(REG_NAME) 2>/dev/null
	-rm -rf packages sbom harden-wolfi.tar
	@echo "cleaned (keys/ 는 보존)"
