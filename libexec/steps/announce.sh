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
        "install")
            if [ -n "$PRIMER_STEP_ANNOUNCE_METHODS" ]; then
                for method in $PRIMER_STEP_ANNOUNCE_METHODS; do
                    if command -v "_primer_step_announce_${method}_add" >/dev/null 2>&1; then
                        yush_info "Announcing using method: $method"
                        "_primer_step_announce_${method}_add"
                    else
                        yush_warn "Announce method $method is not supported, skipping"
                    fi
                done
            else
                yush_warn "No DNS announce methods specified."
            fi
            ;;
        "clean")
            if [ -n "$PRIMER_STEP_ANNOUNCE_METHODS" ]; then
                for method in $PRIMER_STEP_ANNOUNCE_METHODS; do
                    if command -v "_primer_step_announce_${method}_remove" >/dev/null 2>&1; then
                        yush_info "Cleaning announcements for method: $method"
                        "_primer_step_announce_${method}_remove"
                    else
                        yush_warn "Announce method $method is not supported, skipping"
                    fi
                done
            else
                yush_warn "No DNS announce methods specified."
            fi
            ;;
    esac
}

_primer_step_announce_mDNS_add() {
    lsb_dist=$(primer_os_distribution)
    case "$lsb_dist" in
        *buntu|*bian|alpine*|clear*linux*)
            primer_os_dependency avahi-daemon avahi-daemon;;
        fedora*)
            primer_os_dependency avahi-daemon avahi;;
        *)
            yush_warn "avahi installation NYI for $lsb_dist";;
    esac
    if command -v "avahi-daemon" >/dev/null 2>&1; then
        primer_os_service start avahi-daemon
        primer_os_service enable avahi-daemon
    fi
}

_primer_step_announce_mDNS_remove() {
    if command -v "avahi-daemon" >/dev/null 2>&1; then
        primer_os_service stop avahi-daemon
        primer_os_service disable avahi-daemon
    fi
}

_primer_step_announce_NetBIOS_add() {
    lsb_dist=$(primer_os_distribution)
    case "$lsb_dist" in
        *buntu|*bian|alpine*|clear*linux*)
            primer_os_dependency nmbd samba;;
        fedora*)
            primer_os_dependency nmbd samba-common-tools;;
        *)
            yush_warn "NetBIOS installation NYI for $lsb_dist";;
    esac
    if command -v "nmbd" >/dev/null 2>&1; then
        primer_os_service start nmbd
        primer_os_service enable nmbd
    fi
}

_primer_step_announce_NetBIOS_remove() {
    if command -v "nmbd" >/dev/null 2>&1; then
        primer_os_service stop nmbd
        primer_os_service disable nmbd
    fi
}
