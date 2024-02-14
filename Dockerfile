# syntax=docker/dockerfile:1.3

FROM alpine:latest

LABEL org.opencontainers.image.title="Docker VPN Hotspot" \
      org.opencontainers.image.description="A docker image to setup a wireless access point with VPN tunelling" \
      org.opencontainers.image.version="0.0.1" \
      org.opencontainers.image.url="https://hub.docker.com/r/diptanw/vpn-hotspot" \
      org.opencontainers.image.authors="Volodymyr D. <25989266+diptanw@users.noreply.github.com >" \
      org.opencontainers.image.source="https://github.com/diptanw/rpi-server/vpn-hotspot"

RUN --mount=type=cache,target=/var/cache/apk apk add --no-cache \
    bash hostapd iptables dhcp docker-cli iw

RUN touch /var/lib/dhcp/dhcpd.leases
ADD hotspot.sh /bin/hotspot

ENTRYPOINT [ "hotspot" ]