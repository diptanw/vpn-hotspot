# VPN Hotspot Access Point

A docker image to setup a wireless access point with VPN tunelling to work primarally on raspberry Pi.

Implementation is borrowed from https://github.com/sdelrio/rpi-hostap with a few fixes to ip routing.

## Build

To build an image you need docker installed:

```sh
docker build -t diptanw/vpn-hotspot:latest .
```

## Run

To run container:

```sh
sudo docker run --rm -d -t \
  -e INTERFACE=wlan0 \
  -e CHANNEL=6 \
  -e SSID=hotspot \
  -e AP_ADDR=192.168.254.1 \
  -e SUBNET=192.168.254.0 \
  -e WPA_PASSPHRASE=qwerty123 \
  -e OUTGOINGS=tun0 \
  --privileged \
  --net host \
  diptanw/vpn-hotspot:latest
```

An example of an access point that routes all connected clients via wireguard VPN interface:

```
version: "3.7"
services:
  gluetun:
    image: qmcgaw/gluetun:v3
    expose:
      - 8888/tcp # HTTP proxy
    environment:
      VPN_SERVICE_PROVIDER: custom
      VPN_TYPE: wireguard
      WIREGUARD_ENDPOINT_IP: ${WIREGUARD_ENDPOINT_IP}
      WIREGUARD_ENDPOINT_PORT: ${WIREGUARD_ENDPOINT_PORT}
      WIREGUARD_PUBLIC_KEY: ${WIREGUARD_PUBLIC_KEY}
      WIREGUARD_PRIVATE_KEY: ${WIREGUARD_PRIVATE_KEY}
      WIREGUARD_PRESHARED_KEY: ${WIREGUARD_PRESHARED_KEY}
      WIREGUARD_ADDRESS: ${WIREGUARD_ADDRESS}
      HTTPPROXY: on
      SHADOWSOCKS: off
      SHADOWSOCKS_PASSWORD:
      TZ: Europe/Stockholm
      DOT: off
      HTTP_CONTROL_SERVER_LOG: off
      FIREWALL: on
      UPDATER_PERIOD: 3h
    sysctls:
      - net.ipv4.ip_forward=1
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE

  hotspot:
    build:
      context: .
    image: diptanw/vpn-hotspot:latest
    network_mode: "service:gluetun"
    depends_on:
      - gluetun
    privileged: true
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv6.conf.all.disable_ipv6=1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      INTERFACE: wlan0
      OUTGOINGS: tun0
      WPA_PASSPHRASE: ${SERVER_ADMIN_PSK}
      SSID: hotspot
    restart: unless-stopped
```