FROM rust:1.94-bookworm AS builder

WORKDIR /app

COPY Cargo.toml Cargo.lock ./
COPY src ./src

RUN cargo build --locked --release

FROM debian:bookworm

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/target/release/asu-class-lookup /usr/local/bin/asu-class-pingbot
COPY --from=ghcr.io/nushell/nushell:0.113.1-bookworm /usr/bin/nu /usr/bin/nu

COPY asu.nu /app/asu.nu
# COPY docker/crontab /etc/cron.d/class-checker-cron-job


# RUN chmod 0644 /etc/cron.d/class-checker-cron-job \
#   && crontab /etc/cron.d/class-checker-cron-job

# # Create your log file
# RUN touch /var/log/cron.log

CMD ["/app/asu.nu"]
