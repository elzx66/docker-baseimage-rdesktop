FROM ghcr.io/linuxserver/baseimage-arch:latest AS buildstage

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
    sed -i \
      's#https://freedesktop.org#https://www.freedesktop.org#g' \
      PKGBUILD && \
    makepkg -sAci --skipinteg --noconfirm && \
    sudo rm -f ${PACKAGE}-debug*pkg.tar.zst && \
    sudo -u root tar xf ${PACKAGE}-*pkg.tar.zst -C /buildout && \
    cd /tmp ;\
  done

# docker compose
FROM ghcr.io/linuxserver/docker-compose:amd64-latest AS compose

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
ENV NVIDIA_DRIVER_CAPABILITIES="all" \
    HOME=/config

RUN \
  echo "**** enable locales ****" && \
  sed -i \
    '/locale/d' \
    /etc/pacman.conf && \
  echo "**** install deps ****" && \
  pacman -Sy --noconfirm --needed \
    base-devel \
    docker \
    fuse \
    git \
    hicolor-icon-theme \
    imlib2 \
    intel-media-driver \
    lame \
    libfdk-aac \
    libjpeg-turbo \
    libxrandr \
    libva-mesa-driver \
    mesa \
    mesa-libgl \
    noto-fonts \
    noto-fonts-emoji \
    openbox \
    openssh \
    pciutils \
    pulseaudio \
    sudo \
    vulkan-extra-layers \
    vulkan-intel \
    vulkan-radeon \
    vulkan-swrast \
    vulkan-tools \
    xf86-video-amdgpu \
    xf86-video-ati \
    xf86-video-intel \
    xf86-video-nouveau \
    xf86-video-qxl \
    xorg-server \
    xorg-xmessage \
    xterm && \
  pacman -Sy --noconfirm \
    glibc && \
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
  echo "**** openbox tweaks ****" && \
  sed -i \
    -e 's/NLIMC/NLMC/g' \
    -e 's|</applications>|  <application class="*"><maximized>yes</maximized></application>\n</applications>|' \
    -e 's|</keyboard>|  <keybind key="C-S-d"><action name="ToggleDecorations"/></keybind>\n</keyboard>|' \
    /etc/xdg/openbox/rc.xml && \
  echo "**** proot-apps ****" && \
  mkdir /proot-apps/ && \
  PAPPS_RELEASE=$(curl -sX GET "https://api.github.com/repos/linuxserver/proot-apps/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]') && \
  curl -L https://github.com/linuxserver/proot-apps/releases/download/${PAPPS_RELEASE}/proot-apps-x86_64.tar.gz \
    | tar -xzf - -C /proot-apps/ && \
  echo "${PAPPS_RELEASE}" > /proot-apps/pversion && \
  echo "**** configure locale ****" && \
  for LOCALE in $(curl -sL https://raw.githubusercontent.com/thelamer/lang-stash/master/langs); do \
    localedef -i $LOCALE -f UTF-8 $LOCALE.UTF-8; \
  done && \
  echo "**** theme ****" && \
  curl -s https://raw.githubusercontent.com/thelamer/lang-stash/master/theme.tar.gz \
    | tar xzvf - -C /usr/share/themes/Clearlooks/openbox-3/ && \
  echo "**** cleanup ****" && \
  pacman -Rsn --noconfirm \
    git \
    $(pacman -Qdtq) && \
  rm -rf \
    /tmp/* \
    /var/cache/pacman/pkg/* \
    /var/lib/pacman/sync/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3389
VOLUME /config
