STAGE ?= dev
BRANCH ?= master

VERSION := 1.0.0
GIT_HASH := $(shell git rev-parse --short HEAD)

APP_NAME ?= frontend-aws-service

GOLANGCI_VERSION = 1.27.0

default: deploy-common deploy-assets deploy-cluster deploy-echo-service-ecr push-docker-container deploy-echo-service
.PHONY: default

bin/golangci-lint: bin/golangci-lint-${GOLANGCI_VERSION}
	@ln -sf golangci-lint-${GOLANGCI_VERSION} bin/golangci-lint
bin/golangci-lint-${GOLANGCI_VERSION}:
	@curl -sfL https://install.goreleaser.com/github.com/golangci/golangci-lint.sh | BINARY=golangci-lint bash -s -- v${GOLANGCI_VERSION}
	@mv bin/golangci-lint $@

bin/reflex:
	env GOBIN=$$PWD/bin GO111MODULE=on go install github.com/cespare/reflex

bin/hey:
	env GOBIN=$$PWD/bin GO111MODULE=on go install github.com/rakyll/hey

bin/gcov2lcov:
	@env GOBIN=$$PWD/bin GO111MODULE=on go install github.com/jandelgado/gcov2lcov

lint: bin/golangci-lint
	@echo "--- lint all the things"
	@bin/golangci-lint run
.PHONY: lint

test: bin/gcov2lcov
	@echo "--- test all the things"
	@go test -v -covermode=count -coverprofile=coverage.txt ./cmd/... ./internal/...
	@bin/gcov2lcov -infile=coverage.txt -outfile=coverage.lcov
.PHONY: test

watch: bin/reflex
	bin/reflex -R '^static/' -r '(.go$$)|(.html$$)' -s -- go run cmd/frontend-aws-service/main.go
.PHONY: watch

deploy-common:
	@echo "--- deploy alert stack to aws"
	@aws cloudformation deploy \
		--no-fail-on-empty-changeset \
		--template-file infra/operations/alert.yaml \
		--capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
		--stack-name $(APP_NAME)-alert-$(STAGE)-$(BRANCH) \
		--tags "environment=$(STAGE)" "branch=$(BRANCH)" "service=$(APP_NAME)" "owner=$(USER)" \
		--parameter-overrides Email=$(ALERT_EMAIL_ADDRESS)

	@echo "--- deploy public zone stack to aws"
	@aws cloudformation deploy \
		--no-fail-on-empty-changeset \
		--template-file infra/vpc/zone-public.yaml \
		--capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
		--stack-name $(APP_NAME)-public-zone-$(STAGE)-$(BRANCH) \
		--tags "environment=$(STAGE)" "branch=$(BRANCH)" "service=$(APP_NAME)" "owner=$(USER)" \
		--parameter-overrides Name=$(DOMAIN_NAME)
.PHONY: deploy-common

deploy-assets:
	@echo "--- deploy cflogs s3 stack to aws"
	@aws cloudformation deploy \
		--no-fail-on-empty-changeset \
		--template-file infra/state/s3.yaml \
		--capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
		--stack-name $(APP_NAME)-cflogs-s3-$(STAGE)-$(BRANCH) \
		--tags "environment=$(STAGE)" "branch=$(BRANCH)" "service=$(APP_NAME)" "owner=$(USER)" \
		--parameter-overrides Access=CloudFrontAccessLogWrite

	@echo "--- deploy assets static website stack to aws"
	@aws cloudformation deploy \
		--no-fail-on-empty-changeset \
		--template-file infra/static-website/static-website.yaml \
		--capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
		--stack-name $(APP_NAME)-assets-static-website-$(STAGE)-$(BRANCH) \
		--tags "environment=$(STAGE)" "branch=$(BRANCH)" "service=$(APP_NAME)" "owner=$(USER)" \
		--parameter-overrides ParentZoneStack=$(APP_NAME)-public-zone-$(STAGE)-$(BRANCH) \
			ParentAlertStack=$(APP_NAME)-alert-$(STAGE)-$(BRANCH) \
			ParentS3StackAccessLog=$(APP_NAME)-cflogs-s3-$(STAGE)-$(BRANCH) \
			DefaultRootObject="" SubDomainNameWithDot=assets. CertificateType=CreateAcmCertificate EnableRedirectSubDomainName=true
.PHONY: deploy-assets

