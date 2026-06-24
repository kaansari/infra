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

FROM alpine:3.20

RUN apk --no-cache add ca-certificates
WORKDIR /app
COPY --from=builder /bin/ceerat-user-service /app/ceerat-user-service

EXPOSE 50051
CMD ["/app/ceerat-user-service"]
