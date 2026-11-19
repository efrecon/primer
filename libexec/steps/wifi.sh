#!/usr/bin/env sh

# Wifi interface to configure, empty (the default) to pick the first one.
PRIMER_STEP_WIFI_INTERFACE=${PRIMER_STEP_WIFI_INTERFACE:-}

# Name of wifi network to connect to
PRIMER_STEP_WIFI_ESSID=${PRIMER_STEP_WIFI_ESSID:-}

# Pre-share key (passphrase) to access network.
PRIMER_STEP_WIFI_PSK=${PRIMER_STEP_WIFI_PSK:-}

# List of interfaces known to the OS.
PRIMER_STEP_WIFI_IFLIST=${PRIMER_STEP_WIFI_IFLIST:-/etc/network/interfaces}

primer_step_wifi() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--interface --essid|--network|--ssid --psk|--password|--key|--passphrase"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --interface)
                        PRIMER_STEP_WIFI_INTERFACE="$2"; shift 2;;
                    --essid | --network | --ssid)
                        PRIMER_STEP_WIFI_ESSID="$2"; shift 2;;
                    --psk | --password | --key | --passphrase)
                        PRIMER_STEP_WIFI_PSK="$2"; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            if [ -z "$PRIMER_STEP_WIFI_INTERFACE" ]; then
                _primer_step_wifi_interface
            fi
            if [ -z "$PRIMER_STEP_WIFI_INTERFACE" ]; then
                yush_warn "No wifi interface found, nothing to configure"
            elif [ -z "$PRIMER_STEP_WIFI_ESSID" ]; then
                yush_warn "No wifi network specified, nothing to configure"
            else
                _primer_step_wifi_install
            fi
            ;;
        "clean")
            if [ -z "$PRIMER_STEP_WIFI_INTERFACE" ]; then
                _primer_step_wifi_interface
            fi
            if [ -z "$PRIMER_STEP_WIFI_INTERFACE" ]; then
                yush_warn "No wifi interface found, nothing to clean"
            else
                _primer_step_wifi_clean
            fi
            ;;
    esac
}

_primer_step_wifi_install() {
    if yush_glob "*bian|*buntu" "$(primer_os_distribution)"; then
        primer_os_packages add wpasupplicant
    else
        primer_os_packages add wpa_supplicant
    fi
    # Bring up the link and scan for networks to check if the
    # network is in range. This more for information than anything
    # else...
    $PRIMER_OS_SUDO ip link set "$PRIMER_STEP_WIFI_INTERFACE" up
    if primer_utils_syscmd_exists iwlist; then
        if $PRIMER_OS_SUDO iwlist "$PRIMER_STEP_WIFI_INTERFACE" scan | grep "ESSID:" | grep -q "$PRIMER_STEP_WIFI_ESSID"; then
            yush_info "$PRIMER_STEP_WIFI_ESSID is in range"
        else
            yush_warn "$PRIMER_STEP_WIFI_ESSID seems not in range"
        fi
    fi
    # Check that we don't already have an IP for that interface. If
    # we don't make settings directly in /etc/network/interfaces
    if ip address show dev "$PRIMER_STEP_WIFI_INTERFACE" | grep "inet" | grep "$PRIMER_STEP_WIFI_INTERFACE" | grep -q "scope global"; then
        yush_debug "$PRIMER_STEP_WIFI_INTERFACE already connected"
    else
        # Bring down the link, we brought it up to scan
        $PRIMER_OS_SUDO ip link set "$PRIMER_STEP_WIFI_INTERFACE" down

        # Disable wpa_supplicant (DBus) service
        if primer_os_service list wpa_supplicant | grep -q wpa_supplicant; then
            yush_notice "Disabling wpa_supplicant service"
            primer_os_service stop wpa_supplicant
            primer_os_service disable wpa_supplicant
        fi

        # Insert settings if we don't yet have them
        if [ -f "$PRIMER_STEP_WIFI_IFLIST" ] \
                && grep -qxF "# primer autoadd wifi settings: $PRIMER_STEP_WIFI_INTERFACE" "$PRIMER_STEP_WIFI_IFLIST"; then
            yush_debug "Information for $PRIMER_STEP_WIFI_ESSID already present at $PRIMER_STEP_WIFI_IFLIST"
        else
            # We insert an interface block. The wpa- are parsed and
            # understood by the wpa_supplicant package for its
            # configuration.
            $PRIMER_OS_SUDO mkdir -p "$(dirname "$PRIMER_STEP_WIFI_IFLIST")"
            {
                echo "";
                echo "# primer autoadd wifi settings: $PRIMER_STEP_WIFI_INTERFACE";
                printf "auto %s\n" "$PRIMER_STEP_WIFI_INTERFACE";
                printf "allow-hotplug %s\n" "$PRIMER_STEP_WIFI_INTERFACE";
                printf "iface %s inet dhcp\n" "$PRIMER_STEP_WIFI_INTERFACE";
                printf "    wpa-ssid \"%s\"\n" "$PRIMER_STEP_WIFI_ESSID";
                if [ -z "$PRIMER_STEP_WIFI_PSK" ]; then
                    echo "    wpa-key-mgmt NONE";
                else
                    printf "    wpa-psk %s\n" "$(_primer_step_wifi_psk_hex)";
                fi
                echo "# primer endof wifi settings: $PRIMER_STEP_WIFI_INTERFACE";
            } | primer_utils_sysfile_append "$PRIMER_STEP_WIFI_IFLIST"
        fi

        # Bring up the interface (down first, as a security
        # measure). This tests the block declared above, meaning
        # that we know it will work at next boot as well.
        $PRIMER_OS_SUDO ifdown "$PRIMER_STEP_WIFI_INTERFACE"
        $PRIMER_OS_SUDO ifup "$PRIMER_STEP_WIFI_INTERFACE"
    fi
}