deploy-cluster:
	@echo "--- deploy alert stack to aws"
	@aws cloudformation deploy \
		--no-fail-on-empty-changeset \
		--template-file infra/fargate/cluster.yaml \
		--capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
		--stack-name $(APP_NAME)-ecs-cluster-$(STAGE)-$(BRANCH) \
		--tags "environment=$(STAGE)" "branch=$(BRANCH)" "service=$(APP_NAME)" "owner=$(USER)"

	@echo "--- deploy ecs cluster vpc stack to aws"
	@aws cloudformation deploy \
		--no-fail-on-empty-changeset \
		--template-file infra/vpc/vpc-2azs.yaml \
		--capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
		--stack-name $(APP_NAME)-ecs-cluster-vpc-$(STAGE)-$(BRANCH) \
		--tags "environment=$(STAGE)" "branch=$(BRANCH)" "service=$(APP_NAME)" "owner=$(USER)"

	@echo "--- deploy ecs cluster vpc flowlogs stack to aws"
	@aws cloudformation deploy \
		--no-fail-on-empty-changeset \
		--template-file infra/vpc/vpc-flow-logs-s3.yaml \
		--capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
		--stack-name $(APP_NAME)-ecs-cluster-vpc-flowlogs-$(STAGE)-$(BRANCH) \
		--tags "environment=$(STAGE)" "branch=$(BRANCH)" "service=$(APP_NAME)" "owner=$(USER)" \
		--parameter-overrides ParentVPCStack="$(APP_NAME)-ecs-cluster-vpc-$(STAGE)-$(BRANCH)"

	@echo "--- deploy ecs cluster alblogs s3 stack to aws"
	@aws cloudformation deploy \
		--no-fail-on-empty-changeset \
		--template-file infra/state/s3.yaml \
		--capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
		--stack-name $(APP_NAME)-ecs-cluster-alblogs-$(STAGE)-$(BRANCH) \
		--tags "environment=$(STAGE)" "branch=$(BRANCH)" "service=$(APP_NAME)" "owner=$(USER)" \
		--parameter-overrides Access=ElbAccessLogWrite
.PHONY: deploy-cluster

deploy-echo-service-ecr:
	@echo "--- deploy echo service ecr stack to aws"
	@aws cloudformation deploy \
		--no-fail-on-empty-changeset \
		--template-file infra/fargate/ecr.yaml \
		--capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
		--stack-name $(APP_NAME)-echo-service-ecr-$(STAGE)-$(BRANCH) \
		--tags "environment=$(STAGE)" "branch=$(BRANCH)" "service=$(APP_NAME)" "owner=$(USER)" \
		--parameter-overrides TagPrefix=echo-service
.PHONY: deploy-echo-service-ecr

build-docker-container:
	@echo "--- build docker container $(APP_NAME)"
	@go mod vendor
	@docker build --build-arg BUILD_DATE=$(shell date -u '+%Y-%m-%dT%H:%M:%SZ') \
		--build-arg GIT_HASH=$(GIT_HASH) \
		-t $(APP_NAME) .
.PHONY: build-docker-container

push-docker-container:
	@echo "--- create and push container to ecr"
	$(eval REPOSITORY_URI=$(shell aws cloudformation list-exports --query 'Exports[?Name==`$(APP_NAME)-echo-service-ecr-$(STAGE)-$(BRANCH)-ECRHostname`].Value' --output text))
	aws ecr get-login-password | docker login --username AWS --password-stdin $(REPOSITORY_URI)
	@echo "Tagging image: ${REPOSITORY_URI}:$(VERSION)_$(GIT_HASH)"
	@docker tag $(APP_NAME) $(REPOSITORY_URI):$(VERSION)_$(GIT_HASH)
	@docker push $(REPOSITORY_URI):$(VERSION)_$(GIT_HASH)
	@echo "Pushed container ${REPOSITORY_URI}"
.PHONY: push-docker-container

deploy-echo-service:
	@echo "--- deploy echo service stack to aws"
	$(eval ASSETS_BUCKET=$(shell aws cloudformation list-exports --query 'Exports[?Name==`$(APP_NAME)-assets-static-website-$(STAGE)-$(BRANCH)-BucketName`].Value' --output text))
	$(eval REPOSITORY_URI=$(shell aws cloudformation list-exports --query 'Exports[?Name==`$(APP_NAME)-echo-service-ecr-$(STAGE)-$(BRANCH)-ECRHostname`].Value' --output text))
	@aws cloudformation deploy \
		--no-fail-on-empty-changeset \
		--template-file infra/fargate/service-dedicated-alb.yaml \
		--capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
		--stack-name $(APP_NAME)-echo-service-dedicated-alb-$(STAGE)-$(BRANCH) \
		--tags "environment=$(STAGE)" "branch=$(BRANCH)" "service=$(APP_NAME)" "owner=$(USER)" \
		--parameter-overrides ParentVPCStack="$(APP_NAME)-ecs-cluster-vpc-$(STAGE)-$(BRANCH)" \
			ParentAlertStack=$(APP_NAME)-alert-$(STAGE)-$(BRANCH) \
			ParentClusterStack=$(APP_NAME)-ecs-cluster-$(STAGE)-$(BRANCH) \
			ParentZoneStack=$(APP_NAME)-public-zone-$(STAGE)-$(BRANCH) \
			ParentS3StackAccessLog=$(APP_NAME)-ecs-cluster-alblogs-$(STAGE)-$(BRANCH) \
			AppPort=8000 AppEnvironment1Key=S3_BUCKET AppEnvironment1Value=$(ASSETS_BUCKET) \
			TaskPolicies=arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess \
			AppImage=${REPOSITORY_URI}:$(VERSION)_$(GIT_HASH) \
			SubDomainNameWithDot=console.
.PHONY: deploy-echo-service
