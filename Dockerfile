FROM golang:latest as builder

MAINTAINER Mark Wolfe <mark@wolfe.id.au>

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY ./cmd ./cmd
COPY ./pkg ./pkg
RUN CGO_ENABLED=0 go build -a -installsuffix cgo -o service ./cmd/frontend-aws-service

FROM debian

MAINTAINER Mark Wolfe <mark@wolfe.id.au>

RUN apt update && apt install -y ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

WORKDIR /app
COPY --from=builder /app/service /service

ENTRYPOINT /service