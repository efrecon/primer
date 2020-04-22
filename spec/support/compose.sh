#!/usr/bin/env sh

compose() {
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
            -s "compose runner" \
            --compose:version="$version" \
            --compose:sha256="$sum" \
            --runner:command="docker-compose --version"
}
