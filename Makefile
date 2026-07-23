# Kazoo 5 Debian + RPM builder
# Top-level entrypoints. All real logic lives in scripts/*.sh.

SHELL          := /usr/bin/env bash
.SHELLFLAGS    := -euo pipefail -c
.DEFAULT_GOAL  := help

# --- Version pins (single source of truth) ---
KAZOO_VERSION  := $(shell cat config/kazoo.version)
OTP_VERSION    := $(shell cat config/otp.version)
REBAR_VERSION  := $(shell cat config/rebar.version)
PKG_REVISION   := $(shell cat config/package.revision)

# SHA-256 pins for the two artifacts fetched over the network at image-build
# time (OTP source tarball + rebar3 binary). Verified in the Dockerfiles so a
# tampered or corrupted download fails the build instead of being trusted.
OTP_SHA256     := $(shell cat config/otp.sha256)
REBAR_SHA256   := $(shell cat config/rebar.sha256)

# --- Required per-invocation variable ---
TARGET         ?=

VALID_TARGETS  := debian-12 el9

# --- Build directories ---
BUILD_DIR      := build
OUT_DIR        := $(BUILD_DIR)/out

export KAZOO_VERSION OTP_VERSION REBAR_VERSION PKG_REVISION

.PHONY: help
help:  ## Show available targets
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | sort \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Variables:"
	@echo "  TARGET=$(VALID_TARGETS)  (required for build/sign/verify)"
	@echo "  KAZOO_VERSION=$(KAZOO_VERSION) OTP_VERSION=$(OTP_VERSION) PKG_REVISION=$(PKG_REVISION)"

.PHONY: check-target
check-target:
	@if [ -z "$(TARGET)" ]; then \
	  echo "ERROR: TARGET is required. One of: $(VALID_TARGETS)"; exit 2; \
	fi
	@case " $(VALID_TARGETS) " in \
	  *" $(TARGET) "*) ;; \
	  *) echo "ERROR: TARGET=$(TARGET) invalid. One of: $(VALID_TARGETS)"; exit 2 ;; \
	esac

.PHONY: docker-build
docker-build: check-target  ## Build the docker image for TARGET
	docker build \
	  --build-arg OTP_VERSION=$(OTP_VERSION) \
	  --build-arg REBAR_VERSION=$(REBAR_VERSION) \
	  --build-arg OTP_SHA256=$(OTP_SHA256) \
	  --build-arg REBAR_SHA256=$(REBAR_SHA256) \
	  -t openkazoo-kazoo5-builder:$(TARGET) \
	  -f docker/Dockerfile.$(TARGET) .

.PHONY: build
build: check-target docker-build  ## Produce a package for TARGET in $(OUT_DIR)
	mkdir -p $(OUT_DIR)
	docker run --rm \
	  -v $(CURDIR):/work \
	  -e TARGET=$(TARGET) \
	  -e KAZOO_VERSION -e OTP_VERSION -e REBAR_VERSION -e PKG_REVISION \
	  openkazoo-kazoo5-builder:$(TARGET) \
	  /work/scripts/build.sh

.PHONY: sign
sign: check-target  ## Sign the package for TARGET (requires GPG_PRIVATE_KEY in env or files in tests/fixtures/gpg/)
	./scripts/sign.sh $(TARGET)

.PHONY: verify
verify: check-target  ## Smoke-test the package for TARGET
	./scripts/verify.sh $(TARGET)

.PHONY: publish
publish:  ## Build apt + yum repos under build/repo/ for both targets (assumes build/out/ populated)
	./scripts/publish.sh

.PHONY: test
test:  ## Run bats unit tests
	@# Unset exported vars so build.sh validation tests can assert "unset" paths.
	env -u KAZOO_VERSION -u OTP_VERSION -u REBAR_VERSION -u PKG_REVISION -u TARGET \
	  ./tests/bats/bin/bats tests/unit/

.PHONY: clean
clean:  ## Remove build outputs (does NOT remove docker images)
	rm -rf $(BUILD_DIR)

.PHONY: sparkly-clean
sparkly-clean: clean  ## Also remove docker images
	-docker image rm openkazoo-kazoo5-builder:debian-12 openkazoo-kazoo5-builder:el9 2>/dev/null
