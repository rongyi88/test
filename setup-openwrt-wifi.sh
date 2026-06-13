#!/bin/sh
set -eu

# OpenWrt WiFi AP setup for Raspberry Pi 4.
# Copy this file to the router, edit the values below, then run:
#   sh setup-openwrt-wifi.sh

SSID="OpenWrt-Pi4"
PASSWORD="test234"
COUNTRY="US"
RADIO="radio0"
NETWORK="lan"

if [ "$(id -u)" != "0" ]; then
  echo "Please run as root: sh $0"
  exit 1
fi

if ! command -v uci >/dev/null 2>&1; then
  echo "uci not found. This script must be run on OpenWrt."
  exit 1
fi

if [ "${#PASSWORD}" -lt 8 ]; then
  echo "WiFi password must be at least 8 characters."
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

uci set wireless."$RADIO".disabled='0'
uci set wireless."$RADIO".country="$COUNTRY"

# On Raspberry Pi 4, the onboard radio can be 2.4 GHz or 5 GHz depending on
# driver/regulatory support. Channel auto is the safest portable default.
uci set wireless."$RADIO".channel='auto'

uci set wireless."$AP_SECTION".device="$RADIO"
uci set wireless."$AP_SECTION".mode='ap'
uci set wireless."$AP_SECTION".network="$NETWORK"
uci set wireless."$AP_SECTION".ssid="$SSID"
uci set wireless."$AP_SECTION".encryption='psk2'
uci set wireless."$AP_SECTION".key="$PASSWORD"
uci set wireless."$AP_SECTION".disabled='0'

uci commit wireless

wifi reload || wifi

echo "Done."
echo "SSID: $SSID"
echo "Radio: $RADIO"
echo "Network: $NETWORK"
