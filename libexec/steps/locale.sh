#!/usr/bin/env sh

# Locale to set on the system, e.g. en_US.UTF-8
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
            _primer_step_locale_generate "$PRIMER_STEP_LOCALE_LOCALE"
            LC_ALL=$PRIMER_STEP_LOCALE_LOCALE
            export LC_ALL
            # Replace any existing LC_ALL setting, so this can be run several
            # times, or with another locale.
            if [ -f /etc/environment ] && grep -q '^LC_ALL=' /etc/environment; then
                if grep -qxF "LC_ALL=$PRIMER_STEP_LOCALE_LOCALE" /etc/environment; then
                    yush_debug "Locale $PRIMER_STEP_LOCALE_LOCALE already set in /etc/environment"
                    return 0
                fi
                primer_utils_sysfile_clip /etc/environment '^LC_ALL='
            fi
            yush_info "Setting locale to $PRIMER_STEP_LOCALE_LOCALE in /etc/environment"
            printf "LC_ALL=%s\\n" "$PRIMER_STEP_LOCALE_LOCALE" | primer_utils_sysfile_append /etc/environment
            ;;
        "clean")
            if [ -f /etc/environment ]; then
                primer_utils_sysfile_clip /etc/environment "^LC_ALL=$(yush_regex_escape "$PRIMER_STEP_LOCALE_LOCALE")\$"
            fi
            ;;
    esac
}

# Generate the locale passed as an argument, when the system supports it. On
# Debian, the locales package is installed and the locale enabled in
# /etc/locale.gen. Ubuntu's locale-gen takes the locale as an argument. Other
# distributions (e.g. Alpine with musl) have no locale generation.
_primer_step_locale_generate() {
    lsb_dist=$(primer_os_distribution)
    case "$lsb_dist" in
        *bian)
            primer_os_dependency locale-gen locales
            if [ -f /etc/locale.gen ]; then
                _rx=$(yush_regex_escape "$1")
                if grep -qE "^#[[:space:]]*${_rx}[[:space:]]" /etc/locale.gen; then
                    yush_debug "Enabling $1 in /etc/locale.gen"
                    $PRIMER_OS_SUDO sed -i -E "s/^#[[:space:]]*(${_rx}[[:space:]])/\\1/" /etc/locale.gen
                elif ! grep -qE "^${_rx}[[:space:]]" /etc/locale.gen; then
                    printf '%s %s\n' "$1" "${1#*.}" | primer_utils_sysfile_append /etc/locale.gen
                fi
            fi
            $PRIMER_OS_SUDO locale-gen
            ;;
        *buntu)
            primer_os_dependency locale-gen locales
            $PRIMER_OS_SUDO locale-gen "$1"
            ;;
        *)
            if primer_utils_syscmd_exists locale-gen; then
                $PRIMER_OS_SUDO locale-gen "$1"
            else
                yush_debug "No locale generation on $lsb_dist"
            fi
            ;;
    esac
}
