#!/usr/bin/env sh

# handle following scenarios:
#   * unprivileged user (i.e. not root, sudo not used)
#   * privileged user (i.e. not root, sudo used)
#   * root user (i.e. sudo not used)
PRIMER_OS_SUDO=''
primer_os_sudo() {
    if [ "$(id -u)" -ne "0" ]; then
        # verify that 'sudo' is present before assuming we can use it
        if ! [ -x "$(which sudo 2>/dev/null)" ]; then
            primer_abort "Cannot find sudo"
        fi

        PRIMER_OS_SUDO='sudo'
    fi
}

# Get platform, this supposes linux and intel
primer_os_platform() {
    if [ "$(getconf LONG_BIT)" = "64" ]; then
        echo "x86_64"
    else
        echo "x86"
    fi
}

PRIMER_OS_DISTRO=""
primer_os_distribution() {
    if [ -z "$PRIMER_OS_DISTRO" ]; then
        lsb_dist=""
        # Every system that we officially support has /etc/os-release
        if [ -r /etc/os-release ]; then
            # shellcheck disable=SC1091
            lsb_dist="$(. /etc/os-release && echo "$ID")"
        fi
        # Returning an empty string here should be alright since the
        # case statements don't act unless you provide an actual value
        PRIMER_OS_DISTRO=$(printf %s\\n "$lsb_dist" | tr '[:upper:]' '[:lower:]')
    fi
    printf %s\\n "$PRIMER_OS_DISTRO"
}

PRIMER_OS_VERSION=""
primer_os_version() {
    if [ -z "$PRIMER_OS_VERSION" ]; then
        _version=""
        # Every system that we officially support has /etc/os-release
        if [ -r /etc/os-release ]; then
            # shellcheck disable=SC1091
            _version="$(. /etc/os-release && echo "$VERSION_ID")"
        fi
        PRIMER_OS_VERSION=$(printf %s\\n "$_version" | tr '[:upper:]' '[:lower:]')
    fi
    printf %s\\n "$PRIMER_OS_VERSION"
}

primer_os_init() {
    primer_os_sudo
    # Initialise caches, don't run in sub-shells.
    primer_os_distribution > /dev/null
    primer_os_version > /dev/null
    yush_info "Discovered OS as: $PRIMER_OS_DISTRO v$PRIMER_OS_VERSION"
}

PRIMER_OS_PKGIDX_UPDATED=${PRIMER_OS_PKGIDX_UPDATED:-"0"}
primer_os_update() {
    if [ "$PRIMER_OS_PKGIDX_UPDATED" = "0" ]; then
        yush_info "Updating OS package indices (if relevant)"
        lsb_dist=$(primer_os_distribution)
        case "$lsb_dist" in
            *buntu)
                _primer_os_apt update;;
            *bian)
                _primer_os_apt update;;
            alpine*)
                _primer_os_apk update;;
            clear*linux*)
                # Clear linux has no index
                ;;
            *)
                yush_warn "System update NYI for $lsb_dist";;
        esac
        PRIMER_OS_PKGIDX_UPDATED=1
    fi
}

PRIMER_OS_UPGRADED=${PRIMER_OS_UPGRADED:-"0"}
primer_os_upgrade() {
    # Update indices
    primer_os_update
    if [ "$PRIMER_OS_UPGRADED" = "0" ] || [ "$1" = "-f" ] || [ "$1" = "--force" ]; then
        yush_info "Unattended upgrade of the OS (this might take time!)"
        lsb_dist=$(primer_os_distribution)
        case "$lsb_dist" in
            *buntu)
                _primer_os_apt upgrade
                _primer_os_apt autoremove
                ;;
            *bian)
                _primer_os_apt upgrade
                _primer_os_apt autoremove
                ;;
            alpine*)
                _primer_os_apk upgrade
                ;;
            clear*linux*)
                _primer_os_swupd update
                ;;
            *)
                yush_warn "System upgrade NYI for $lsb_dist";;
        esac
        PRIMER_OS_UPGRADED=1
    fi
}

