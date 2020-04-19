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
        yush_info "Updating package indices"
        lsb_dist=$(primer_distribution)
        case "$lsb_dist" in
            ubuntu|*bian)
                DEBIAN_FRONTEND=noninteractive $PRIMER_SUDO apt-get update -y
                ;;
            alpine*)
                $PRIMER_SUDO apk update
                ;;
            clear*linux*)
                $PRIMER_SUDO swupd update
                ;;
            *)
                yush_warn "System update NYI for $lsb_dist";;
        esac
        PRIMER_PKGIDX_UPDATED=1
    fi
}

primer_dependency() {
    if ! [ -x "$(command -v "$1")" ] || [ -z "$1" ]; then
        cmd=$1
        shift

        if [ $# = 0 ]; then
            pkgs="$cmd"
        else
            # shellcheck disable=SC2124
            pkgs="$@"
        fi
        lsb_dist=$(primer_distribution)
        yush_notice "Automatically installing $pkgs for $lsb_dist"
        primer_update
        case "$lsb_dist" in
            ubuntu|*bian)
                # shellcheck disable=SC2086
                DEBIAN_FRONTEND=noninteractive $PRIMER_SUDO apt-get install -y $pkgs
                ;;
            alpine*)
                # shellcheck disable=SC2086
                $PRIMER_SUDO apk add $pkgs
                ;;
            clear*linux*)
                # shellcheck source=yu.sh/log.sh disable=SC2086
                $PRIMER_SUDO swupd bundle-add $pkgs
                ;;
            *)
                yush_warn "Dependency resolution NYI for $lsb_dist";;
        esac
    fi
}
