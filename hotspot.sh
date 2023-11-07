#!/bin/bash -e

# Default values
: ${INTERFACE:=wlan0}
: ${SUBNET:=192.168.254.0}
: ${AP_ADDR:=192.168.254.1}
: ${SSID:=docker-ap}
: ${CHANNEL:=36}
: ${WPA_PASSPHRASE:=passw0rd}
: ${HW_MODE:=a}
: ${DRIVER:=nl80211}
: ${DNS_ADDRESSES:=1.1.1.1}
: ${OUTGOINGS:=tun0}

function setup_interface() {
    if ip a | grep -q "${INTERFACE}"; then
        echo "Interface exists. No need to retrieve again"
    else
        echo "Attaching ${INTERFACE} interface to container"

        # Determine the container ID that has the overlay file system
        local overlay_id=$(grep -i overlay /proc/self/mountinfo | sed -n "s/.*upperdir=\(.*\)\/diff.*/\1/p")
        local container_id=$(docker ps -aq | xargs docker inspect --format '{{.ID}} {{.GraphDriver.Data.MergedDir}}' | grep "$overlay_id" | cut -d ' ' -f1)

        if [ -z "$container_id" ]; then
            echo "[Error] Not found this docker container"
            exit 1
        fi

        local container_pid=$(docker inspect --format '{{.State.Pid}}' $container_id)
        local container_image=$(docker inspect --format '{{.Config.Image}}' $container_id)

        # Move the WLAN interface to the container's network namespace
        docker run -t --privileged --net=host --pid=host --rm --entrypoint /bin/sh $container_image -c "
            PHY=\$(echo phy\$(iw dev $INTERFACE info | grep wiphy | awk '{print \$2}'))
            iw phy \$PHY set netns $container_pid
        "

        echo "$INTERFACE attached to $container_image:$container_id"
    fi

    echo "Setting interface $INTERFACE"
    
    rfkill unblock wlan
    ip a | grep -Eq ": $INTERFACE:.*state UP" && ip link set $INTERFACE down && echo "Down $INTERFACE ..."

    ip link set $INTERFACE name $INTERFACE
    ip link set $INTERFACE up
    ip addr flush dev $INTERFACE
    ip addr add $AP_ADDR/24 dev $INTERFACE
    ip rule add from all lookup main suppress_prefixlength 0
}

function setup_hostapd() {
    cat > "/etc/hostapd.conf" <<-EOF
interface=$INTERFACE
driver=$DRIVER
ssid=$SSID
hw_mode=$HW_MODE
channel=$CHANNEL
wpa=2
wpa_passphrase=$WPA_PASSPHRASE
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP CCMP
rsn_pairwise=CCMP
wpa_ptk_rekey=600
macaddr_acl=0
ignore_broadcast_ssid=0
wmm_enabled=1
ieee80211ac=1
require_vht=1
ieee80211d=0
ieee80211h=0
EOF
}

function setup_dhcp() {
    cat > "/etc/dhcp/dhcpd.conf" <<-EOF
option domain-name-servers $DNS_ADDRESSES;
option subnet-mask 255.255.255.0;
option routers $AP_ADDR;
subnet $SUBNET netmask 255.255.255.0 {
    range ${SUBNET::-1}100 ${SUBNET::-1}200;
}
EOF

    dhcpd $INTERFACE
}

function setup_nat() {
    echo "Initializing routing"
    echo "NAT settings ip_dynaddr, ip_forward"
    sysctl -w net.ipv4.ip_dynaddr=1
    sysctl -w net.ipv4.ip_forward=1

    for int in $(echo $OUTGOINGS | tr ',' ' '); do
        echo "Setting iptables for outgoing traffics on $int..."
        iptables -D FORWARD -i $INTERFACE -o $int -j ACCEPT 2>/dev/null || true
        iptables -A FORWARD -i $INTERFACE -o $int -j ACCEPT
        iptables -D FORWARD -i $int -o $INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
        iptables -A FORWARD -i $int -o $INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
        iptables -t nat -D POSTROUTING -s ${SUBNET}/24 -o $int -j MASQUERADE 2>/dev/null || true
        iptables -t nat -A POSTROUTING -s ${SUBNET}/24 -o $int -j MASQUERADE
    done

    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
}

sleep 3

echo "External IP Address: $(wget http://ipecho.net/plain -O - -q ; echo)"

setup_hostapd
setup_interface
setup_nat
setup_dhcp

/usr/sbin/hostapd /etc/hostapd.conf
