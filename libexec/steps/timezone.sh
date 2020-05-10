#!/usr/bin/env sh

# The location to place the system at, e.g. Europe/Stockholm.
PRIMER_STEP_TIMEZONE_LOCATION=${PRIMER_STEP_TIMEZONE_LOCATION:-}

primer_step_timezone() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    --location)
                        PRIMER_STEP_TIMEZONE_LOCATION=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            if [ -n "$PRIMER_STEP_TIMEZONE_LOCATION" ]; then
                lsb_dist=$(primer_os_distribution)
                case "$lsb_dist" in
                    *buntu)
                        [ -f /etc/localtime ] && $PRIMER_OS_SUDO rm /etc/localtime
                        $PRIMER_OS_SUDO ln -s "/usr/share/zoneinfo/$PRIMER_STEP_TIMEZONE_LOCATION" /etc/localtime
                        primer_os_dependency "" "tzdata"
                        $PRIMER_OS_SUDO dpkg-reconfigure --frontend noninteractive tzdata
                        ;;
                    *bian)
                        [ -f /etc/localtime ] && $PRIMER_OS_SUDO rm /etc/localtime
                        $PRIMER_OS_SUDO ln -s "/usr/share/zoneinfo/$PRIMER_STEP_TIMEZONE_LOCATION" /etc/localtime
                        primer_os_dependency "" "tzdata"
                        $PRIMER_OS_SUDO dpkg-reconfigure --frontend noninteractive tzdata
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
