FROM ghcr.io/linuxserver/baseimage-alpine:3.20 as buildstage

ARG ALPINE_VERSION=3.20
ARG XRDP_PULSE_VERSION=v0.7

RUN \
  echo "**** install build deps ****" && \
  apk add --no-cache \
    alpine-sdk \
    autoconf \
    automake \
    doxygen \
    pulseaudio-dev \
    xrdp-dev \
    xorgxrdp-dev && \
  echo "**** user perms ****" && \
  useradd builder && \
  usermod -G abuild builder

USER builder

RUN \
  echo "**** grab aports ****" && \
  wget \
    https://gitlab.alpinelinux.org/alpine/aports/-/archive/${ALPINE_VERSION}-stable/aports-${ALPINE_VERSION}-stable.tar.gz \
    -O /tmp/aports.tar.gz && \
  cd /tmp && \
  tar -xf aports.tar.gz

# Otherwise meson tries to write bash completions to /root
ENV HOME=/tmp

RUN \
  echo "**** build pulseaudio from source ****" && \
  cd /tmp/aports-${ALPINE_VERSION}-stable/community/pulseaudio && \
  sed -i \
    's#https://freedesktop.org#https://www.freedesktop.org#g' \
    APKBUILD && \
  abuild fetch && \
  abuild unpack && \
  abuild deps && \
  abuild prepare && \
  VERSION=$(ls -1 /tmp/aports-${ALPINE_VERSION}-stable/community/pulseaudio/src/ | \
    awk -F '-' '/pulseaudio-/ {print $2; exit}') && \
  cd src/pulseaudio-${VERSION} && \
  meson build

RUN \
  echo "**** build pulseaudio xrdp module ****" && \
  VERSION=$(ls -1 /tmp/aports-${ALPINE_VERSION}-stable/community/pulseaudio/src/ | \
    awk -F '-' '/pulseaudio-/ {print $2; exit}') && \
  mkdir -p /tmp/buildout/usr/lib/pulse-${VERSION}/modules/ && \
  wget \
    https://github.com/neutrinolabs/pulseaudio-module-xrdp/archive/refs/tags/${XRDP_PULSE_VERSION}.tar.gz \
    -O /tmp/pulsemodule.tar.gz && \
  cd /tmp && \
  tar -xf pulsemodule.tar.gz && \
  cd pulseaudio-module-xrdp-* && \
  ./bootstrap && \
  ./configure \
    PULSE_DIR=/tmp/aports-${ALPINE_VERSION}-stable/community/pulseaudio/src/pulseaudio-${VERSION} && \
  make && \
  install -t "/tmp/buildout/usr/lib/pulse-${VERSION}/modules/" -D -m 644 src/.libs/*.so

# runtime stage
FROM ghcr.io/linuxserver/baseimage-alpine:3.20

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# copy over libs and installers from build stage
COPY --from=buildstage /tmp/buildout/ /

RUN \
  echo "**** install deps ****" && \
  apk add --no-cache \
    dbus-x11 \
    docker \
    docker-cli-compose \
    libpulse \
    mesa \
    openssh-client \
    openssl \
    pavucontrol \
    pulseaudio \
    pciutils-libs \
    sudo \
    xf86-video-ati \
    xf86-video-amdgpu \
    xf86-video-intel \
    xorg-server \
    xorgxrdp \
    xrdp \
    xterm && \
  VERSION=$(ls -1 /usr/lib/ | \
    awk -F '-' '/pulse-/ {print $2; exit}') && \
  ldconfig -n /usr/lib/pulse-${VERSION}/modules && \
  echo "**** cleanup and user perms ****" && \
  echo "abc:abc" | chpasswd && \
  usermod -s /bin/bash abc && \
  echo '%wheel ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/wheel && \
  adduser abc wheel && \
  rm -rf \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3389
VOLUME /config
