#!/usr/bin/env sh

primer_net_interfaces() {
    ip addr list |
        grep -E -e '^[[:digit:]]{1,}:[[:space:]]*' |
        sed -E 's|^[[:digit:]]{1,}:[[:space:]]*([^:]*):[[:space:]]*.*|\1|' |
        sed -E 's/([^@]*)(@.*)?/\1/'
}

primer_net_macaddr() {
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