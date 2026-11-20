#!/usr/bin/env sh

# Version of git LFS to download.
PRIMER_STEP_GIT_LFS_VERSION=${PRIMER_STEP_GIT_LFS_VERSION:-}

# URL to JSON file where to find the list of releases of git LFS. The code only
# supports github API.
PRIMER_STEP_GIT_LFS_RELEASES=https://api.github.com/repos/git-lfs/git-lfs/releases

# Root URL to download location
PRIMER_STEP_GIT_LFS_DOWNLOAD=https://github.com/git-lfs/git-lfs/releases/download

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
            _lfs="${PRIMER_BINDIR%%/}/git-lfs"
            if [ -f "$_lfs" ]; then
                _want=${PRIMER_STEP_GIT_LFS_VERSION:-$(_primer_step_git_lfs_latest || true)}
                _have=$(_primer_step_git_lfs_version "$_lfs")
                if [ -n "$_want" ] && [ "$_have" = "$_want" ]; then
                    yush_info "Removing git LFS $_have"
                    $PRIMER_OS_SUDO rm -f "$_lfs"
                else
                    yush_warn "Keeping $_lfs, at version ${_have:-unknown}, not installed by primer (version ${_want:-unknown})"
                fi
            fi
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
    # Following uses the github API
    # https://developer.github.com/v3/repos/releases/#list-releases-for-a-repository
    # for getting the list of latest releases.
    yush_notice "Discovering latest git LFS version from $PRIMER_STEP_GIT_LFS_RELEASES"
    primer_net_curl "$PRIMER_STEP_GIT_LFS_RELEASES" |
        grep -E '"name"[[:space:]]*:[[:space:]]*"v[0-9]+(\.[0-9]+)*"' |
        sed -E 's/[[:space:]]*"name"[[:space:]]*:[[:space:]]*"v([0-9]+(\.[0-9]+)*)",/\1/g' |
        head -1
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
    _release="${PRIMER_STEP_GIT_LFS_DOWNLOAD%%/}/v${PRIMER_STEP_GIT_LFS_VERSION}"
    _tar=git-lfs-${_os}-${_platform}-v${PRIMER_STEP_GIT_LFS_VERSION}.tar.gz
    # Get the published sum, lines are formatted as <sha256> [*]<file>.
    yush_debug "Downloading sha256 sums from ${_release}/sha256sums.asc"
    _sum256=$(primer_net_curl "${_release}/sha256sums.asc" |
                awk -v a="$_tar" '{f=$2; sub(/^\*/, "", f); if (f == a && !s) s = $1} END {print s}' || true)
    if [ -z "$_sum256" ]; then
        yush_error "Could not find sha256 sum for $_tar in ${_release}/sha256sums.asc, will not install"
        return 1
    fi

    # Work in a temporary directory whereto we will be downloading the
    # tarpack, verify its sha256 sum and the binary before installation.
    _tmpdir=$(mktemp -d)
    _rc=1
    if ! primer_net_curl "${_release}/${_tar}" --progress-bar > "${_tmpdir}/${_tar}"; then
        yush_error "No binary at ${_release}/${_tar}"
    elif [ "$(sha256sum < "${_tmpdir}/${_tar}" | cut -d " " -f 1)" != "$_sum256" ]; then
        yush_error "SHA256 sum mismatch, should have been $_sum256"
    else
        _bin=$(tar ztf "${_tmpdir}/$_tar" | grep 'git-lfs$' | head -1)
        if [ -z "$_bin" ]; then
            yush_error "Cannot find git-lfs in tar file!"
        else
            tar -C "${_tmpdir}" -zxf "${_tmpdir}/$_tar" "$_bin"
            yush_debug "Verifying binary at ${_tmpdir}/${_bin}"
            chmod a+x "${_tmpdir}/${_bin}"
            if ! "${_tmpdir}/${_bin}" --version >/dev/null 2>&1; then
                yush_error "Downloaded binary at ${_tmpdir}/${_bin} probably invalid, will not install"
            else
                yush_notice "Installing as ${PRIMER_BINDIR%%/}/git-lfs"
                if ! [ -d "$PRIMER_BINDIR" ]; then
                    $PRIMER_OS_SUDO mkdir -p "$PRIMER_BINDIR"
                fi
                primer_utils_install_bin "${_tmpdir}/${_bin}" "${PRIMER_BINDIR%%/}/git-lfs"
                _rc=0
            fi
        fi
    fi
    rm -rf "$_tmpdir"
    return "$_rc"
}
