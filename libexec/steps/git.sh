#!/usr/bin/env sh

# Version of git LFS to download.
PRIMER_STEP_GIT_LFS_VERSION=${PRIMER_STEP_GIT_LFS_VERSION:-}

# Project of git LFS at GitHub.
PRIMER_STEP_GIT_LFS_PROJECT=git-lfs/git-lfs

# Regular expression matching the name of the regular users on the system that
# should be given access to git LFS. This defaults to all regular users.
PRIMER_STEP_GIT_LFS_INSTALL=${PRIMER_STEP_GIT_LFS_INSTALL:-".*"}

primer_step_git() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--lfs-version --lfs-install"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --lfs-version)
                        PRIMER_STEP_GIT_LFS_VERSION=$2; shift 2;;
                    --lfs-install)
                        PRIMER_STEP_GIT_LFS_INSTALL=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            # Install git, if not already present
            if ! command -v git >/dev/null 2>&1; then
                primer_os_dependency git
            fi
            # Install git-lfs directly from source. This is a go binary, so it
            # will work on all distributions, independently of their libc
            # implementation. Verification failures fail the step.
            if ! command -v "git-lfs" >/dev/null 2>&1; then
                _primer_step_git_lfs_download || return 1
                # Check version
                yush_debug "Verifying installed version against $PRIMER_STEP_GIT_LFS_VERSION"
                if ! command -v "git-lfs" >/dev/null 2>&1; then
                    yush_error "git-lfs could not be installed!"
                    return 1
                elif [ "$(_primer_step_git_lfs_version)" != "$PRIMER_STEP_GIT_LFS_VERSION" ]; then
                    yush_warn "Installed git-lfs version mismatch: $(_primer_step_git_lfs_version)"
                fi
            fi

            if [ -n "$PRIMER_STEP_GIT_LFS_INSTALL" ]; then
                yush_info "Installing LFS for all users on system matching $PRIMER_STEP_GIT_LFS_INSTALL"
                # su is missing from minimal Fedora installations.
                primer_os_dependency su util-linux
                primer_auth_user_list | while IFS= read -r _username || [ -n "$_username" ]; do
                    if printf %s\\n "$_username" | grep -qE "$PRIMER_STEP_GIT_LFS_INSTALL"; then
                        yush_debug "Installing git LFS for $_username"
                        $PRIMER_OS_SUDO su -l "${_username}" -c "git lfs install"
                    fi
                done
            else
                git lfs install
                yush_info "Only current user has git LFS installed"
            fi
            ;;
        "clean")
            # Only remove git LFS when at the version that this step installs:
            # the one requested, or the latest one. Another binary might not
            # have been installed by this step.
            _want=${PRIMER_STEP_GIT_LFS_VERSION:-$(_primer_step_git_lfs_latest)}
            primer_utils_remove_at_version "${PRIMER_BINDIR%%/}/git-lfs" "$_want" _primer_step_git_lfs_version
            ;;
    esac
}

# Print the version of the git LFS binary at $1, git-lfs in the PATH by
# default, e.g. 3.8.1 for "git-lfs/3.8.1 (GitHub; linux amd64; go 1.25)".
_primer_step_git_lfs_version() {
    "${1:-git-lfs}" --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+)+' | head -1
}

# Print the latest version of git LFS, without the leading v.
_primer_step_git_lfs_latest() {
    _latest=$(primer_github_latest "$PRIMER_STEP_GIT_LFS_PROJECT")
    printf %s\\n "${_latest#v}"
}

# Download git LFS at PRIMER_STEP_GIT_LFS_VERSION (the latest when empty) for
# the current platform, verify it against the sha256 sum published with the
# release, check that it runs, and install it. Fails, installing nothing, when
# any of this fails.
_primer_step_git_lfs_download() {
    if [ -z "$PRIMER_STEP_GIT_LFS_VERSION" ]; then
        PRIMER_STEP_GIT_LFS_VERSION=$(_primer_step_git_lfs_latest || true)
        if [ -z "$PRIMER_STEP_GIT_LFS_VERSION" ]; then
            yush_error "Could not discover latest git LFS version"
            return 1
        fi
    fi
    _os=$(uname -s | tr '[:upper:]' '[:lower:]')
    _platform=
    case $(primer_os_platform) in
        x86_64|amd64) _platform=amd64;;
        x86|i?86) _platform=386;;
        aarch64|arm64) _platform=arm64;;
        armv7*|armv6*|arm) _platform=arm;;
    esac
    if [ -z "$_platform" ]; then
        yush_error "Cannot download for this platform!"
        return 1
    fi

    yush_info "Installing git LFS $PRIMER_STEP_GIT_LFS_VERSION"
    primer_github_install --sum sha256sums.asc --check --version --name git-lfs \
        "$PRIMER_STEP_GIT_LFS_PROJECT" "v${PRIMER_STEP_GIT_LFS_VERSION}" \
        "git-lfs-${_os}-${_platform}-v${PRIMER_STEP_GIT_LFS_VERSION}.tar.gz" git-lfs
}
