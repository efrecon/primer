#!/usr/bin/env sh

# sleep time
PRIMER_STEP_FOREVER_SLEEP=${PRIMER_STEP_FOREVER_SLEEP:-5}

primer_step_forever() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    --sleep)
                        PRIMER_STEP_FOREVER_SLEEP=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            yush_notice "Will sleep forever with at ${PRIMER_STEP_FOREVER_SLEEP}s intervals"
            while true; do
                sleep "$PRIMER_STEP_FOREVER_SLEEP"
            done
            ;;
        "clean")
            ;;
    esac
}
