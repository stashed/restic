SHELL=/bin/bash -o pipefail

BIN      	:= restic
REGISTRY 	?= stashed
GO_PKG   	:= stash.appscode.dev
REPO     	:= $(notdir $(shell pwd))
SRC_DIRS 	:= *.go cmd helpers internal

# This version-strategy uses git tags to set the version string
git_branch       := $(shell git rev-parse --abbrev-ref HEAD)
git_tag          := $(shell git describe --exact-match --abbrev=0 2>/dev/null || echo "")
commit_hash      := $(shell git rev-parse --verify HEAD)
commit_timestamp := $(shell date --date="@$$(git show -s --format=%ct)" --utc +%FT%T)

VERSION          := $(shell git describe --tags --always --dirty)
version_strategy := commit_hash
ifdef git_tag
	VERSION := $(git_tag)
	version_strategy := tag
else
	ifeq (,$(findstring $(git_branch),master HEAD))
		ifneq (,$(patsubst release-%,,$(git_branch)))
			VERSION := $(git_branch)
			version_strategy := branch
		endif
	endif
endif

IMAGE           := $(REGISTRY)/$(BIN)
TAG             := $(VERSION)
GO_VERSION      ?= 1.16
BUILD_IMAGE     ?= appscode/golang-dev:$(GO_VERSION)
DOCKERFILE		:= $(shell pwd)/docker/Dockerfile

# Directories that we need created to build/test.
BUILD_DIRS  := .go/bin	 \
               .go/cache \

.PHONY: all clean test restic

all: fmt build restic test

# run gofmt, goimports etc.
.PHONY: fmt
fmt: $(BUILD_DIRS)
	@docker run                                                 \
	    -i                                                      \
	    --rm                                                    \
	    -u $$(id -u):$$(id -g)                                  \
	    -v $$(pwd):/src                                         \
	    -w /src                                                 \
	    -v $$(pwd)/.go/bin:/go/bin                				\
	    -v $$(pwd)/.go/cache:/.cache                            \
	    --env HTTP_PROXY=$(HTTP_PROXY)                          \
	    --env HTTPS_PROXY=$(HTTPS_PROXY)                        \
	    $(BUILD_IMAGE)                                          \
	    /bin/bash -c "                                          \
	        REPO_PKG=$(GO_PKG)                                  \
	        ./helpers/fmt.sh $(SRC_DIRS)                        \
	    "

# build release binaries
.PHONY: build
build: $(BUILD_DIRS)
	@echo "Building release binaries"
	@docker run                                                 \
	    -i                                                      \
	    --rm                                                    \
	    -u $$(id -u):$$(id -g)                                  \
	    -v $$(pwd):/src                                         \
	    -w /src                                                 \
	    -v $$(pwd)/.go/bin:/go/bin    				            \
	    -v $$(pwd)/.go/cache:/.cache                            \
	    --env HTTP_PROXY=$(HTTP_PROXY)                          \
	    --env HTTPS_PROXY=$(HTTPS_PROXY)                        \
	    --env GO111MODULE=on                                    \
	    $(BUILD_IMAGE)                                          \
	    go run /src/helpers/build-release-binaries/main.go --version ${TAG} --source="/src" --output="/go/bin/"

restic: $(BUILD_DIRS)
	@echo "Building restic binary"
	@docker run                                                 \
	    -i                                                      \
	    --rm                                                    \
	    -u $$(id -u):$$(id -g)                                  \
	    -v $$(pwd):/src                                         \
	    -w /src                                                 \
	    -v $$(pwd)/.go/bin:/go/bin    				            \
	    -v $$(pwd)/.go/cache:/.cache                            \
	    --env HTTP_PROXY=$(HTTP_PROXY)                          \
	    --env HTTPS_PROXY=$(HTTPS_PROXY)                        \
	    --env GO111MODULE=on                                    \
	    golang:${GO_VERSION}-alpine                             \
	    go run build.go

.PHONY: container
container: restic
	@echo "Building restic docker image"
	docker build --rm -t ${REGISTRY}/${BIN}:${TAG} -f ${DOCKERFILE} .

.PHONY: push
push: container
	@echo "Pushing docker image: ${REGISTRY}/${BIN}:${TAG}"
	docker push ${REGISTRY}/${BIN}:${TAG}

ADDTL_LINTERS   := goconst,gofmt,goimports,unparam

.PHONY: lint
lint: $(BUILD_DIRS)
	@echo "running linter"
	@docker run                                                 \
	    -i                                                      \
	    --rm                                                    \
	    -u $$(id -u):$$(id -g)                                  \
	    -v $$(pwd):/src                                         \
	    -w /src                                                 \
	    -v $$(pwd)/.go/bin:/go/bin    				            \
	    -v $$(pwd)/.go/cache:/.cache                            \
	    --env HTTP_PROXY=$(HTTP_PROXY)                          \
	    --env HTTPS_PROXY=$(HTTPS_PROXY)                        \
	    --env GO111MODULE=on                                    \
	    --env GOFLAGS="-mod=vendor"                             \
	    $(BUILD_IMAGE)                                          \
	    golangci-lint run --enable $(ADDTL_LINTERS) --timeout=10m --skip-dirs-use-default --skip-dirs=vendor

$(BUILD_DIRS):
	@mkdir -p $@

clean:
	rm -rf restic .go

.PHONY: test
test: $(BUILD_DIRS)
	@docker run                                                 \
	    -i                                                      \
	    --rm                                                    \
	    -u $$(id -u):$$(id -g)                                  \
	    -v $$(pwd):/src                                         \
	    -w /src                                                 \
	    --net=host                                              \
	    -v $(HOME)/.credentials:$(HOME)/.credentials            \
	    -v $$(pwd)/.go/bin:/go/bin                				\
	    -v $$(pwd)/.go/cache:/.cache                            \
	    --env HTTP_PROXY=$(HTTP_PROXY)                          \
	    --env HTTPS_PROXY=$(HTTPS_PROXY)                        \
	    --env GOFLAGS="-mod=vendor"                             \
	    $(BUILD_IMAGE)                                          \
		go test ./cmd/... ./internal/...
