#!/usr/bin/env sh

# List of packages to install. This is obviously limited by the fact that
# packages are not called the same in all distributions. The variable has the
# PACKAGE word twice because of naming conventions.
PRIMER_STEP_PACKAGES_PACKAGES=${PRIMER_STEP_PACKAGES_PACKAGES:-}

# Should we freshen up the system with all pending and existing upgrades.
PRIMER_STEP_PACKAGES_FRESH=${PRIMER_STEP_PACKAGES_FRESH:-1}

primer_step_packages() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--packages --fresh"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --packages)
                        PRIMER_STEP_PACKAGES_PACKAGES=$2; shift 2;;
                    --fresh)
                        PRIMER_STEP_PACKAGES_FRESH=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            # Update package index in system
            primer_os_update

            # Freshen up system to latest
            if yush_is_true "$PRIMER_STEP_PACKAGES_FRESH"; then
                yush_info "Upgrading and cleaning system"
                primer_os_upgrade
            fi

            if [ -n "$PRIMER_STEP_PACKAGES_PACKAGES" ]; then
                # shellcheck disable=SC2086
                primer_os_packages add $PRIMER_STEP_PACKAGES_PACKAGES
            fi
            ;;
        "clean")
            if [ -n "$PRIMER_STEP_PACKAGES_PACKAGES" ]; then
                # shellcheck disable=SC2086
                primer_os_packages del $PRIMER_STEP_PACKAGES_PACKAGES
            fi
            ;;
    esac
}
