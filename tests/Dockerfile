# The Linux build and test environment, for `make test-linux` from any host.
# Same base as the CI Linux job (.github/workflows/test.yml), so a local run
# matches CI.
FROM ubuntu:24.04
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        clang make pkg-config libglib2.0-dev python3 python3-dbusmock dbus \
    && rm -rf /var/lib/apt/lists/*
