#!/usr/bin/env sh

# Root directory where to find scripts, progs to run. The directory should have
# two under directories called install and clean
PRIMER_STEP_FREEFORM_ROOT=${PRIMER_STEP_FREEFORM_ROOT:-}

# Filter to scripts to install/remove
PRIMER_STEP_FREEFORM_FILTER=${PRIMER_STEP_FREEFORM_FILTER:-"*.sh"}

# Should we run operations as system user
PRIMER_STEP_FREEFORM_SUDO=${PRIMER_STEP_FREEFORM_SUDO:-1}

primer_step_freeform() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--root --filter --sudo"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --root)
                        PRIMER_STEP_FREEFORM_ROOT=$2; shift 2;;
                    --filter)
                        PRIMER_STEP_FREEFORM_FILTER=$2; shift 2;;
                    --sudo)
                        PRIMER_STEP_FREEFORM_SUDO=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install" | "clean")
            if [ -n "$PRIMER_STEP_FREEFORM_ROOT" ] && [ -d "$PRIMER_STEP_FREEFORM_ROOT" ]; then
                if [ -d "${PRIMER_STEP_FREEFORM_ROOT%/}/$1" ]; then
                    yush_notice "${1}ing all files matching $PRIMER_STEP_FREEFORM_FILTER under ${PRIMER_STEP_FREEFORM_ROOT%/}/$1"
                    find "${PRIMER_STEP_FREEFORM_ROOT%/}/$1" \
                            -maxdepth 1 \
                            -mindepth 1 \
                            -executable \
                            -name "$PRIMER_STEP_FREEFORM_FILTER" |
                        sort |
                        while IFS= read -r fpath || [ -n "$fpath" ]; do
                            yush_info "${1}ing $fpath"
                            if yush_is_true "$PRIMER_STEP_FREEFORM_SUDO"; then
                                yush_info "Running $fpath as administrator"
                                $PRIMER_OS_SUDO "$fpath"
                            else
                                yush_info "Running $fpath"
                                "$fpath"
                            fi
                        done
                else
                    yush_warn "No $1 directory under $PRIMER_STEP_FREEFORM_ROOT"
                fi
            fi
            ;;
    esac
}
