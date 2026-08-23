# syntax=docker/dockerfile:1

# Official Telegram MTProxy backend image.
# Built unchanged from the same pinned commit the reference installer uses
# (f36d8af769ffaeac36978d38c2c0f6d1104c2137). Official MTProxy is x86_64-only;
# this image must run on an x86_64 host.

FROM ubuntu:24.04 AS build
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates git make gcc g++ libssl-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

ARG MTPROXY_COMMIT=f36d8af769ffaeac36978d38c2c0f6d1104c2137
RUN git clone https://github.com/TelegramMessenger/MTProxy.git /MTProxy \
    && git -C /MTProxy checkout "${MTPROXY_COMMIT}" \
    && make -C /MTProxy -j"$(nproc)"
RUN test -x /MTProxy/objs/bin/mtproto-proxy

FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl libssl3t64 zlib1g \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10002 --home-dir /nonexistent --shell /usr/sbin/nologin mtproxy
COPY --from=build /MTProxy/objs/bin/mtproto-proxy /usr/local/bin/mtproto-proxy
USER mtproxy
EXPOSE 2398 8888
ENTRYPOINT ["/usr/local/bin/mtproto-proxy"]
