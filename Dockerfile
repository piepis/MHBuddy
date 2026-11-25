# Local image for MH伙伴助手: Flutter web, the Go API, and fixture content.
# Flutter 3.50.1 is the stable release that satisfies apps/web (Dart >=3.14, Flutter >=3.47).
# This image turns on dev sign-in. Do not put it on a public host.

FROM ubuntu:24.04 AS web
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*
ARG FLUTTER_VERSION=3.50.1
RUN curl -fsSL -o /tmp/flutter.tar.xz \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
 && mkdir -p /opt \
 && tar -C /opt -xf /tmp/flutter.tar.xz \
 && rm /tmp/flutter.tar.xz
ENV PATH="/opt/flutter/bin:${PATH}"
ENV FLUTTER_SUPPRESS_ANALYTICS=true
RUN git config --global --add safe.directory /opt/flutter \
 && flutter config --no-analytics --no-cli-animations --enable-web \
 && flutter precache --web
WORKDIR /src
COPY packages/catalog packages/catalog
COPY packages/builds packages/builds
COPY packages/player_store packages/player_store
COPY apps/web apps/web
WORKDIR /src/apps/web
RUN flutter pub get \
 && flutter build web --release --pwa-strategy=none --no-web-resources-cdn

FROM golang:1.22-bookworm AS api
WORKDIR /src/services/api
COPY services/api/go.mod services/api/go.sum ./
RUN go mod download
COPY services/api/ ./
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/mhbuddy ./cmd/mhbuddy

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --home /app --shell /usr/sbin/nologin mhbuddy
WORKDIR /app
COPY --from=api /out/mhbuddy /app/mhbuddy
COPY --from=web /src/apps/web/build/web /app/apps/web/build/web
COPY content/fixtures /app/content/fixtures
COPY services/api/migrations /app/services/api/migrations
COPY docs/GROK_BUILD_SPEC.md /app/docs/GROK_BUILD_SPEC.md
COPY apps/web/fonts/NotoSansSC-400.ttf /app/apps/web/fonts/NotoSansSC-400.ttf
COPY tools/docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod 755 /app/mhbuddy /app/docker-entrypoint.sh
ENV CONTENT_DIR=/app/content/fixtures \
    WEB_ROOT=/app/apps/web/build/web \
    PORT=8080 \
    MH_DEV_AUTH=1 \
    MH_ADMINS=hunter-a
EXPOSE 8080
USER mhbuddy
ENTRYPOINT ["/app/docker-entrypoint.sh"]
