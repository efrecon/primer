#!/usr/bin/env sh

# Docker compose is now a Docker CLI plugin (docker compose ...). It is
# installed (and removed) by the docker step. This step is kept for backwards
# compatibility only and does nothing else than printing out a notice.

primer_step_compose() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    -*)
                        yush_warn "compose step is deprecated, option $1 ignored, see the docker step instead"
                        shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install" | "clean")
            yush_notice "Docker compose is now a Docker CLI plugin, it is installed (and removed) by the docker step"
            ;;
    esac
}
