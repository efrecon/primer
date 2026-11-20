#!/usr/bin/env sh

# Branch of machinery to install, also the name of the directory where it is
# installed: branches coexist, each in its own directory.
PRIMER_STEP_MACHINERY_BRANCH=${PRIMER_STEP_MACHINERY_BRANCH:-master}

# Commit of machinery to install, verified by git: the tip of master when this
# version of primer was released. Empty to install the tip of the branch,
# unverified.
PRIMER_STEP_MACHINERY_COMMIT=${PRIMER_STEP_MACHINERY_COMMIT-9eadd4fd1c226ec14e5420d18f3b63ec571e7a3a}

PRIMER_STEP_MACHINERY_REPO=https://github.com/efrecon/machinery.git

primer_step_machinery() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--branch --commit"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --branch)
                        PRIMER_STEP_MACHINERY_BRANCH=$2; shift 2;;
                    --commit)
                        PRIMER_STEP_MACHINERY_COMMIT=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            [ -z "$PRIMER_STEP_MACHINERY_BRANCH" ] && PRIMER_STEP_MACHINERY_BRANCH=master
            _dir="${PRIMER_OPTDIR%%/}/machinery/$PRIMER_STEP_MACHINERY_BRANCH"
            _link="${PRIMER_BINDIR%%/}/machinery"
            # Branches coexist, each in its own directory.
            if ! [ -d "$_dir/.git" ]; then
                lsb_dist=$(primer_os_distribution)
                case "$lsb_dist" in
                    alpine*)
                        primer_os_packages add tcl tclx tcl-tls tcl-lib;;
                    clear*linux*)
                        primer_os_packages add tcl-basic;;
                    *buntu)
                        primer_os_packages add tcl tclx tcl-tls tcllib tcllib-critcl tcl-vfs;;
                    *bian)
                        primer_os_packages add tcl tclx tcl-tls tcllib tcllib-critcl tcl-vfs;;
                    fedora*)
                        primer_os_packages add tcl tclx tcltls tcl8-tcllib tcl-tclvfs;;
                    *)
                        ;;
                esac
            fi
            # At the commit, when given: an existing checkout moves to it.
            yush_info "Installing machinery from $PRIMER_STEP_MACHINERY_REPO (branch: $PRIMER_STEP_MACHINERY_BRANCH, commit: ${PRIMER_STEP_MACHINERY_COMMIT:-none})"
            primer_net_git_clone "$PRIMER_STEP_MACHINERY_REPO" "$PRIMER_STEP_MACHINERY_BRANCH" \
                "$PRIMER_STEP_MACHINERY_COMMIT" "$_dir" || return 1
            $PRIMER_OS_SUDO chmod a+x "$_dir/machinery"
            # Point the link to the branch, unless machinery was installed
            # otherwise.
            if [ -e "$_link" ] && ! [ -L "$_link" ]; then
                yush_warn "$_link is not a link, leaving it alone"
            elif [ "$(readlink "$_link" 2>/dev/null)" != "$_dir/machinery" ]; then
                yush_debug "Installing as $_link"
                [ -d "$PRIMER_BINDIR" ] || $PRIMER_OS_SUDO mkdir -p "$PRIMER_BINDIR"
                $PRIMER_OS_SUDO ln -sf "$_dir/machinery" "$_link"
                yush_debug "Installed machinery version $("$_link" version)"
            fi
            ;;
        "clean")
            [ -z "$PRIMER_STEP_MACHINERY_BRANCH" ] && PRIMER_STEP_MACHINERY_BRANCH=master
            _dir="${PRIMER_OPTDIR%%/}/machinery/$PRIMER_STEP_MACHINERY_BRANCH"
            _link="${PRIMER_BINDIR%%/}/machinery"
            # Only remove the link when it points to the branch being cleaned.
            if [ -L "$_link" ] && [ "$(readlink "$_link")" = "$_dir/machinery" ]; then
                yush_info "Removing $_link"
                $PRIMER_OS_SUDO rm -f "$_link"
            fi
            if [ -d "$_dir" ]; then
                yush_info "Removing $_dir"
                $PRIMER_OS_SUDO rm -rf "$_dir"
                # Remove the parent directory when it is empty
                $PRIMER_OS_SUDO rmdir "${PRIMER_OPTDIR%%/}/machinery" 2>/dev/null || true
            fi
            ;;
    esac
}
