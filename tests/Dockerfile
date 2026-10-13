# The Linux build and test environment, for `make test-linux` from any host.
FROM debian:trixie
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        clang make pkg-config libglib2.0-dev python3 python3-dbusmock dbus \
    && rm -rf /var/lib/apt/lists/*
