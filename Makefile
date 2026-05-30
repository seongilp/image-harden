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
