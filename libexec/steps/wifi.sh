#!/usr/bin/env sh

# Locale on system
PRIMER_STEP_WIFI_INTERFACE=${PRIMER_STEP_WIFI_INTERFACE:-}

PRIMER_STEP_WIFI_ESSID=${PRIMER_STEP_WIFI_ESSID:-}

PRIMER_STEP_WIFI_PSK=${PRIMER_STEP_WIFI_PSK:-}

PRIMER_STEP_WIFI_PIDFILE=/run/wpa_supplicant.pid
PRIMER_STEP_WIFI_CFDIR=/etc/wpa_supplicant

primer_step_wifi() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    --interface)
                        PRIMER_STEP_WIFI_INTERFACE="$2"; shift 2;;
                    --essid | --network)
                        PRIMER_STEP_WIFI_ESSID="$2"; shift 2;;
                    --psk | --password | --key)
                        PRIMER_STEP_WIFI_PSK="$2"; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            [ -z "$PRIMER_STEP_WIFI_INTERFACE" ] && _primer_step_wifi_interface
            if [ -n "$PRIMER_STEP_WIFI_ESSID" ]; then
                $PRIMER_OS_SUDO ip link set "$PRIMER_STEP_WIFI_INTERFACE" up
                if command -v iwlist >/dev/null; then
                    if $PRIMER_OS_SUDO iwlist "$PRIMER_STEP_WIFI_INTERFACE" scan | grep "ESSID:" | grep -q "$PRIMER_STEP_WIFI_ESSID"; then
                        yush_info "$PRIMER_STEP_WIFI_ESSID is in range"
                    else
                        yush_warn "$PRIMER_STEP_WIFI_ESSID seems not in range"
                    fi
                fi
                if ip address show dev "$PRIMER_STEP_WIFI_INTERFACE" | grep "inet" | grep "$PRIMER_STEP_WIFI_INTERFACE" | grep -q "scope global"; then
                    yush_debug "$PRIMER_STEP_WIFI_INTERFACE already connected"
                else
                    _cf_path=${PRIMER_STEP_WIFI_CFDIR%/}/wpa_supplicant-${PRIMER_STEP_WIFI_INTERFACE}.conf
                    if [ -f "$_cf_path" ] && grep ssid "$_cf_path" | grep -q "$PRIMER_STEP_WIFI_ESSID"; then
                        yush_debug "Information for $PRIMER_STEP_WIFI_ESSID already present at $_cf_path"
                    else
                        yush_info "Remembering $PRIMER_STEP_WIFI_ESSID in $_cf_path"
                        wpa_passphrase "$PRIMER_STEP_WIFI_ESSID" "$PRIMER_STEP_WIFI_PSK" | primer_utils_sysfile_append "$_cf_path"
                    fi
                    if ps -e -o comm,pid | grep -q wpa_supplicant; then
                        _pid=$(ps -e -o comm,pid | grep wpa_supplicant | awk '{print $2}')
                        yush_notice "Killing existing wpa_supplicant at $_pid"
                        $PRIMER_OS_SUDO kill "$_pid"
                    fi
                    $PRIMER_OS_SUDO wpa_supplicant \
                                        -B \
                                        -i "$PRIMER_STEP_WIFI_INTERFACE" \
                                        -c "$_cf_path" \
                                        -P "$PRIMER_STEP_WIFI_PIDFILE" \
                                        -D "nl80211,wext"
                    yush_info "Acquiring IP address"
                    $PRIMER_OS_SUDO dhclient "$PRIMER_STEP_WIFI_INTERFACE"

                    # HOWTO remember at reboot: beginning of ? https://unix.stackexchange.com/a/92810
                    if ! grep -q "$_cf_path" /etc/network/interfaces; then
                        printf "auto %s\n" "$PRIMER_STEP_WIFI_INTERFACE" | primer_utils_sysfile_append /etc/network/interfaces
                        printf "iface %s inet dhcp\n" "$PRIMER_STEP_WIFI_INTERFACE" | primer_utils_sysfile_append /etc/network/interfaces
                        printf "    pre-up wpa_supplicant -B -i %s -c \"%s\" -P \"%s\" -D nl80211,wext\n" "$PRIMER_STEP_WIFI_INTERFACE" "$_cf_path" "$PRIMER_STEP_WIFI_PIDFILE" | primer_utils_sysfile_append /etc/network/interfaces
                        printf "    post-down kill \$(cat \"%s\")\n" "$PRIMER_STEP_WIFI_PIDFILE" | primer_utils_sysfile_append /etc/network/interfaces
                    fi
                fi
            fi
            ;;
        "clean")
            ;;
    esac
}


_primer_step_wifi_interface() {
    yush_debug "Discovering wifi interface"
    PRIMER_STEP_WIFI_INTERFACE=$(
        ip link show |
        grep -E '^[0-9]+:[[:space:]]+wl[[:alnum:]]+[0-9]' |
        sed -E 's/[0-9]+:[[:space:]]+(wl[[:alnum:]]+[0-9]):.*/\1/' |
        head -n 1)
    yush_notice "Using $PRIMER_STEP_WIFI_INTERFACE interface for wifi"
}