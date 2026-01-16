FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY cmd ./cmd
RUN go build -o /out/offgrid-node ./cmd/offgrid-node

FROM alpine:3.20
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=build /out/offgrid-node /app/offgrid-node
RUN adduser -D -H -u 10001 offgrid && mkdir -p /data && chown -R offgrid:offgrid /data
USER offgrid
EXPOSE 8787
CMD ["/app/offgrid-node", "--config", "/app/config.json"]
