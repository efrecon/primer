#!/usr/bin/env sh

# sleep time
FOREVER_SLEEP=${FOREVER_SLEEP:-5}

forever() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    --sleep)
                        FOREVER_SLEEP=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            yush_notice "Will sleep forever with at ${FOREVER_SLEEP}s intervals"
            while true; do
                sleep "$FOREVER_SLEEP"
            done
            ;;
        "clean")
            ;;
    esac
}
