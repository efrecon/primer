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
