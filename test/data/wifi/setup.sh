#!/bin/sh

# Sourced inside test containers (with test/lib.sh) to fake a host with a wifi
# interface: ip, iwlist, ifup and ifdown are replaced by stubs that log their
# calls to $MOCK_LOG. The wifi interface is $WIFI_IF (default: wlan0), the
# network in range is $WIFI_INRANGE (default: IEEE). When /tmp/wifi.connected
# exists, the interface has a global address. /etc/network/interfaces starts as
# a copy of test/data/wifi/interfaces.

WIFI_IF=${WIFI_IF-wlan0}
WIFI_INRANGE=${WIFI_INRANGE:-IEEE}

stub_bin ip "printf '%s\\n' \"ip \$*\" >> $MOCK_LOG
case \"\$*\" in
    'link show')
        printf '1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536\\n'
        printf '2: eth0@if12: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500\\n'
        [ -n '$WIFI_IF' ] && printf '3: %s: <BROADCAST,MULTICAST> mtu 1500\\n' '$WIFI_IF'
        ;;
    'address show dev '*)
        if [ -f /tmp/wifi.connected ]; then
            printf '    inet 192.168.1.5/24 brd 192.168.1.255 scope global %s\\n' '$WIFI_IF'
        fi
        ;;
esac
exit 0"
stub_bin iwlist "printf '%s\\n' \"iwlist \$*\" >> $MOCK_LOG
printf '          ESSID:\"%s\"\\n' '$WIFI_INRANGE'"
for _cmd in ifup ifdown; do
    stub_bin "$_cmd" "printf '%s\\n' \"$_cmd \$*\" >> $MOCK_LOG"
done

mkdir -p /etc/network
cp /primer/test/data/wifi/interfaces /etc/network/interfaces
