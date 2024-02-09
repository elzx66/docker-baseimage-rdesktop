FROM ghcr.io/linuxserver/baseimage-arch:latest as buildstage

RUN \
  echo "**** install build deps ****" && \
  pacman -Sy --noconfirm \
    base-devel \
    git \
    pulseaudio \
    sudo && \
  echo "**** prep abc user ****" && \
  usermod -s /bin/bash abc && \
  echo '%abc ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/abc && \
  mkdir /buildout

USER abc:abc
RUN \
  echo "**** build AUR packages ****" && \
  cd /tmp && \
  AUR_PACKAGES="\
    xrdp \
    xorgxrdp \
    pulseaudio-module-xrdp" && \ 
  for PACKAGE in ${AUR_PACKAGES}; do \
    sudo chmod 777 -R /root && \
    git clone https://aur.archlinux.org/${PACKAGE}.git && \
    cd ${PACKAGE} && \
    makepkg -sAci --skipinteg --noconfirm && \
    sudo rm -f ${PACKAGE}-debug*pkg.tar.zst && \
    sudo -u root tar xf ${PACKAGE}-*pkg.tar.zst -C /buildout && \
    cd /tmp ;\
  done

# docker compose
FROM ghcr.io/linuxserver/docker-compose:amd64-latest as compose

# runtime stage
FROM ghcr.io/linuxserver/baseimage-arch:latest

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# copy over packages from build stage
COPY --from=buildstage /buildout/ /
COPY --from=compose /usr/local/bin/docker-compose /usr/local/bin/docker-compose

#Add needed nvidia environment variables for https://github.com/NVIDIA/nvidia-docker
ENV NVIDIA_DRIVER_CAPABILITIES="compute,video,utility"

RUN \
  echo "**** install deps ****" && \
  pacman -Sy --noconfirm --needed \
    base-devel \
    docker \
    fuse \
    git \
    imlib2 \
    lame \
    libfdk-aac \
    libjpeg-turbo \
    libxrandr \
    mesa \
    noto-fonts \
    openssh \
    pciutils \
    pulseaudio \
    sudo \
    xf86-video-ati \
    xf86-video-amdgpu \
    xf86-video-intel \
    xorg-server \
    xorg-xmessage \
    xterm && \
  echo "**** user perms ****" && \
  echo "abc:abc" | chpasswd && \
  usermod -s /bin/bash abc && \
  echo 'abc ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/abc && \
  echo "allowed_users=anybody" > /etc/X11/Xwrapper.config && \
  echo "**** build dbus-x11 ****" && \
  rm -f \
    /usr/lib/systemd/system/dbus.service \
    /usr/lib/systemd/user/dbus.service && \
  cd /tmp && \
  pacman -Rns --noconfirm -dd dbus && \
  git clone https://aur.archlinux.org/dbus-x11.git && \
  chown -R abc:abc dbus-x11 && \
  cd dbus-x11 && \
  sed -i '/check()/,+2 d' PKGBUILD && \
  sudo -u abc makepkg -sAci --skipinteg --noconfirm --needed && \
  echo "**** configure locale ****" && \
  echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
  locale-gen && \
  echo "**** cleanup ****" && \
  rm -rf \
    /tmp/* \
    /var/cache/pacman/pkg/* \
    /var/lib/pacman/sync/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3389
VOLUME /config
