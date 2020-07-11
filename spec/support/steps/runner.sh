#!/usr/bin/env sh

# command to execute
RUNNER_COMMAND=${RUNNER_COMMAND:-}

primer_step_runner() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    --command)
                        RUNNER_COMMAND=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !";;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            if [ -n "$RUNNER_COMMAND" ]; then
                yush_debug "Running: $RUNNER_COMMAND"
                if ! $RUNNER_COMMAND; then
                    yush_error "$RUNNER_COMMAND execution FAILED!"
                fi
            fi
            ;;
        "clean")
            ;;
    esac
}
