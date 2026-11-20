#!/usr/bin/env sh

# Wifi interface to configure, empty (the default) to pick the first one.
PRIMER_STEP_WIFI_INTERFACE=${PRIMER_STEP_WIFI_INTERFACE:-}

# Name of wifi network to connect to
PRIMER_STEP_WIFI_ESSID=${PRIMER_STEP_WIFI_ESSID:-}

# Pre-share key (passphrase) to access network.
PRIMER_STEP_WIFI_PSK=${PRIMER_STEP_WIFI_PSK:-}

# List of interfaces known to the OS.
PRIMER_STEP_WIFI_IFLIST=${PRIMER_STEP_WIFI_IFLIST:-/etc/network/interfaces}

# Directory for the wpa_supplicant configuration of the interface, which holds
# the network name and its key. The file is only readable by root.
PRIMER_STEP_WIFI_CONFDIR=${PRIMER_STEP_WIFI_CONFDIR:-/etc/wpa_supplicant}

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
                # Invalid input fails the step, and changes nothing.
                _primer_step_wifi_valid || return 1
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
    # The interface is configured through ifupdown (Debian, Ubuntu) or
    # ifupdown-ng (Alpine). NetworkManager would fight over the interface.
    if primer_os_service list NetworkManager | grep -q NetworkManager; then
        yush_error "NetworkManager manages the network of this host, use nmcli to connect to $PRIMER_STEP_WIFI_ESSID. Nothing changed"
        return 1
    fi
    _flavour=
    case "$(primer_os_distribution)" in
        *bian|*buntu)
            _flavour=ifupdown
            primer_os_packages add wpasupplicant ifupdown
            ;;
        alpine*)
            _flavour=ifupdown-ng
            primer_os_packages add wpa_supplicant ifupdown-ng ifupdown-ng-wifi
            ;;
        *)
            yush_error "The wifi step needs ifupdown, which $(primer_os_distribution) does not use, nothing changed"
            return 1
            ;;
    esac

    # Bring up the link and scan for networks to check if the
    # network is in range. This more for information than anything
    # else...
    $PRIMER_OS_SUDO ip link set "$PRIMER_STEP_WIFI_INTERFACE" up
    if primer_utils_syscmd_exists iwlist; then
        if $PRIMER_OS_SUDO iwlist "$PRIMER_STEP_WIFI_INTERFACE" scan | grep -qF "ESSID:\"$PRIMER_STEP_WIFI_ESSID\""; then
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

        # The network and its key go to a configuration file only readable by
        # root, the interfaces file, often readable by all, points to it.
        _conf=$(_primer_step_wifi_conf)
        if [ -n "$PRIMER_STEP_WIFI_PSK" ] && ! printf %s\\n "$_conf" | grep -qE '^	psk=[0-9a-f]{64}$'; then
            yush_error "Could not compute the key for $PRIMER_STEP_WIFI_ESSID, nothing changed"
            return 1
        fi
        _block=$(_primer_step_wifi_block "$_flavour")
        # Insert settings if we don't yet have them, replace them when they
        # have changed, e.g. another network or passphrase.
        if [ -f "$PRIMER_STEP_WIFI_IFLIST" ] \
                && grep -qxF "$(_primer_step_wifi_marker autoadd)" "$PRIMER_STEP_WIFI_IFLIST"; then
            if [ "$(_primer_step_wifi_current)" = "$_block" ]; then
                yush_debug "Information for $PRIMER_STEP_WIFI_INTERFACE already present at $PRIMER_STEP_WIFI_IFLIST"
            else
                yush_notice "Replacing wifi settings for $PRIMER_STEP_WIFI_INTERFACE at $PRIMER_STEP_WIFI_IFLIST"
                # A damaged block is left untouched, and so is the rest.
                _primer_step_wifi_remove || return 0
                printf '\n%s\n' "$_block" | primer_utils_sysfile_append "$PRIMER_STEP_WIFI_IFLIST"
            fi
        else
            $PRIMER_OS_SUDO mkdir -p "$(dirname "$PRIMER_STEP_WIFI_IFLIST")"
            printf '\n%s\n' "$_block" | primer_utils_sysfile_append "$PRIMER_STEP_WIFI_IFLIST"
        fi
        _primer_step_wifi_conf_write "$_conf"

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

    _primer_step_wifi_remove || true
    _primer_step_wifi_conf_remove
}

