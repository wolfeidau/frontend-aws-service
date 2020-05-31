FROM golang:latest as builder

MAINTAINER Mark Wolfe <mark@wolfe.id.au>

ARG BUILD_DATE
ARG GIT_HASH

WORKDIR /app
COPY go.mod go.sum ./
COPY ./vendor ./vendor
COPY ./cmd ./cmd
COPY ./internal ./internal
RUN CGO_ENABLED=0 go build -a -installsuffix cgo -ldflags='-w -s -X main.buildDate=${BUILD_DATE} -X main.commit=${GIT_HASH}' -trimpath -o service ./cmd/frontend-aws-service

FROM debian

MAINTAINER Mark Wolfe <mark@wolfe.id.au>

RUN apt update && apt install -y ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

WORKDIR /app
COPY --from=builder /app/service /service

ENTRYPOINT /service