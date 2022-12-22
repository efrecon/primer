#!/usr/bin/env sh

primer_version_current() {
    if [ -x "$(command -v "$1")" ]; then
        if "$1" --version | grep -iFq "version"; then
            "$1" --version|grep -iF "version"|grep -E -o '[0-9]+(\.[0-9]+)*'|head -1
        else
            "$1" --version|grep -E -o '[0-9]+(\.[0-9]+)*'|head -1
        fi
    fi
}

# Following uses the github API
# https://developer.github.com/v3/repos/releases/#list-releases-for-a-repository
# for getting the list of latest releases and focuses solely on "full" releases.
# Release candidates have -rcXXX in their version number, these are set away by
# the grep calls.
primer_version_github_latest() {
    yush_notice "Discovering latest ${2:-} version from $1"
    primer_net_curl "$1" |
        grep -E '"name"[[:space:]]*:[[:space:]]*"v?[0-9]+(\.[0-9]+)*"' |
        grep -Eo '[0-9]+(\.[0-9]+)*' |
        head -1
}