# Print the marker comment of type $1 (autoadd or endof) for the interface.
_primer_step_wifi_marker() {
    printf '# primer %s wifi settings: %s\n' "$1" "$PRIMER_STEP_WIFI_INTERFACE"
}

# Path to the wpa_supplicant configuration file for the interface.
_primer_step_wifi_conf_path() {
    printf '%s/primer-%s.conf\n' "${PRIMER_STEP_WIFI_CONFDIR%/}" "$PRIMER_STEP_WIFI_INTERFACE"
}

# Print the interface block, without secrets: it points to the wpa_supplicant
# configuration file, with wpa-conf for ifupdown, wifi-config-path for
# ifupdown-ng ($1).
_primer_step_wifi_block() {
    _primer_step_wifi_marker autoadd
    printf "auto %s\n" "$PRIMER_STEP_WIFI_INTERFACE"
    printf "allow-hotplug %s\n" "$PRIMER_STEP_WIFI_INTERFACE"
    printf "iface %s inet dhcp\n" "$PRIMER_STEP_WIFI_INTERFACE"
    if [ "$1" = "ifupdown-ng" ]; then
        printf "    use wifi\n"
        printf "    wifi-config-path %s\n" "$(_primer_step_wifi_conf_path)"
    else
        printf "    wpa-conf %s\n" "$(_primer_step_wifi_conf_path)"
    fi
    _primer_step_wifi_marker endof
}

# Print the wpa_supplicant configuration for the network: its name and the
# pre-shared key, or no key management for open networks.
_primer_step_wifi_conf() {
    printf '# primer wifi settings: %s\n' "$PRIMER_STEP_WIFI_INTERFACE"
    printf 'network={\n'
    printf '\tssid="%s"\n' "$PRIMER_STEP_WIFI_ESSID"
    if [ -z "$PRIMER_STEP_WIFI_PSK" ]; then
        printf '\tkey_mgmt=NONE\n'
    else
        printf '\tpsk=%s\n' "$(_primer_step_wifi_psk_hex)"
    fi
    printf '}\n'
}

# Write the configuration $1 to the configuration file, created only readable
# by root before anything is written to it.
_primer_step_wifi_conf_write() {
    _cw_path=$(_primer_step_wifi_conf_path)
    if ! $PRIMER_OS_SUDO test -f "$_cw_path"; then
        $PRIMER_OS_SUDO mkdir -p "$(dirname "$_cw_path")"
        (umask 077 && $PRIMER_OS_SUDO touch "$_cw_path")
        $PRIMER_OS_SUDO chmod 600 "$_cw_path"
    elif [ "$($PRIMER_OS_SUDO cat "$_cw_path")" = "$1" ]; then
        yush_debug "Wifi network for $PRIMER_STEP_WIFI_INTERFACE already at $_cw_path"
        return 0
    elif [ -s "$_cw_path" ]; then
        yush_notice "Replacing wifi network for $PRIMER_STEP_WIFI_INTERFACE at $_cw_path"
    fi
    printf '%s\n' "$1" | primer_utils_sysfile_replace "$_cw_path"
}

# Remove the configuration file, when written by primer.
_primer_step_wifi_conf_remove() {
    _cr_path=$(_primer_step_wifi_conf_path)
    if [ "$($PRIMER_OS_SUDO head -n 1 "$_cr_path" 2>/dev/null || true)" = "# primer wifi settings: $PRIMER_STEP_WIFI_INTERFACE" ]; then
        $PRIMER_OS_SUDO rm -f "$_cr_path"
    fi
}

# Print the block for the interface currently in the list of interfaces.
_primer_step_wifi_current() {
    _cur_start=$(_primer_step_wifi_marker autoadd)
    _cur_end=$(_primer_step_wifi_marker endof)
    _cur_in=0
    while IFS= read -r _cur_line || [ -n "$_cur_line" ]; do
        if [ "$_cur_line" = "$_cur_start" ]; then _cur_in=1; fi
        if [ "$_cur_in" = "1" ]; then printf '%s\n' "$_cur_line"; fi
        if [ "$_cur_line" = "$_cur_end" ]; then _cur_in=0; fi
    done < "$PRIMER_STEP_WIFI_IFLIST"
}

