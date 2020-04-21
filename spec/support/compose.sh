#!/usr/bin/env sh

compose() {
    img=${1:-alpine}
    version=${2:-}
    sum=${3:-}
    container=$(  docker run \
                    -d \
                    -v "$(pwd):/primer:ro" \
                    --entrypoint /primer/primer \
                "$img" \
                    -s "forever" 2>/dev/null)
    docker exec "$container" \
        /primer/primer \
            -v debug \
            -s compose \
            --compose:version="$version" \
            --compose:sha256="$sum" >/dev/null 2>&1
    # Check if we can run --version and output the version line
    retval=0
    if ! docker exec -i "$container" docker-compose --version 2>/dev/null; then
        retval=1
    fi
    # Clean away the container
    docker container rm -fv "$container" >/dev/null 2>&1
    return $retval
}