primer_os_dependency() {
    if ! command -v "$1" >/dev/null 2>&1 || [ -z "$1" ]; then
        cmd=$1
        shift

        if [ $# = 0 ]; then
            primer_os_packages add "$cmd"
        else
            primer_os_packages add "$@"
        fi
    fi
}

primer_os_packages() {
    lsb_dist=$(primer_os_distribution)
    case "$1" in
        add|install)
            # Add one or more packages
            shift
            yush_info "Installing packages: $*"
            # Construct a list of packages that haven't been installed yet.
            _install=
            for pkg in "$@"; do
                if primer_os_packages installed "$pkg"; then
                    yush_debug "Package: $pkg already installed"
                else
                    _install="$_install $pkg"
                fi
            done
            # Install packages that are not yet present
            if [ -n "$_install" ]; then
                primer_os_update
                case "$lsb_dist" in
                    *bian)
                        # shellcheck disable=SC2086
                        _primer_os_apt install $_install;;
                    *buntu)
                        # shellcheck disable=SC2086
                        _primer_os_apt install $_install;;
                    alpine*)
                        # shellcheck disable=SC2086
                        _primer_os_apk add $_install;;
                    clear*linux*)
                        # shellcheck source=yu.sh/log.sh disable=SC2086
                        _primer_os_swupd bundle-add $_install;;
                    *)
                        yush_warn "Dependency resolution NYI for $lsb_dist";;
                esac
            fi
            ;;
        del*|remove|uninstall)
            # Remove one or more packages
            shift
            yush_info "Removing packages: $*"
            case "$lsb_dist" in
                *buntu)
                    # shellcheck disable=SC2086
                    _primer_os_apt remove "$@"
                    yush_debug "Cleaning orphan packages"
                    _primer_os_apt autoremove
                    ;;
                *bian)
                    # shellcheck disable=SC2086
                    _primer_os_apt remove "$@"
                    yush_debug "Cleaning orphan packages"
                    _primer_os_apt autoremove
                    ;;
                alpine*)
                    # shellcheck disable=SC2086
                    _primer_os_apk del "$@"
                    ;;
                clear*linux*)
                    # shellcheck disable=SC2086
                    _primer_os_swupd bundle-remove "$@"
                    ;;
                *)
                    yush_warn "Package removal NYI for $lsb_dist";;
            esac
            ;;
        list)
            # List installed packages
            case "$lsb_dist" in
                *buntu)
                    $PRIMER_OS_SUDO dpkg --get-selections | grep -v deinstall | awk '{print $1}'
                    ;;
                *bian)
                    $PRIMER_OS_SUDO dpkg --get-selections | grep -v deinstall | awk '{print $1}'
                    ;;
                alpine*)
                    _primer_os_apk list -I 2>/dev/null | awk '{print $1}'
                    ;;
                clear*linux*)
                    $PRIMER_OS_SUDO swupd bundle-list --status | grep installed | awk '{print $2}'
                    ;;
                *)
                    yush_warn "Package removal NYI for $lsb_dist";;
            esac
            ;;
        installed)
            # Is package passed as argument installed
            shift
            primer_os_packages list | grep -q "^$1"
            ;;
        search)
            case "$lsb_dist" in
                *buntu)
                    $PRIMER_OS_SUDO apt-cache search "$1" |
                        sed -E 's/([[:alnum:]\-_]+)\s+-\s*.*/\1/' |
                        grep "^$1\$"
                    ;;
                *bian)
                    $PRIMER_OS_SUDO apt-cache search "$1" |
                        sed -E 's/([[:alnum:]\-_]+)\s+-\s*.*/\1/' |
                        grep "^$1\$"
                    ;;
                alpine*)
                    _primer_os_apk search -x "$1"
                    ;;
                clear*linux*)
                    _primer_os_swupd search "$1" |
                        grep -E '\s+\-\s+' |
                        awk '{print $1}'
                    ;;
                *)
                    yush_warn "Package search for $lsb_dist";;
            esac
            ;;
    esac
}