# Remove the block for the interface from the list of interfaces. This needs
# to match against the lines that are added as comments when installing,
# including the empty line that precedes the block. A block without its end
# marker (e.g. after a manual edit) is never removed, as everything after it
# would go: the file is left untouched, with a warning, and this returns 1.
_primer_step_wifi_remove() {
    if ! [ -f "$PRIMER_STEP_WIFI_IFLIST" ]; then
        yush_debug "No $PRIMER_STEP_WIFI_IFLIST, nothing to remove"
        return 0
    fi

    # Copy all lines but the block to a temporary file. An empty line is held
    # back until the next line is known not to start the block. The loop reads
    # from a redirection, so it runs in this shell and its state is known
    # after it.
    _rm_start=$(_primer_step_wifi_marker autoadd)
    _rm_end=$(_primer_step_wifi_marker endof)
    _rm_cut=0
    _rm_held=0
    _iface=$(mktemp)
    while IFS= read -r _rm_line || [ -n "$_rm_line" ]; do
        if [ "$_rm_line" = "$_rm_start" ]; then
            _rm_cut=1
            _rm_held=0
        elif [ "$_rm_line" = "$_rm_end" ]; then
            _rm_cut=0
        elif [ "$_rm_cut" = "0" ]; then
            if [ "$_rm_held" = "1" ]; then
                echo ""
                _rm_held=0
            fi
            if [ -z "$_rm_line" ]; then
                _rm_held=1
            else
                printf '%s\n' "$_rm_line"
            fi
        fi
    done < "$PRIMER_STEP_WIFI_IFLIST" > "$_iface"

    if [ "$_rm_cut" = "1" ]; then
        rm -f "$_iface"
        yush_warn "Wifi settings for $PRIMER_STEP_WIFI_INTERFACE at $PRIMER_STEP_WIFI_IFLIST have no end marker, leaving the file untouched: fix it manually!"
        return 1
    fi
    if [ "$_rm_held" = "1" ]; then
        echo "" >> "$_iface"
    fi
    # Replace atomically, keeping the owner and permissions of the file.
    primer_utils_sysfile_replace "$PRIMER_STEP_WIFI_IFLIST" < "$_iface"
    rm -f "$_iface"
}

# Check the network name and the passphrase: the name is written between double
# quotes, and wpa_passphrase only accepts passphrases of 8 to 63 characters.
_primer_step_wifi_valid() {
    case "$PRIMER_STEP_WIFI_ESSID" in
        *\"*)
            yush_error "Wifi network names containing double quotes are not supported: $PRIMER_STEP_WIFI_ESSID"
            return 1;;
    esac
    if [ -n "$PRIMER_STEP_WIFI_PSK" ]; then
        if [ "${#PRIMER_STEP_WIFI_PSK}" -lt 8 ] || [ "${#PRIMER_STEP_WIFI_PSK}" -gt 63 ]; then
            yush_error "Wifi passphrases must have 8 to 63 characters, nothing changed"
            return 1
        fi
    fi
}

# Use wpa_passphrase to get the hex encoded value for the passphrase. The
# passphrase is given on stdin, as the command line is visible to all users.
# Recent versions only read it from a terminal (wpa_supplicant 2.11, e.g. on
# Alpine 3.24): the passphrase is then passed as an argument, visible
# for as long as wpa_passphrase runs.
_primer_step_wifi_psk_hex() {
    _hex=$(printf '%s\n' "$PRIMER_STEP_WIFI_PSK" | wpa_passphrase "$PRIMER_STEP_WIFI_ESSID" 2>/dev/null | _primer_step_wifi_psk_field || true)
    if [ -z "$_hex" ]; then
        _hex=$(wpa_passphrase "$PRIMER_STEP_WIFI_ESSID" "$PRIMER_STEP_WIFI_PSK" | _primer_step_wifi_psk_field || true)
    fi
    printf '%s\n' "$_hex"
}

# Print the value of the uncommented psk field of the output of wpa_passphrase
# on stdin.
_primer_step_wifi_psk_field() {
    grep -E '^[[:space:]]*psk=' | sed -E 's/^[[:space:]]*psk=([0-9a-f]+)/\1/'
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
