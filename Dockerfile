ARG BIN_NAME=asu-class-pingbot

FROM rust:1.94-bookworm AS builder
ARG BIN_NAME

WORKDIR /app

RUN	--mount=type=bind,source=src,target=src \
    --mount=type=bind,source=Cargo.toml,target=Cargo.toml \
    --mount=type=bind,source=Cargo.lock,target=Cargo.lock \
		--mount=type=cache,target=/app/target/ \
    --mount=type=cache,target=/var/cache/cargo \
		cargo build --locked --release \
    && cp ./target/release/$BIN_NAME /bin/$BIN_NAME

FROM debian:bookworm-slim
ARG BIN_NAME

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=ghcr.io/nushell/nushell:0.113.1-bookworm /usr/bin/nu /usr/bin/nu
COPY --from=builder /bin/$BIN_NAME /usr/local/bin/$BIN_NAME

COPY asu.nu /app/asu.nu

# Log all messages from script
ENV NU_LOG_LEVEL=DEBUG

CMD ["/app/asu.nu"]
