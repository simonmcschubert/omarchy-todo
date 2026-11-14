# Headless Omarchy desktop for testing the plugin without a screen.
# Hyprland runs nested inside a headless Mutter; the Omarchy shell is the real
# one from the pinned Omarchy release. See README.md, "Development".
FROM archlinux:latest

ARG OMARCHY_REF=v4.5.0

RUN pacman -Syu --noconfirm --needed \
      hyprland quickshell mutter dbus grim wtype jq git gum mesa libnotify libcap socat inotify-tools \
      python-pywayland wlr-protocols \
      qt6-base qt6-declarative qt6-svg qt6-wayland qt6-imageformats qt6-multimedia qt6-5compat \
      ttf-jetbrains-mono-nerd noto-fonts procps-ng which \
      meson ninja gcc pkgconf wayland wayland-protocols libxkbcommon \
 && git clone --depth 1 https://git.sr.ht/~brocellous/wlrctl /tmp/wlrctl \
 && meson setup /tmp/wlrctl/build /tmp/wlrctl \
 && ninja -C /tmp/wlrctl/build \
 && install -m 755 /tmp/wlrctl/build/wlrctl /usr/local/bin/wlrctl \
 && rm -rf /tmp/wlrctl \
 && (setcap -r /usr/bin/Hyprland || true) \
 && pacman -Scc --noconfirm

RUN git clone --depth 1 --branch "$OMARCHY_REF" https://github.com/basecamp/omarchy.git /opt/omarchy

COPY desktop act pointer systemd-cat /usr/local/bin/
RUN useradd -m -u 1000 dev
USER dev
WORKDIR /home/dev
CMD ["desktop"]
