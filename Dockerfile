FROM alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6
ARG GOGDL_VERSION=3.18
ARG GOGDL_SHA256=1974f09cb0e0cdfed536937335488548addd92e5c654f4229ac22594a22f8ae0
ARG HTMLCXX_VERSION=0.87
ARG HTMLCXX_SHA256=5d38f938cf4df9a298a5346af27195fffabfef9f460fc2a02233cbcfa8fc75c8

RUN apk add --no-cache -t .dev help2man cmake make g++ curl-dev jsoncpp-dev tinyxml2-dev rhash-dev boost-dev tidyhtml-dev && \
    apk add --no-cache boost boost-program_options boost-iostreams boost-date_time jsoncpp rhash tinyxml2 curl tidyhtml && \
    curl --fail --location --retry 3 --output htmlcxx.tar.gz "https://sourceforge.net/projects/htmlcxx/files/v${HTMLCXX_VERSION}/htmlcxx-${HTMLCXX_VERSION}.tar.gz/download" && \
    echo "${HTMLCXX_SHA256}  htmlcxx.tar.gz" | sha256sum -c - && \
    tar -xvf htmlcxx.tar.gz && \
    cd htmlcxx-${HTMLCXX_VERSION} && \
    export CXXFLAGS="$CXXFLAGS -std=c++14" && \
    ./configure --prefix=/usr && \
    make && \
    make install && \
    cd / && \
    curl --fail --location --retry 3 --output lgogdownloader.tar.gz https://github.com/Sude-/lgogdownloader/releases/download/v${GOGDL_VERSION}/lgogdownloader-${GOGDL_VERSION}.tar.gz && \
    echo "${GOGDL_SHA256}  lgogdownloader.tar.gz" | sha256sum -c - && \
    tar -xvf lgogdownloader.tar.gz && \
    cd lgogdownloader-${GOGDL_VERSION} && \
    cmake . -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release && \
    make -j"$(nproc)" && \
    make install && \
    cd / && \
    rm -rf /htmlcxx* /lgogdownloader* && \
    apk del .dev && \
    # Setup wrapper to set --directory to /downloads
    mv /usr/bin/lgogdownloader /usr/bin/lgogdownloader_original && \
    printf '#!/usr/bin/env sh\n/usr/bin/lgogdownloader_original --directory /downloads "$@"' > /usr/bin/lgogdownloader && \
    chmod 755 /usr/bin/lgogdownloader && \
    # Non-root runtime: UID/GID 1000, own home and the three persistent mounts
    addgroup -g 1000 lgogdownloader && \
    adduser -D -u 1000 -G lgogdownloader -h /home/lgogdownloader -s /sbin/nologin lgogdownloader && \
    mkdir -p /config /cache /downloads /home/lgogdownloader && \
    chown -R 1000:1000 /config /cache /downloads /home/lgogdownloader

ENV HOME=/home/lgogdownloader \
    XDG_CONFIG_HOME=/config \
    XDG_CACHE_HOME=/cache
VOLUME ["/config", "/cache", "/downloads"]
USER lgogdownloader:lgogdownloader
WORKDIR /downloads
ENTRYPOINT ["/usr/bin/lgogdownloader"]
CMD ["--help"]
