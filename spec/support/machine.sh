#!/usr/bin/env sh

machine() {
    img=${1:-alpine}
    version=${2:-}
    sum=${3:-}
    docker run \
            -i \
            --rm \
            -v "$(pwd):/primer:ro" \
            --entrypoint /primer/primer \
        "$img" \
            -p /primer/libexec/steps:/primer/spec/support/steps \
            -v error \
            -s "machine runner" \
            --machine:version="$version" \
            --machine:sha256="$sum" \
            --runner:command="docker-machine version"
}
