FROM golang:1.22-alpine AS build
WORKDIR /app
COPY go.mod ./
COPY . .
RUN go build -o server ./cmd/server

FROM alpine:3.19
COPY --from=build /app/server /server
ENTRYPOINT ["/server"]
