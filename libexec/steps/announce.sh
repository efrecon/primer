#!/usr/bin/env sh

# Announce methods
PRIMER_STEP_ANNOUNCE_METHODS=${PRIMER_STEP_ANNOUNCE_METHODS:-"mDNS NetBIOS"}

primer_step_announce() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--method --methods"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --method)
                        PRIMER_STEP_ANNOUNCE_METHODS="$PRIMER_STEP_ANNOUNCE_METHODS $2"; shift 2;;
                    --methods)
                        PRIMER_STEP_ANNOUNCE_METHODS=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install"|"clean")
            if [ -z "$PRIMER_STEP_ANNOUNCE_METHODS" ]; then
                yush_warn "No DNS announce methods specified."
                return
            fi
            lsb_dist=$(primer_os_distribution)
            for method in $PRIMER_STEP_ANNOUNCE_METHODS; do
                # Daemon implementing the method, and package providing it.
                _daemon=
                _pkg=
                case "$(printf %s\\n "$method" | tr '[:upper:]' '[:lower:]')" in
                    mdns)
                        _daemon=avahi-daemon
                        case "$lsb_dist" in
                            *buntu|*bian)
                                _pkg=avahi-daemon;;
                            fedora*|alpine*|clear*linux*)
                                _pkg=avahi;;
                        esac
                        ;;
                    netbios)
                        _daemon=nmbd
                        case "$lsb_dist" in
                            *buntu|*bian|fedora*|clear*linux*)
                                _pkg=samba;;
                            alpine*)
                                _pkg=samba-server;;
                        esac
                        ;;
                esac

                if [ -z "$_daemon" ]; then
                    yush_warn "Announce method $method is not supported, skipping"
                elif [ -z "$_pkg" ]; then
                    yush_warn "Announce method $method NYI for $lsb_dist"
                elif [ "$1" = "install" ]; then
                    yush_info "Announcing using method: $method"
                    _primer_step_announce_install "$_daemon" "$_pkg"
                else
                    yush_info "Cleaning announcements for method: $method"
                    _primer_step_announce_uninstall "$_daemon" "$_pkg"
                fi
            done
            ;;
    esac
}

# Install package $2 and run the daemon $1 it provides at boot.
_primer_step_announce_install() {
    primer_os_dependency "$1" "$2"
    if primer_utils_syscmd_exists "$1"; then
        primer_os_service start "$1"
        primer_os_service enable "$1"
    else
        yush_warn "Could not find $1 after installing $2, announcing disabled"
    fi
}

# Stop the daemon $1 and remove the package $2 providing it.
_primer_step_announce_uninstall() {
    if primer_utils_syscmd_exists "$1"; then
        primer_os_service stop "$1"
        primer_os_service disable "$1"
        primer_os_packages del "$2"
    fi
}
