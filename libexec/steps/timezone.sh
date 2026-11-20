#!/usr/bin/env sh

# The location to place the system at, e.g. Europe/Stockholm.
PRIMER_STEP_TIMEZONE_LOCATION=${PRIMER_STEP_TIMEZONE_LOCATION:-}

# Directory containing the timezone database.
PRIMER_STEP_TIMEZONE_ZONEINFO=${PRIMER_STEP_TIMEZONE_ZONEINFO:-/usr/share/zoneinfo}

primer_step_timezone() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--location"
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
                # Locations are relative to the zoneinfo directory, and stay
                # in it.
                case "/$PRIMER_STEP_TIMEZONE_LOCATION/" in
                    //*|*/../*)
                        yush_error "Invalid timezone $PRIMER_STEP_TIMEZONE_LOCATION"
                        return 1;;
                esac
                lsb_dist=$(primer_os_distribution)
                case "$lsb_dist" in
                    *buntu|*bian|fedora*|alpine*)
                        if ! primer_os_packages installed tzdata; then
                            primer_os_packages add tzdata
                        fi
                        ;;
                esac
                _zone="${PRIMER_STEP_TIMEZONE_ZONEINFO%/}/$PRIMER_STEP_TIMEZONE_LOCATION"
                if ! [ -f "$_zone" ]; then
                    yush_error "Unknown timezone $PRIMER_STEP_TIMEZONE_LOCATION, no $_zone"
                    return 1
                fi
                # Zone files start with this magic, other files in the
                # directory, e.g. zone1970.tab, are not zones.
                if [ "$(head -c 4 "$_zone")" != "TZif" ]; then
                    yush_error "$_zone is not a timezone file"
                    return 1
                fi
                yush_info "Setting timezone to $PRIMER_STEP_TIMEZONE_LOCATION"
                # Also replace dangling links, which -e does not see.
                if [ -e /etc/localtime ] || [ -L /etc/localtime ]; then
                    $PRIMER_OS_SUDO rm -f /etc/localtime
                fi
                $PRIMER_OS_SUDO ln -s "$_zone" /etc/localtime
                # Keep /etc/timezone in sync, when the distribution uses it.
                if [ -f /etc/timezone ]; then
                    printf %s\\n "$PRIMER_STEP_TIMEZONE_LOCATION" | $PRIMER_OS_SUDO tee /etc/timezone > /dev/null
                fi
            fi
            ;;
        "clean")
            yush_warn "Timezone information cannot be removed"
            ;;
    esac
}
