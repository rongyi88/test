#!/bin/sh
set -eu

# OpenWrt WiFi AP setup for Raspberry Pi 4.
# Copy this file to the router, edit the values below, then run:
#   sh setup-openwrt-wifi.sh

SSID="OpenWrt-Pi4"
PASSWORD="test2345"
COUNTRY="US"
RADIO="radio0"
NETWORK="lan"
LAN_IP="192.168.8.1"
LAN_NETMASK="255.255.255.0"

if [ "$(id -u)" != "0" ]; then
  echo "Please run as root: sh $0"
  exit 1
fi

if ! command -v uci >/dev/null 2>&1; then
  echo "uci not found. This script must be run on OpenWrt."
  exit 1
fi

if [ "${#PASSWORD}" -lt 8 ]; then
  echo "WiFi password must be at least 8 characters. Current length: ${#PASSWORD}"
  exit 1
fi

if ! uci -q get wireless."$RADIO" >/dev/null; then
  FOUND_RADIO="$(uci show wireless 2>/dev/null | sed -n "s/^wireless\.\(radio[0-9][0-9]*\)=wifi-device.*/\1/p" | head -n 1)"
  if [ -n "$FOUND_RADIO" ]; then
    RADIO="$FOUND_RADIO"
  else
    echo "No WiFi radio found in /etc/config/wireless."
    echo "Try running this first on OpenWrt: wifi config"
    exit 1
  fi
fi

AP_SECTION=""
for section in $(uci show wireless 2>/dev/null | sed -n "s/^wireless\.\([^=]*\)=wifi-iface.*/\1/p"); do
  mode="$(uci -q get wireless."$section".mode || true)"
  device="$(uci -q get wireless."$section".device || true)"
  if [ "$mode" = "ap" ] && [ "$device" = "$RADIO" ]; then
    AP_SECTION="$section"
    break
  fi
done

if [ -z "$AP_SECTION" ]; then
  AP_SECTION="$(uci add wireless wifi-iface)"
fi

echo "Configuring $RADIO as AP '$SSID' on network '$NETWORK'..."

echo "Configuring LAN address $LAN_IP/24 and DHCP server..."
uci set network.lan='interface'
uci set network.lan.proto='static'
uci set network.lan.ipaddr="$LAN_IP"
uci set network.lan.netmask="$LAN_NETMASK"
uci set network.lan.device='br-lan'

uci -q get network.br_lan >/dev/null || uci set network.br_lan='device'
uci set network.br_lan.name='br-lan'
uci set network.br_lan.type='bridge'

uci set dhcp.lan='dhcp'
uci set dhcp.lan.interface='lan'
uci set dhcp.lan.start='100'
uci set dhcp.lan.limit='150'
uci set dhcp.lan.leasetime='12h'
uci set dhcp.lan.ignore='0'

uci commit network
uci commit dhcp

uci set wireless."$RADIO".disabled='0'
uci set wireless."$RADIO".country="$COUNTRY"

# 2.4 GHz channel 6 / HT20 is the most compatible AP setting for first boot.
uci set wireless."$RADIO".band='2g'
uci set wireless."$RADIO".channel='6'
uci set wireless."$RADIO".htmode='HT20'

uci set wireless."$AP_SECTION".device="$RADIO"
uci set wireless."$AP_SECTION".mode='ap'
uci set wireless."$AP_SECTION".network="$NETWORK"
uci set wireless."$AP_SECTION".ssid="$SSID"
uci set wireless."$AP_SECTION".encryption='psk2'
uci set wireless."$AP_SECTION".key="$PASSWORD"
uci set wireless."$AP_SECTION".disabled='0'

uci commit wireless

/etc/init.d/network restart
/etc/init.d/dnsmasq restart
wifi reload || wifi

echo "Done."
echo "SSID: $SSID"
echo "Password: $PASSWORD"
echo "Radio: $RADIO"
echo "Network: $NETWORK"
echo "Router IP: $LAN_IP"
echo "After connecting to WiFi, ping: $LAN_IP"
