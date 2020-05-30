#!/usr/bin/env sh

# Locale on system
PRIMER_STEP_LOCALE_LOCALE=${PRIMER_STEP_LOCALE_LOCALE:-"en_US.UTF-8"}

primer_step_locale() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--locale"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --locale)
                        PRIMER_STEP_LOCALE_LOCALE="$2"; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            if command -v locale-gen >/dev/null; then
                $PRIMER_OS_SUDO locale-gen "$PRIMER_STEP_LOCALE_LOCALE"
            fi
            LC_ALL=$PRIMER_STEP_LOCALE_LOCALE
            export LC_ALL
            printf "LC_ALL=%s\\n" $PRIMER_STEP_LOCALE_LOCALE | primer_utils_sysfile_append /etc/environment
            ;;
        "clean")
            [ -f /etc/environment ] && primer_utils_sysfile_clip /etc/environment "LC_ALL=$PRIMER_STEP_LOCALE_LOCALE"
            ;;
    esac
}
