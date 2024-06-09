# VERSION defines the project version for the bundle.
# Update this value when you upgrade the version of your project.
# To re-generate a bundle for another specific version without changing the standard setup, you can:
# - use the VERSION as arg of the bundle target (e.g make bundle VERSION=0.0.2)
# - use environment variables to overwrite this value (e.g export VERSION=0.0.2)
VERSION ?= 0.0.14

# Image URL to use all building/pushing image targets
#IMG ?= zefir01/operator:latest
IMG ?= zefir01/crossform:${VERSION}
IMG_LATEST ?= zefir01/crossform:latest
IMG_FUNCTION ?= zefir01/proxy-function:${VERSION}
IMG_FUNCTION_LATEST ?= zefir01/proxy-function:latest

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: package-function
package-function: package-function
	crossplane xpkg build \
        --package-root=pkg/crossplane/package \
        --embed-runtime-image=${IMG_FUNCTION} \
        --package-file=function-amd64.xpkg

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet main.go

.PHONY: vet-function
vet-function: ## Run go vet against code.
	go vet proxy-function.go

##@ Build

.PHONY: set-helm-version
set-helm-version:
	yq e ".repoServer.image.tag = \"${VERSION}\"" -P -i helm/crossform/values.yaml
	yq e ".function.image.tag = \"${VERSION}\"" -P -i helm/crossform/values.yaml
	yq e ".version = \"${VERSION}\"" -P -i helm/crossform/Chart.yaml
	yq e ".appVersion = \"${VERSION}\"" -P -i helm/crossform/Chart.yaml

.PHONY: build
build: fmt vet ## Build manager binary.
	go build -o bin/manager main.go

.PHONY: build-function
build-function: fmt vet-function ## Build manager binary.
	go build -o bin/function proxy-function.go

.PHONY: run
run: manifests fmt vet ## Run a controller from your host.
	go run ./main.go

# Run with delve against the configured Kubernetes cluster in ~/.kube/config
run-delve: fmt vet manifests
	go build  main.go
	dlv --listen=:2345 --headless=true --api-version=2 --accept-multiclient exec ./main

# If you wish built the manager image targeting other platforms you can use the --platform flag.
# (i.e. docker build --platform linux/arm64 ). However, you must enable docker buildKit for it.
# More info: https://docs.docker.com/develop/develop-images/build_enhancements/
.PHONY: docker-build-dev
docker-build-dev: ## Build docker image with the manager.
	docker build -t ${IMG} -f dev.dockerfile .

.PHONY: docker-build
docker-build: ## Build docker image with the manager.
	docker build -t ${IMG} -f Dockerfile .
	docker tag ${IMG} ${IMG_LATEST}

.PHONY: docker-build-function
docker-build-function: ## Build docker image with the manager.
	docker build -t ${IMG_FUNCTION} -f proxy-function.dockerfile .
	docker tag ${IMG_FUNCTION} ${IMG_FUNCTION_LATEST}

.PHONY: docker-push-function
docker-push-function: ## Push docker image with the manager.
	crossplane xpkg push  --package-files=function-amd64.xpkg  index.docker.io/${IMG_FUNCTION}
	crossplane xpkg push  --package-files=function-amd64.xpkg  index.docker.io/${IMG_FUNCTION_LATEST}

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	docker push ${IMG}
	docker push ${IMG_LATEST}

.PHONY: release
release: fmt vet vet-function docker-build-function docker-build docker-build-function set-helm-version docker-push-function docker-push