# Build from the repository root:
#   docker build -f deploy/Dockerfile -t arcanum-server .
FROM rust:1-bookworm AS build
WORKDIR /src
COPY core core
COPY server server
# Migrations are embedded at compile time (sqlx::migrate!).
RUN cargo build --release --locked --manifest-path server/Cargo.toml

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --no-create-home pm
COPY --from=build /src/server/target/release/arcanum-server /usr/local/bin/arcanum-server
USER pm
ENV BIND_ADDR=0.0.0.0:8080 RUST_LOG=info
EXPOSE 8080
ENTRYPOINT ["arcanum-server"]
