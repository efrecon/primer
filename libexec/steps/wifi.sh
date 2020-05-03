#!/usr/bin/env sh

# Locale on system
PRIMER_STEP_WIFI_INTERFACE=${PRIMER_STEP_WIFI_INTERFACE:-}

# Name of wifi network to connect to
PRIMER_STEP_WIFI_ESSID=${PRIMER_STEP_WIFI_ESSID:-}

# Pre-share key (passphrase) to access network.
PRIMER_STEP_WIFI_PSK=${PRIMER_STEP_WIFI_PSK:-}

# List of interfaces known to the OS.
PRIMER_STEP_WIFI_IFLIST=/etc/network/interfaces

primer_step_wifi() {
    case "$1" in
        "option")
            shift;
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
            [ -z "$PRIMER_STEP_WIFI_INTERFACE" ] && _primer_step_wifi_interface
            [ -n "$PRIMER_STEP_WIFI_INTERFACE" ] && [ -n "$PRIMER_STEP_WIFI_ESSID" ] && _primer_step_wifi_install
            ;;
        "clean")
            [ -z "$PRIMER_STEP_WIFI_INTERFACE" ] && _primer_step_wifi_interface
            [ -n "$PRIMER_STEP_WIFI_INTERFACE" ] && _primer_step_wifi_clean
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
    if command -v iwlist >/dev/null; then
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
        if primer_os_service list | grep -q wpa_supplicant; then
            yush_notice "Disabling wpa_supplicant service"
            primer_os_service stop wpa_supplicant
            primer_os_service disable wpa_supplicant
        fi

        # Insert settings if we don't yet have them
        if grep "wpa-ssid" "$PRIMER_STEP_WIFI_IFLIST" | grep -q "$PRIMER_STEP_WIFI_ESSID"; then
            yush_debug "Information for $PRIMER_STEP_WIFI_ESSID already present at $PRIMER_STEP_WIFI_IFLIST"
        else
            # We insert an interface block. The wpa- are parsed and
            # understood by the wpa_supplicant package for its
            # configuration. 
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
    
    # Remove interface settings. This needs to match against the
    # lines that are added as comments when installing.
    _iface=$(mktemp)
    awk "
        BEGIN { cut=0 }
        /^#.*autoadd.*: $PRIMER_STEP_WIFI_INTERFACE/ { cut=1 }
        /^#.*endof.*: $PRIMER_STEP_WIFI_INTERFACE/ { cut=0; next }
        { if (cut!=1) { print \$0 } }
    " > "$_iface"
    primer_utils_path_ownership "$_iface" --as "$PRIMER_STEP_WIFI_IFLIST"
    $PRIMER_OS_SUDO mv -f "$_iface" "$PRIMER_STEP_WIFI_IFLIST"
}

# Use wpa_passphrase to get the hex encoded value for the passphrase.
_primer_step_wifi_psk_hex() {
    wpa_passphrase "$PRIMER_STEP_WIFI_ESSID" "$PRIMER_STEP_WIFI_PSK" |
        grep 'psk=' |
        grep -vE '^\s*#psk' |
        sed -E 's/^\s*psk=([0-9a-f]+)/\1/'
}

# Guess first wifi interface. Old style wlan0 new style wlxxxx, they all start
# by wl and end with a number.
_primer_step_wifi_interface() {
    yush_debug "Discovering wifi interface"
    PRIMER_STEP_WIFI_INTERFACE=$(
        ip link show |
        grep -E '^[0-9]+:[[:space:]]+wl[[:alnum:]]+[0-9]' |
        sed -E 's/[0-9]+:[[:space:]]+(wl[[:alnum:]]+[0-9]):.*/\1/' |
        head -n 1)
    yush_notice "Using $PRIMER_STEP_WIFI_INTERFACE interface for wifi"
}
