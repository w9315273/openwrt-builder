FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential clang flex bison gawk \
    git gettext libncurses-dev libssl-dev \
    python3 python3-pip python3-setuptools python3-wheel \
    rsync unzip file wget \
    libelf-dev zlib1g-dev libpam0g-dev libssh-dev \
    swig qemu-utils ccache curl ca-certificates jq \
    xz-utils zstd zip time tzdata locales \
    nodejs npm && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8 && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    TZ=UTC

CMD ["/bin/bash"]