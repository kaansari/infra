FROM golang:1.26.2-alpine AS builder

WORKDIR /src
RUN apk add --no-cache git ca-certificates

COPY go.work go.work.sum ./
COPY contracts-repo ./contracts-repo
COPY services-repo ./services-repo
COPY apps-repo ./apps-repo

RUN cd /src/apps-repo/ai/ceerat-agent-service && go mod download && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /bin/ceerat-agent-service .
RUN cd /src/apps-repo/apps/ceerat-web-ui && go mod download && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /bin/ceerat-web-ui .
RUN cd /src/apps-repo/apps/ceerat-admin-ui && go mod download && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /bin/ceerat-admin-ui .
RUN cd /src/apps-repo/apps/ceerat-customer-ui && go mod download && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /bin/ceerat-customer-ui .

FROM alpine:3.20

RUN apk --no-cache add ca-certificates
WORKDIR /app
COPY --from=builder /bin/ceerat-agent-service /usr/local/bin/ceerat-agent-service
COPY --from=builder /bin/ceerat-web-ui /usr/local/bin/ceerat-web-ui
COPY --from=builder /bin/ceerat-admin-ui /usr/local/bin/ceerat-admin-ui
COPY --from=builder /bin/ceerat-customer-ui /usr/local/bin/ceerat-customer-ui
COPY apps-repo/apps/ceerat-web-ui/web /app/ceerat-web-ui/web
COPY apps-repo/apps/ceerat-admin-ui/web /app/ceerat-admin-ui/web
COPY apps-repo/apps/ceerat-customer-ui/web /app/ceerat-customer-ui/web

EXPOSE 3000 3005 3010 8088
