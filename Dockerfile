FROM golang:1.26-alpine AS build
WORKDIR /app
COPY go.mod ./
COPY . .
RUN go build -o server ./cmd/server

FROM alpine:3.23
RUN adduser -D -H -s /sbin/nologin appuser
COPY --from=build /app/server /server
USER appuser
ENTRYPOINT ["/server"]