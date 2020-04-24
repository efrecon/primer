#!/usr/bin/env sh

# The location to place the system at, e.g. Europe/Stockholm.
TIMEZONE_LOCATION=${TIMEZONE_LOCATION:-}

timezone() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    --location)
                        TIMEZONE_LOCATION=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            if [ -n "$TIMEZONE_LOCATION" ]; then
                lsb_dist=$(primer_distribution)
                case "$lsb_dist" in
                    ubuntu|*bian)
                        $PRIMER_SUDO ln -fs "/usr/share/zoneinfo/$TIMEZONE_LOCATION" /etc/localtime
                        primer_dependency "" "tzdata"
                        $PRIMER_SUDO dpkg-reconfigure --frontend noninteractive tzdata
                        ;;
                    *)
                        yush_warn "Timezone setting NYI for $lsb_dist";;
                esac
            fi
            ;;
        "clean")
            yush_warn "Timezone information cannot be removed"
            ;;
    esac
}
