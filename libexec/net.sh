#!/usr/bin/env sh

_primer_net_ip() {
    lsb_dist=$(primer_os_distribution)
    case "$lsb_dist" in
        *buntu|*bian|alpine*|clear*linux*)
            primer_os_dependency ip iproute2;;
        fedora*)
            primer_os_dependency ip iproute;;
        *)
            yush_warn "ip installation NYI for $lsb_dist";;
    esac
}

primer_net_interfaces() {
    _primer_net_ip
    ip addr list |
        grep -E -e '^[[:digit:]]{1,}:[[:space:]]*' |
        sed -E 's|^[[:digit:]]{1,}:[[:space:]]*([^:]*):[[:space:]]*.*|\1|' |
        sed -E 's/([^@]*)(@.*)?/\1/'
}

primer_net_macaddr() {
    _primer_net_ip
    if [ "$#" = "0" ]; then
        for _if in $(primer_net_interfaces | grep -v '^lo$'); do
            primer_net_macaddr "$_if"
        done
    elif [ -n "$1" ]; then
        ip addr show "$1" |
            grep -E '^[[:space:]]*link' |
            grep -Eo '[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}' |
            head -n 1 |
            tr '[:upper:]' '[:lower:]'
    fi
}

primer_net_primary_interface() {
    primer_net_interfaces | grep -E '^(en.*|eth[[:digit:]]{1,})' | head -n 1
}

# Decode URL-encoded (percent-encoded) strings, from the argument or stdin,
# line by line. awk is used as printf %b does not support \x in all shells
# (e.g. dash), and the C locale makes it process bytes.
# shellcheck disable=SC2120
primer_net_urldec() {
    if [ "$#" -eq "0" ]; then
        LC_ALL=C awk '
            BEGIN { for (i = 1; i < 256; i++) chr[sprintf("%02x", i)] = sprintf("%c", i) }
            {
                gsub(/\+/, " ")
                out = ""
                while (match($0, /%[0-9a-fA-F][0-9a-fA-F]/)) {
                    out = out substr($0, 1, RSTART - 1) chr[tolower(substr($0, RSTART + 1, 2))]
                    $0 = substr($0, RSTART + 3)
                }
                print out $0
            }'
    else
        printf %s\\n "$1" | primer_net_urldec
    fi
}

primer_net_urlenc() {
    _encoded=
    for _pos in $(seq 1 "${#1}"); do
        _c=$(printf %s\\n "$1" | cut -c "$_pos")
        case "$_c" in
            [_.~a-zA-Z0-9-]) _encoded="${_encoded}${_c}" ;;
            # The single quote before $_c below converts $_c to its numeric
            # value: http://pubs.opengroup.org/onlinepubs/9699919799/utilities/printf.html#tag_20_94_13
            *)               _encoded="${_encoded}$(printf '%%%02x' "'$_c")";;
        esac
    done
    printf %s\\n "$_encoded"
}

# Return the hostname of the current machine.
primer_net_hostname() { uname -n; }

primer_net_active_firewall() {
    if primer_utils_syscmd_exists ufw &&
            $PRIMER_OS_SUDO ufw status 2>/dev/null | grep -q '^Status: active$'; then
        printf '%s\n' ufw
    elif primer_utils_syscmd_exists firewall-cmd &&
            $PRIMER_OS_SUDO firewall-cmd --state 2>/dev/null | grep -qx running; then
        printf '%s\n' firewalld
    elif primer_utils_syscmd_exists nft &&
            { { primer_utils_syscmd_exists systemctl &&
                    $PRIMER_OS_SUDO systemctl is-active --quiet nftables; } ||
              { primer_utils_syscmd_exists rc-service &&
                    $PRIMER_OS_SUDO rc-service nftables status >/dev/null 2>&1; }; }; then
        printf '%s\n' nftables
    fi
}

_primer_net_port_allow() {
    _firewall=$1
    _port=$2
    _proto=$3
    yush_info "Allowing incoming traffic for port $_port/$_proto on firewall $_firewall"
    case "$_firewall" in
        ufw)
            $PRIMER_OS_SUDO ufw allow "${_port}/${_proto}";;
        firewalld)
            $PRIMER_OS_SUDO firewall-cmd --permanent --add-port="${_port}/${_proto}"
            $PRIMER_OS_SUDO firewall-cmd --add-port="${_port}/${_proto}";;
        nftables)
            $PRIMER_OS_SUDO nft add rule inet filter input "$_proto" dport "$_port" accept;;
    esac
}

