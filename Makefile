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
