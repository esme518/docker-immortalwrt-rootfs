#
# Dockerfile for immortalwrt-rootfs
#

FROM alpine AS builder

ARG FILE_HOST=https://downloads.immortalwrt.org/releases
ARG VERSION=24.10-SNAPSHOT

WORKDIR /builder

RUN set -ex \
    && if [ "$(uname -m)" == aarch64 ]; then \
           export TARGET='armsr/armv8'; \
       elif [ "$(uname -m)" == x86_64 ]; then \
           export TARGET='x86/64'; \
       fi \
    && apk add --update --no-cache curl \
    && export DOWNLOAD_PATH="$FILE_HOST/$VERSION/targets/$TARGET/" \
    && export DOWNLOAD_FILE=$(curl -s $DOWNLOAD_PATH | grep rootfs.tar.gz | egrep -o 'immortalwrt[^"]*rootfs.tar.gz') \
    && wget -O immortalwrt-rootfs.tar.gz "$DOWNLOAD_PATH$DOWNLOAD_FILE" \
    && mkdir rootfs \
    && tar xvf immortalwrt-rootfs.tar.gz --strip=1 --no-same-owner -C rootfs

FROM scratch AS rootfs
COPY --from=builder /builder/rootfs/ /

RUN mkdir /var/lock && \
    opkg update && \
    opkg install curl luci-app-openclash && \
    sh -c "$(curl -ksS https://raw.githubusercontent.com/sbwml/luci-app-mosdns/v5/install.sh)"

RUN uci set dhcp.lan.ignore='1' && \
    uci delete firewall.@defaults[0].syn_flood && \
    uci delete firewall.@zone[1] && \
    uci delete firewall.@forwarding[0] && \
    while uci -q delete firewall.@rule[0]; do :; done && \
    touch /etc/config/network && \
    uci -q batch <<-EOF
    set network.loopback='interface'
    set network.loopback.device='lo'
    set network.loopback.proto='static'
    set network.loopback.ipaddr='127.0.0.1'
    set network.loopback.netmask='255.0.0.0'
    set network.globals='globals'
    set network.globals.packet_steering='1'
    set network.lan='interface'
    set network.lan.device='eth0'
    set network.lan.proto='static'
    set network.lan.ipaddr='192.168.1.2'
    set network.lan.netmask='255.255.255.0'
    set network.lan.gateway='192.168.1.1'
    set network.lan.delegate='0'
EOF

RUN uci commit && \
    find /tmp -mindepth 1 -maxdepth 1 ! -name "resolv.conf" -exec rm -rf {} +

FROM scratch
COPY --from=rootfs / /

EXPOSE 80

RUN mkdir /var/lock

USER root

VOLUME /etc/config

CMD ["/sbin/init"]
