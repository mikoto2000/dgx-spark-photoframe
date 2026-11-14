FROM ubuntu:24.04 AS drm-probe-build

RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libc6-dev libdrm-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

COPY drm-probe.c /src/drm-probe.c
RUN cc -Wall -Wextra -Werror /src/drm-probe.c -o /drm-probe \
    $(pkg-config --cflags --libs libdrm)

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       libdrm2 mpv \
    && rm -rf /var/lib/apt/lists/*

COPY --from=drm-probe-build /drm-probe /usr/local/bin/drm-probe
COPY entrypoint.sh entrypoint.sh
COPY drm-selection.sh drm-selection.sh

RUN chmod +x entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
