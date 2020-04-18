#!/usr/bin/env sh

# List of packages to install. This is obviously limited by the fact that
# packages are not called the same in all distributions. The variable has the
# PACKAGE word twice because of naming conventions.
PACKAGES_PACKAGES=${PACKAGES_PACKAGES:-}

packages() {
    case "$1" in
        "install")
            # Update package index in system
            primer_update

            # Freshen up system to latest
            lsb_dist=$(primer_distribution)
            case "$lsb_dist" in
                ubuntu|*bian)
                    $PRIMER_SUDO apt-get upgrade -y -q
                    $PRIMER_SUDO apt-get dist-upgrade -y -q
                    $PRIMER_SUDO apt-get autoremove -y -q
                    ;;
                alpine*)
                    $PRIMER_SUDO apk upgrade
                    ;;
                clear*linux*)
                    $PRIMER_SUDO swupd update
                    ;;
            esac

            # shellcheck disable=SC2086
            [ -n "$PACKAGES_PACKAGES" ] && primer_dependency "" $PACKAGES_PACKAGES
            ;;
        "clean")
            if [ -n "$PACKAGES_PACKAGES" ]; then
                lsb_dist=$(primer_distribution)
                case "$lsb_dist" in
                    ubuntu|*bian)
                        # shellcheck disable=SC2086
                        $PRIMER_SUDO apt-get remove -y -q $PACKAGES_PACKAGES
                        ;;
                    alpine*)
                        # shellcheck disable=SC2086
                        $PRIMER_SUDO apk del $PACKAGES_PACKAGES
                        ;;
                    clear*linux*)
                        # shellcheck disable=SC2086
                        $PRIMER_SUDO swupd bundle-remove $PACKAGES_PACKAGES
                        ;;
                esac
            fi
            ;;
    esac
}
