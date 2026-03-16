# ─────────────────────────────────────────────
# Stage 1: Build
# ─────────────────────────────────────────────
FROM golang:1.22-alpine AS builder

RUN apk add --no-cache ca-certificates

WORKDIR /app
COPY go.mod ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-w -s" -o /stopwatch main.go

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /stopwatch /stopwatch

USER 65534:65534

EXPOSE 8080

ENTRYPOINT ["/stopwatch"]