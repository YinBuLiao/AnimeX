FROM golang:1.25-alpine AS backend-build
ARG APP_VERSION=dev
WORKDIR /src
COPY go.mod go.sum ./
COPY third_party/ ./third_party/
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath \
    -ldflags="-s -w -X main.appVersion=${APP_VERSION}" \
    -o /out/bangumi-pikpak .

FROM node:22-alpine AS frontend-build
WORKDIR /src/frontend
COPY frontend/package*.json ./
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi
COPY frontend/ ./
RUN npm run build

FROM alpine:3.20
WORKDIR /app
RUN apk add --no-cache ca-certificates tzdata && mkdir -p /app/data /app/frontend/dist
COPY --from=backend-build /out/bangumi-pikpak /usr/local/bin/bangumi-pikpak
COPY --from=frontend-build /src/frontend/dist /app/frontend/dist
ENV TZ=Asia/Shanghai \
    ANIMEX_DOCKER=true \
    ANIMEX_SKIP_DB_INSTALL_STEPS=true \
    ANIMEX_MYSQL_HOST=mysql \
    ANIMEX_MYSQL_PORT=3306 \
    ANIMEX_MYSQL_DATABASE=animex \
    ANIMEX_MYSQL_USERNAME=animex \
    ANIMEX_REDIS_ADDR=redis:6379 \
    ANIMEX_REDIS_DB=0 \
    ANIMEX_STORAGE_PROVIDER=local \
    ANIMEX_LOCAL_STORAGE_PATH=/app/data/downloads
EXPOSE 8080
VOLUME ["/app/data"]
ENTRYPOINT ["bangumi-pikpak"]
CMD ["-configdb", "/app/data/animex.db", "-addr", ":8080", "-static", "/app/frontend/dist"]

