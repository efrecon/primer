#!/usr/bin/env sh

primer_net_interfaces() {
    primer_os_dependency ip iproute2
    ip addr list |
        grep -E -e '^[[:digit:]]{1,}:[[:space:]]*' |
        sed -E 's|^[[:digit:]]{1,}:[[:space:]]*([^:]*):[[:space:]]*.*|\1|' |
        sed -E 's/([^@]*)(@.*)?/\1/'
}

primer_net_macaddr() {
    primer_os_dependency ip iproute2
    if [ "$#" = "0" ]; then
        for _if in $(primer_net_interfaces); do
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

# shellcheck disable=SC2120
primer_net_urldec() {
    if [ "$#" -eq "0" ]; then
        printf '%b\n' "$(sed -E -e 's/\+/ /g' -e 's/%([0-9a-fA-F]{2})/\\x\1/g')"
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

_primer_net_curlopts() {
    if [ -n "$PRIMER_CURL_OPTIONS" ] && [ -f "$PRIMER_CURL_OPTIONS" ]; then
        yush_debug "Looking for curl options for $1"
        while IFS='' read -r line || [ -n "$line" ]; do
            # Skip over lines containing comments. (Lines starting with '#').
            [ "${line##\#*}" ] || continue

            if [ -n "$line" ]; then
                _rx=$(printf %s\\n "$line" | awk '{print $1}' | primer_net_urldec)
                if printf %s\\n "$1" | grep -Eq "$_rx"; then
                    # Use awk to print all remaining fields of the line,
                    # respecting the ORS and OFS variables of awk.
                    _opts=$(    printf %s\\n "$line" |
                                awk '{for(i=2;i<=NF;i++){ printf("%s",( (i>2) ? OFS : "" ) $i) } ; printf("%s",ORS);}' )
                    yush_info "Picked these curl options for accessing $1: $_opts"
                    printf %s\\n "$_opts"
                    break
                fi
            fi
        done < "$PRIMER_CURL_OPTIONS"
    fi
}

primer_net_curl() {
    # Install curl if necessary, do it just once.
    if ! command -v curl >/dev/null 2>&1; then
        yush_debug "First time installation of curl and dependencies"
        primer_os_dependency curl
    fi

    # Get the URL, this is the first argument. Everything else is free-form
    # options to curl from the caller.
    _url=$1
    shift

    # Construct a curl command, forcing some decent options first, then the one
    # that could be specific for that (group of) URLs, last from the caller.
    yush_trace "Downloading $_url"
    if yush_loglevel_le verbose; then
        _copts="-fSL --progress-bar"
    else
        _copts=-sSL
    fi
    # shellcheck disable=SC2046
    curl $_copts $(_primer_net_curlopts "$_url") "$@" "$_url"
}