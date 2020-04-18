#!/usr/bin/env sh

# List of packages to install. This is obviously limited by the fact that
# packages are not called the same in all distributions. The variable has the
# PACKAGE word twice because of naming conventions.
PACKAGES_PACKAGES=${PACKAGES_PACKAGES:-}

# Should we freshen up the system with all pending and existing upgrades.
PACKAGES_FRESH=${PACKAGES_FRESH:-1}

packages() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    --packages)
                        PACKAGES_PACKAGES=$2; shift 2;;
                    --fresh)
                        PACKAGES_FRESH=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !";;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            # Update package index in system
            primer_update

            # Freshen up system to latest
            if yush_is_true "$PACKAGES_FRESH"; then
                lsb_dist=$(primer_distribution)
                case "$lsb_dist" in
                    ubuntu|*bian)
                        DEBIAN_FRONTEND=noninteractive $PRIMER_SUDO apt-get upgrade -y -q
                        DEBIAN_FRONTEND=noninteractive $PRIMER_SUDO apt-get dist-upgrade -y -q
                        DEBIAN_FRONTEND=noninteractive $PRIMER_SUDO apt-get autoremove -y -q
                        ;;
                    alpine*)
                        $PRIMER_SUDO apk upgrade;;
                    clear*linux*)
                        $PRIMER_SUDO swupd update;;
                    *)
                        yush_warn "System update NYI for $lsb_dist";;
                esac
            fi

            # shellcheck disable=SC2086
            [ -n "$PACKAGES_PACKAGES" ] && primer_dependency "" $PACKAGES_PACKAGES
            ;;
        "clean")
            if [ -n "$PACKAGES_PACKAGES" ]; then
                lsb_dist=$(primer_distribution)
                case "$lsb_dist" in
                    ubuntu|*bian)
                        # shellcheck disable=SC2086
                        DEBIAN_FRONTEND=noninteractive $PRIMER_SUDO apt-get remove -y -q $PACKAGES_PACKAGES
                        ;;
                    alpine*)
                        # shellcheck disable=SC2086
                        $PRIMER_SUDO apk del $PACKAGES_PACKAGES
                        ;;
                    clear*linux*)
                        # shellcheck disable=SC2086
                        $PRIMER_SUDO swupd bundle-remove $PACKAGES_PACKAGES
                        ;;
                    *)
                        yush_warn "Package removal NYI for $lsb_dist";;
                esac
            fi
            ;;
    esac
}
