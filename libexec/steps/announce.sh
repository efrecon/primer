#!/usr/bin/env sh

# Announce methods
PRIMER_STEP_ANNOUNCE_METHODS=${PRIMER_STEP_ANNOUNCE_METHODS:-"mDNS NetBIOS"}

# Set once --method has been used: the first --method replaces the default set
# of methods, further ones are added to it.
_PRIMER_STEP_ANNOUNCE_METHOD_SET=0

primer_step_announce() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--method --methods"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --method)
                        if [ "$_PRIMER_STEP_ANNOUNCE_METHOD_SET" = "0" ]; then
                            PRIMER_STEP_ANNOUNCE_METHODS=
                            _PRIMER_STEP_ANNOUNCE_METHOD_SET=1
                        fi
                        # shellcheck disable=SC2086 # Split methods, one per line
                        if ! printf '%s\n' $PRIMER_STEP_ANNOUNCE_METHODS | grep -qixF -- "$2"; then
                            PRIMER_STEP_ANNOUNCE_METHODS="${PRIMER_STEP_ANNOUNCE_METHODS:+$PRIMER_STEP_ANNOUNCE_METHODS }$2"
                        fi
                        shift 2;;
                    --methods)
                        PRIMER_STEP_ANNOUNCE_METHODS=$2
                        _PRIMER_STEP_ANNOUNCE_METHOD_SET=1
                        shift 2;;
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
                _ports=
                case "$(printf %s\\n "$method" | tr '[:upper:]' '[:lower:]')" in
                    mdns)
                        _daemon=avahi-daemon
                        _ports=5353/udp
                        case "$lsb_dist" in
                            *buntu|*bian)
                                _pkg=avahi-daemon;;
                            fedora*|alpine*|clear*linux*)
                                _pkg=avahi;;
                        esac
                        ;;
                    netbios)
                        _daemon=nmbd
                        _ports="137/udp 138/udp"
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
                    if primer_utils_syscmd_exists "$_daemon"; then
                        _primer_step_announce_ports install "$_ports"
                    fi
                else
                    yush_info "Cleaning announcements for method: $method"
                    _primer_step_announce_uninstall "$_daemon"
                    _primer_step_announce_ports clean "$_ports"
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

# Stop the daemon $1 and disable it at boot. The package providing it is kept:
# it might have been installed before primer, e.g. Samba on a file server.
_primer_step_announce_uninstall() {
    if primer_utils_syscmd_exists "$1"; then
        primer_os_service stop "$1"
        primer_os_service disable "$1"
    fi
}

# Open ($1 is install) or close ($1 is clean) the ports $2 in the active
# firewall, if any. This uses the firewall step with its own marker, so that
# only the rules opened by this step are ever removed.
_primer_step_announce_ports() {
    _fw=$(primer_net_active_firewall)
    if [ -z "$_fw" ]; then
        yush_debug "No active firewall, no port to handle"
        return 0
    fi
    primer_utils_loadif firewall
    (
        # shellcheck disable=SC2034 # Used by the firewall step
        PRIMER_STEP_FIREWALL_TYPE=$_fw
        # shellcheck disable=SC2034
        PRIMER_STEP_FIREWALL_PORTS=$2
        # shellcheck disable=SC2034
        PRIMER_STEP_FIREWALL_MARKER=primer-announce
        primer_step_firewall "$1"
    )
}
