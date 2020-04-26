#!/usr/bin/env sh

# Version of machinery to download. Can be set from the
# outside, defaults to empty, meaning the latest as per the variable below.
PRIMER_STEP_MACHINERY_BRANCH=${PRIMER_STEP_MACHINERY_BRANCH:-master}

PRIMER_STEP_MACHINERY_REPO=https://github.com/efrecon/machinery.git

primer_step_machinery() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    --branch)
                        PRIMER_STEP_MACHINERY_BRANCH=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            if ! [ -x "$(command -v "machinery")" ]; then
                [ -z "$PRIMER_STEP_MACHINERY_BRANCH" ] && PRIMER_STEP_MACHINERY_BRANCH=master
                lsb_dist=$(primer_os_distribution)
                case "$lsb_dist" in
                    alpine)
                        primer_os_packages add tcl tclx tcl-tls tcllib
                        ;;
                    clear*linux*)
                        primer_os_packages add tcl-basic
                        ;;
                    ubuntu|*bian)
                        primer_os_packages add tcl tclx tcl-tls tcllib tcllib-critcl tcl-vfs
                        ;;
                    *)
                        ;;
                esac
                primer_os_dependency git
                yush_info "Installing machinery from $PRIMER_STEP_MACHINERY_REPO (branch: $PRIMER_STEP_MACHINERY_BRANCH)"
                $PRIMER_OS_SUDO mkdir -p "${PRIMER_OPTDIR%%/}/machinery/$PRIMER_STEP_MACHINERY_BRANCH"
                $PRIMER_OS_SUDO git clone "$PRIMER_STEP_MACHINERY_REPO" \
                                --recurse \
                                --branch "$PRIMER_STEP_MACHINERY_BRANCH" \
                                --depth 1 \
                                "${PRIMER_OPTDIR%%/}/machinery/$PRIMER_STEP_MACHINERY_BRANCH"
                yush_debug "Installing as ${PRIMER_BINDIR%%/}/machinery"
                $PRIMER_OS_SUDO chmod a+x "${PRIMER_OPTDIR%%/}/machinery/$PRIMER_STEP_MACHINERY_BRANCH/machinery"
                $PRIMER_OS_SUDO ln -s "${PRIMER_OPTDIR%%/}/machinery/$PRIMER_STEP_MACHINERY_BRANCH/machinery" "${PRIMER_BINDIR%%/}/machinery"
                yush_debug "Installed machinery version $("${PRIMER_BINDIR%%/}/machinery" version)"
            fi
            ;;
        "clean")
            if [ -f "${PRIMER_BINDIR%%/}/machinery" ]; then
                yush_info "Removing ${PRIMER_BINDIR%%/}/machinery"
                $PRIMER_OS_SUDO rm -f "${PRIMER_BINDIR%%/}/machinery"
            fi
            if [ -d "${PRIMER_OPTDIR%%/}/machinery/$PRIMER_STEP_MACHINERY_BRANCH" ]; then
                yush_info "Removing ${PRIMER_OPTDIR%%/}/machinery/$PRIMER_STEP_MACHINERY_BRANCH"
                $PRIMER_OS_SUDO rm -f "${PRIMER_OPTDIR%%/}/machinery/$PRIMER_STEP_MACHINERY_BRANCH"
            fi
            ;;
    esac
}