# Detect if running within a container
primer_os_in_container() { grep -qE '(docker|lxc)' /proc/1/cgroup; }

primer_os_service() {
    if printf %s\\n "$1" | grep -qE '(start|stop|enable|disable|restart|list)'; then
        if primer_os_in_container; then
            yush_notice "Service $2 $1 is not relevant in a container"
        else
            if [ -x "$(command -v systemctl)" ]; then
                if [ "$1" = "list" ]; then
                    $PRIMER_OS_SUDO systemctl --no-pager --no-legend list-units ${2:-*}.service | awk '{print $1}' | sed -E 's/(.*)\.service$/\1/'
                else
                    # We also (un)mask when enabling/disabling. See:
                    # https://stackoverflow.com/a/39109593
                    case "$1" in
                        disable)
                            $PRIMER_OS_SUDO systemctl "$1" "$2"
                            $PRIMER_OS_SUDO systemctl mask "$2"
                            ;;
                        enable)
                            $PRIMER_OS_SUDO systemctl unmask "$2"
                            $PRIMER_OS_SUDO systemctl "$1" "$2"
                            ;;
                        *)
                            $PRIMER_OS_SUDO systemctl "$1" "$2"
                            ;;
                    esac
                fi
            elif [ -x "$(command -v service)" ]; then
                if [ "$1" = "list" ]; then
                    $PRIMER_OS_SUDO service --status-all | sed -E 's/^\s*\[\s*.\s*\]\s*(.*)/\1/'
                else
                    $PRIMER_OS_SUDO service "$1" "$2"
                fi
            elif [ -x "$(command -v rc-service)" ]; then
                case "$1" in
                    start|stop|restart)
                        $PRIMER_OS_SUDO rc-service "$2" "$1";;
                    enable)
                        $PRIMER_OS_SUDO rc-update add "$2";;
                    disable)
                        $PRIMER_OS_SUDO rc-update del "$2";;
                    list)
                        $PRIMER_OS_SUDO rc-service -l;;
                esac
            else
                yush_error "Only service, systemctl (systemd) or alpine are supported for daemons"
            fi
        fi
    else
        yush_warn "$1 is not a known command"
    fi
}

primer_os_bash_completion_dir() {
    lsb_dist=$(primer_os_distribution)
        case "$lsb_dist" in
        clear*linux*)
            _completion_dir=/usr/share/bash-completion/completions;;
        *)
            _completion_dir=/etc/bash_completion.d;;
    esac
    printf %s\\n "$_completion_dir"
}

_primer_os_apk() {
    cmd=$1; shift
    if yush_loglevel_le debug; then
        $PRIMER_OS_SUDO apk "$cmd" "$@"
    else
        $PRIMER_OS_SUDO apk "$cmd" -q "$@"
    fi
}

_primer_os_apt() {
    cmd=$1; shift
    if [ -z "$PRIMER_OS_SUDO" ]; then
        if yush_loglevel_le debug; then
            DEBIAN_FRONTEND=noninteractive apt-get "$cmd" -y -q "$@"
        else
            DEBIAN_FRONTEND=noninteractive apt-get "$cmd" -y -qq "$@" > /dev/null
        fi
    else
        if yush_loglevel_le debug; then
            DEBIAN_FRONTEND=noninteractive $PRIMER_OS_SUDO --preserve-env=DEBIAN_FRONTEND apt-get "$cmd" -y -q "$@"
        else
            DEBIAN_FRONTEND=noninteractive $PRIMER_OS_SUDO --preserve-env=DEBIAN_FRONTEND apt-get "$cmd" -y -qq "$@" > /dev/null
        fi
    fi
}

_primer_os_swupd() {
    cmd=$1; shift
    if yush_loglevel_le debug; then
        $PRIMER_OS_SUDO swupd "$cmd" --assume=yes "$@"
    else
        $PRIMER_OS_SUDO swupd "$cmd" --assume=yes --quiet "$@"
    fi
}