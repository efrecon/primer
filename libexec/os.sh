#!/usr/bin/env sh

# handle following scenarios:
#   * unprivileged user (i.e. not root, sudo not used)
#   * privileged user (i.e. not root, sudo used)
#   * root user (i.e. sudo not used)
PRIMER_SUDO=''
primer_sudo() {
    if [ "$(id -u)" -ne "0" ]; then
        # verify that 'sudo' is present before assuming we can use it
        if ! [ -x "$(which sudo 2>/dev/null)" ]; then
            primer_abort "Cannot find sudo"
        fi

        PRIMER_SUDO='sudo'
    fi
}

# Get platform, this supposes linux and intel
primer_platform() {
    if [ "$(getconf LONG_BIT)" = "64" ]; then
        echo "x86_64"
    else
        echo "x86"
    fi
}

primer_distribution() {
	lsb_dist=""
	# Every system that we officially support has /etc/os-release
	if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi
	# Returning an empty string here should be alright since the
	# case statements don't act unless you provide an actual value
	printf %s\\n "$lsb_dist" | tr '[:upper:]' '[:lower:]'
}

PRIMER_PKGIDX_UPDATED=${PRIMER_PKGIDX_UPDATED:-"0"}
primer_update() {
    if [ "$PRIMER_PKGIDX_UPDATED" = "0" ]; then
        yush_info "Updating OS package indices (if relevant)"
        lsb_dist=$(primer_distribution)
        case "$lsb_dist" in
            ubuntu|*bian)
                _primer_apt update
                ;;
            alpine*)
                _primer_apk update
                ;;
            clear*linux*)
                # Clear linux has no index
                ;;
            *)
                yush_warn "System update NYI for $lsb_dist";;
        esac
        PRIMER_PKGIDX_UPDATED=1
    fi
}

PRIMER_UPGRADED=${PRIMER_UPGRADED:-"0"}
primer_upgrade() {
    # Update indices
    primer_update
    if [ "$PRIMER_UPGRADED" = "0" ] || [ "$1" = "-f" ] || [ "$1" = "--force" ]; then
        yush_info "Unattended upgrade of the OS (this might take time!)"
        lsb_dist=$(primer_distribution)
        case "$lsb_dist" in
            ubuntu|*bian)
                _primer_apt upgrade
                _primer_apt autoremove
                ;;
            alpine*)
                _primer_apk upgrade
                ;;
            clear*linux*)
                _primer_swupd update
                ;;
            *)
                yush_warn "System upgrade NYI for $lsb_dist";;
        esac
        PRIMER_UPGRADED=1
    fi
}

primer_dependency() {
    if ! [ -x "$(command -v "$1")" ] || [ -z "$1" ]; then
        cmd=$1
        shift

        if [ $# = 0 ]; then
            primer_packages add "$cmd"
        else
            primer_packages add "$@"
        fi
    fi
}

primer_packages() {
    lsb_dist=$(primer_distribution)
    case "$1" in
        add|install)
            shift
            yush_info "Installing packages: $*"
            primer_update
            case "$lsb_dist" in
                ubuntu|*bian)
                    # shellcheck disable=SC2086
                    _primer_apt install "$@"
                    ;;
                alpine*)
                    # shellcheck disable=SC2086
                    _primer_apk add "$@"
                    ;;
                clear*linux*)
                    # shellcheck source=yu.sh/log.sh disable=SC2086
                    _primer_swupd bundle-add "$@"
                    ;;
                *)
                    yush_warn "Dependency resolution NYI for $lsb_dist";;
            esac
            ;;
        del*|remove|uninstall)
            shift
            yush_info "Removing packages: $*"
            case "$lsb_dist" in
                ubuntu|*bian)
                    # shellcheck disable=SC2086
                    _primer_apt remove "$@"
                    yush_debug "Cleaning orphan packages"
                    _primer_apt autoremove
                    ;;
                alpine*)
                    # shellcheck disable=SC2086
                    _primer_apk del "$@"
                    ;;
                clear*linux*)
                    # shellcheck disable=SC2086
                    _primer_swupd bundle-remove "$@"
                    ;;
                *)
                    yush_warn "Package removal NYI for $lsb_dist";;
            esac
            ;;
    esac
}

# Detect if running within a container
primer_in_container() { grep -q -E '(docker|lxc)' /proc/1/cgroup; }

primer_service() {
    if printf %s\\n "$1" | grep -qE '(start|stop|enable|disable|restart)'; then
        if primer_in_container; then
            yush_notice "Service $2 $1 is not relevant in a container"
        else
            if [ -x "$(command -v service)" ]; then
                $PRIMER_SUDO service "$1" "$2"
            elif [ -x "$(command -v systemctl)" ]; then
                $PRIMER_SUDO systemctl "$1" "$2"
            elif [ -x "$(command -v rc-service)" ]; then
                case "$1" in
                    start|stop|restart)
                        $PRIMER_SUDO rc-service "$2" "$1";;
                    enable)
                        $PRIMER_SUDO rc-update add "$2";;
                    disable)
                        $PRIMER_SUDO rc-update del "$2";;
                esac
            else
                yush_error "Only service, systemctl (systemd) or alpine are supported for daemons"
            fi
        fi
    else
        yush_warn "$1 is not a known command"
    fi
}

primer_bash_completion_dir() {
    lsb_dist=$(primer_distribution)
        case "$lsb_dist" in
        clear*linux*)
            _completion_dir=/usr/share/bash-completion/completions;;
        *)
            _completion_dir=/etc/bash_completion.d;;
    esac
    printf %s\\n "$_completion_dir"
}

_primer_apk() {
    cmd=$1; shift
    if yush_loglevel_le debug; then
        $PRIMER_SUDO apk "$cmd" "$@" 
    else
        $PRIMER_SUDO apk "$cmd" -q "$@"
    fi
}

_primer_apt() {
    cmd=$1; shift
    if yush_loglevel_le debug; then
        DEBIAN_FRONTEND=noninteractive $PRIMER_SUDO apt-get "$cmd" -y -q "$@" 
    else
        DEBIAN_FRONTEND=noninteractive $PRIMER_SUDO apt-get "$cmd" -y -qq "$@" > /dev/null
    fi
}

_primer_swupd() {
    cmd=$1; shift
    if yush_loglevel_le debug; then
        $PRIMER_SUDO swupd "$cmd" --assume=yes "$@" 
    else
        $PRIMER_SUDO swupd "$cmd" --assume=yes --quiet "$@"
    fi

}