#!/bin/sh
set -eu

# Open OpenWrt management ports from the WiFi client/WAN side.
# Run on OpenWrt as root:
#   sh open-openwrt-management-ports.sh

RULE_NAME="Allow-Manage-from-WAN"
WWAN_NETWORK="wwan"
WAN_ZONE="wan"

if [ "$(id -u)" != "0" ]; then
  echo "Please run as root: sh $0"
  exit 1
fi

if ! command -v uci >/dev/null 2>&1; then
  echo "uci not found. This script must be run on OpenWrt."
  exit 1
fi

delete_rule_by_name() {
  name="$1"

  while true; do
    section="$(uci show firewall 2>/dev/null \
      | grep "name='$name'" \
      | head -n 1 \
      | cut -d. -f2 || true)"

    [ -n "$section" ] || break
    uci delete "firewall.${section}"
  done
}

find_zone_section_by_name() {
  name="$1"

  for section in $(uci show firewall 2>/dev/null | sed -n "s/^firewall\.\([^=]*\)=zone.*/\1/p"); do
    zone_name="$(uci -q get firewall."$section".name || true)"
    if [ "$zone_name" = "$name" ]; then
      echo "$section"
      return 0
    fi
  done

  return 1
}

echo "Cleaning old rule: $RULE_NAME"
delete_rule_by_name "$RULE_NAME"

WAN_SECTION="$(find_zone_section_by_name "$WAN_ZONE" || true)"
if [ -z "$WAN_SECTION" ]; then
  echo "Firewall zone '$WAN_ZONE' was not found."
  echo "Check with: uci show firewall | grep -E \"=zone|\\.name=\""
  exit 1
fi

echo "Ensuring network '$WWAN_NETWORK' is covered by zone '$WAN_ZONE'"
uci -q del_list firewall."$WAN_SECTION".network="$WWAN_NETWORK" || true
uci add_list firewall."$WAN_SECTION".network="$WWAN_NETWORK"

echo "Opening TCP ports 22, 80, 443 from zone '$WAN_ZONE' to this router"
uci add firewall rule >/dev/null
uci set firewall.@rule[-1].name="$RULE_NAME"
uci set firewall.@rule[-1].src="$WAN_ZONE"
uci set firewall.@rule[-1].family='ipv4'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='22 80 443'
uci set firewall.@rule[-1].target='ACCEPT'

uci commit firewall
/etc/init.d/firewall restart

if uci -q get uhttpd.main >/dev/null; then
  echo "Configuring uhttpd to listen on all addresses"
  uci -q delete uhttpd.main.listen_http || true
  uci add_list uhttpd.main.listen_http='0.0.0.0:80'
  uci add_list uhttpd.main.listen_http='[::]:80'
  uci -q delete uhttpd.main.listen_https || true
  uci add_list uhttpd.main.listen_https='0.0.0.0:443'
  uci add_list uhttpd.main.listen_https='[::]:443'
  uci commit uhttpd
  /etc/init.d/uhttpd enable
  /etc/init.d/uhttpd restart
else
  echo "uhttpd config not found. Install LuCI/uhttpd if the web UI is missing:"
  echo "  opkg update"
  echo "  opkg install luci"
fi

if [ -x /etc/init.d/dropbear ]; then
  echo "Restarting dropbear SSH"
  /etc/init.d/dropbear enable
  /etc/init.d/dropbear restart
else
  echo "dropbear init script not found; SSH may not be installed."
fi

echo "Done."
echo "Check listeners with:"
echo "  netstat -lntp | grep -E '(:22|:80|:443)'"
