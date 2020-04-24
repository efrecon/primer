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
                        yush_warn "Unknown option: $1 !"; shift 2;;
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
                yush_info "Upgrading and cleaning system"
                primer_upgrade
            fi

            if [ -n "$PACKAGES_PACKAGES" ]; then
                # shellcheck disable=SC2086
                primer_packages add $PACKAGES_PACKAGES
            fi
            ;;
        "clean")
            if [ -n "$PACKAGES_PACKAGES" ]; then
                # shellcheck disable=SC2086
                primer_packages del $PACKAGES_PACKAGES
            fi
            ;;
    esac
}
