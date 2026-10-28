FROM golang:1.26.2-alpine AS builder

WORKDIR /src
RUN apk add --no-cache git ca-certificates

COPY go.work go.work.sum ./
COPY contracts-repo ./contracts-repo
COPY apps-repo ./apps-repo
COPY services-repo ./services-repo

WORKDIR /src/services-repo/services/ceerat-user-service
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /bin/ceerat-user-service .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /bin/dbbootstrap ./cmd/dbbootstrap

FROM alpine:3.20

RUN apk --no-cache add ca-certificates bash postgresql-client
WORKDIR /app
COPY --from=builder /bin/ceerat-user-service /app/ceerat-user-service
COPY --from=builder /bin/dbbootstrap /app/bin/dbbootstrap
COPY services-repo/services/ceerat-user-service/scripts/db-*.sh /app/scripts/
COPY services-repo/services/ceerat-user-service/migrations /app/migrations
# Alpine supplies sha256sum; retain the canonical migration checksum algorithm.
RUN sed -i 's/shasum -a 256/sha256sum/g' /app/scripts/db-migrate.sh

EXPOSE 50051
CMD ["/app/ceerat-user-service"]