# Allow incoming traffic for one or more port[/protocol] rules. A protocol-less
# rule opens both TCP and UDP. Supported protocols are TCP and UDP.
primer_net_port_allow() {
    _firewall=$(primer_net_active_firewall)
    if [ -z "$_firewall" ]; then
        yush_warn "No active UFW, firewalld, or nftables firewall found"
        return 1
    fi

    for _rule in "$@"; do
        _port=${_rule%%/*}
        _proto=${_rule#*/}
        [ "$_port" = "$_proto" ] && _proto=
        if ! printf '%s\n' "$_port" | grep -Eq '^[0-9]+$' ||
                [ "$_port" -lt 1 ] || [ "$_port" -gt 65535 ]; then
            yush_warn "Invalid port rule: $_rule"
            continue
        fi
        if [ -n "$_proto" ]; then
            _proto=$(printf '%s\n' "$_proto" | tr '[:upper:]' '[:lower:]')
            case "$_proto" in
                tcp|udp) _primer_net_port_allow "$_firewall" "$_port" "$_proto";;
                *) yush_warn "Invalid port protocol in rule: $_rule";;
            esac
        else
            _primer_net_port_allow "$_firewall" "$_port" tcp
            _primer_net_port_allow "$_firewall" "$_port" udp
        fi
    done

    if [ "$_firewall" = nftables ]; then
        yush_warn "nftables rules are not persistent; add them to the managed nftables configuration"
    fi
}

# Print the extra curl options for URL $1, if any, in the format of a curl
# config file, one option per line. Lines of the file at $PRIMER_CURL_OPTIONS
# (# for comments) are a URL-encoded regex followed by curl options, quoted as
# in the shell, e.g. -H "Authorization: Bearer xxx": the options of the first
# line whose regex matches $1 are printed.
_primer_net_curlopts() {
    if [ -n "$PRIMER_CURL_OPTIONS" ] && [ -f "$PRIMER_CURL_OPTIONS" ]; then
        yush_debug "Looking for curl options for $1"
        while IFS='' read -r line || [ -n "$line" ]; do
            # Skip over lines containing comments. (Lines starting with '#').
            [ "${line##\#*}" ] || continue

            if [ -n "$line" ]; then
                _rx=$(printf %s\\n "$line" | awk '{print $1}' | primer_net_urldec)
                if printf %s\\n "$1" | grep -Eq "$_rx"; then
                    # Options are not logged, as they often carry secrets,
                    # e.g. tokens.
                    yush_debug "Using curl options from $PRIMER_CURL_OPTIONS for accessing $1"
                    printf %s\\n "$line" |
                        sed -E 's/^[[:space:]]*[^[:space:]]+[[:space:]]*//' |
                        _primer_net_curlconfig
                    break
                fi
            fi
        done < "$PRIMER_CURL_OPTIONS"
    fi
}

# Convert the command-line options on stdin, quoted as in the shell (single
# and double quotes, backslashes), to the format of a curl config file: one
# option per line, followed by its value in double quotes, if any.
_primer_net_curlconfig() {
    awk '
        function esc(t,   r, k, ch) {
            r = ""
            for (k = 1; k <= length(t); k++) {
                ch = substr(t, k, 1)
                if (ch == "\\" || ch == "\"") r = r "\\"
                r = r ch
            }
            return r
        }
        {
            sq = sprintf("%c", 39); n = 0; tok = ""; intok = 0; q = ""
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (q != "") {
                    if (c == q) q = ""
                    else if (c == "\\" && q == "\"" && i < length($0)) { i++; tok = tok substr($0, i, 1) }
                    else tok = tok c
                } else if (c == "\"" || c == sq) { q = c; intok = 1 }
                else if (c == "\\" && i < length($0)) { i++; tok = tok substr($0, i, 1); intok = 1 }
                else if (c == " " || c == "\t") { if (intok) { toks[++n] = tok; tok = ""; intok = 0 } }
                else { tok = tok c; intok = 1 }
            }
            if (intok) toks[++n] = tok
            out = ""
            for (j = 1; j <= n; j++) {
                if (substr(toks[j], 1, 1) == "-") {
                    if (out != "") print out
                    out = toks[j]
                } else {
                    out = out " \"" esc(toks[j]) "\""
                }
            }
            if (out != "") print out
        }'
}

primer_net_curl() {
    # Install curl if necessary, do it just once.
    if ! command -v curl >/dev/null 2>&1; then
        yush_debug "First time installation of curl and dependencies"
        primer_os_dependency curl >/dev/null
    fi

    # Get the URL, this is the first argument. Everything else is free-form
    # options to curl from the caller.
    _url=$1
    shift

    # Construct a curl command, forcing some decent options first, then the one
    # that could be specific for that (group of) URLs, last from the caller.
    yush_trace "Downloading $_url"
    # Always fail on HTTP errors, and only show progress at the debug level
    # and below.
    if yush_loglevel_le debug; then
        _copts="-fSL --progress-bar"
    else
        _copts=-fsSL
    fi
    # Options for the URL are given as a config file on stdin, so that they
    # can contain spaces, and secrets do not show in the list of processes.
    # shellcheck disable=SC2086
    _primer_net_curlopts "$_url" | curl -K - $_copts "$@" "$_url"
}