_primer_step_wifi_clean() {
    # Bring down interface
    if ip address show dev "$PRIMER_STEP_WIFI_INTERFACE" | grep "inet" | grep "$PRIMER_STEP_WIFI_INTERFACE" | grep -q "scope global"; then
        $PRIMER_OS_SUDO ifdown --force -v "$PRIMER_STEP_WIFI_INTERFACE"
    fi

    if ! [ -f "$PRIMER_STEP_WIFI_IFLIST" ]; then
        yush_debug "No $PRIMER_STEP_WIFI_IFLIST, nothing to remove"
        return 0
    fi

    # Remove interface settings. This needs to match against the lines that
    # are added as comments when installing, including the empty line that
    # precedes the block.
    _iface=$(mktemp)
    awk -v start="# primer autoadd wifi settings: $PRIMER_STEP_WIFI_INTERFACE" \
        -v end="# primer endof wifi settings: $PRIMER_STEP_WIFI_INTERFACE" '
        $0 == start { cut=1; held=0; next }
        $0 == end { cut=0; next }
        cut == 1 { next }
        held == 1 { print ""; held=0 }
        $0 == "" { held=1; next }
        { print }
        END { if (held == 1) print "" }
    ' "$PRIMER_STEP_WIFI_IFLIST" > "$_iface"
    # Write back in place, which keeps the owner and permissions of the file.
    $PRIMER_OS_SUDO tee "$PRIMER_STEP_WIFI_IFLIST" < "$_iface" > /dev/null
    rm -f "$_iface"
}

# Use wpa_passphrase to get the hex encoded value for the passphrase.
_primer_step_wifi_psk_hex() {
    wpa_passphrase "$PRIMER_STEP_WIFI_ESSID" "$PRIMER_STEP_WIFI_PSK" |
        grep -E '^[[:space:]]*psk=' |
        sed -E 's/^[[:space:]]*psk=([0-9a-f]+)/\1/'
}

# Guess first wifi interface. Old style wlan0, new style wlp2s0 or wlx followed
# by the MAC address: they all start by wl.
_primer_step_wifi_interface() {
    yush_debug "Discovering wifi interface"
    PRIMER_STEP_WIFI_INTERFACE=$(
        ip link show |
        grep -E '^[0-9]+:[[:space:]]+wl[[:alnum:]]+:' |
        sed -E 's/^[0-9]+:[[:space:]]+(wl[[:alnum:]]+):.*/\1/' |
        head -n 1)
    if [ -n "$PRIMER_STEP_WIFI_INTERFACE" ]; then
        yush_notice "Using $PRIMER_STEP_WIFI_INTERFACE interface for wifi"
    fi
}
