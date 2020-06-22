#!/usr/bin/env sh

primer_net_interfaces() {
    ip addr list |
        grep -E -e '^[[:digit:]]{1,}:[[:space:]]*' |
        sed -E 's|^[[:digit:]]{1,}:[[:space:]]*([^:]*):[[:space:]]*.*|\1|' |
        sed -E 's/([^@]*)(@.*)?/\1/'
}

primer_net_macaddr() {
    ip addr show "$1" |
        grep -E '^[[:space:]]*link' |
        grep -Eo '[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}' |
        head -n 1 |
        tr '[:upper:]' '[:lower:]'
}

primer_net_urldec() {
    printf '%b\n' "$(sed -E -e 's/\+/ /g' -e 's/%([0-9a-fA-F]{2})/\\x\1/g')"
}