#!/usr/bin/env sh

primer() {
    img=${1:-alpine}
    shift
    docker run \
        -i \
        --rm \
        -v "$(pwd):/primer:ro" \
        --entrypoint /primer/primer \
        "$img" \
            -p "/primer/spec/support/steps" \
            "$@"
}
