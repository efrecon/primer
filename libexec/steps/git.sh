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
            # implementation.
            if ! command -v "git-lfs" >/dev/null 2>&1; then
                if [ -z "$PRIMER_STEP_GIT_LFS_VERSION" ]; then
                    # Following uses the github API
                    # https://developer.github.com/v3/repos/releases/#list-releases-for-a-repository
                    # for getting the list of latest releases.
                    yush_notice "Discovering latest git LFS version from $PRIMER_STEP_GIT_LFS_RELEASES"
                    PRIMER_STEP_GIT_LFS_VERSION=$(  primer_net_curl "$PRIMER_STEP_GIT_LFS_RELEASES" |
                                        grep -E '"name"[[:space:]]*:[[:space:]]*"v[0-9]+(\.[0-9]+)*"' |
                                        sed -E 's/[[:space:]]*"name"[[:space:]]*:[[:space:]]*"v([0-9]+(\.[0-9]+)*)",/\1/g' |
                                        head -1)
                fi
                yush_info "Installing git LFS $PRIMER_STEP_GIT_LFS_VERSION"
                # Work in a temporary directory whereto we will be downloading
                # the tarpack for the proper platform and verify its sha256 sum
                # before installation.
                tmpdir=$(mktemp -d)
                _os=$(uname -s | tr '[:upper:]' '[:lower:]')
                _platform=
                case $(primer_os_platform) in
                    x86_64) _platform=amd64;;
                    x86) _platform=386;;
                esac
                if [ -n "$_platform" ]; then
                    _tar=git-lfs-${_os}-${_platform}-v${PRIMER_STEP_GIT_LFS_VERSION}.tar.gz
                    # Get the published sum
                    yush_debug "Downloading sha256 sums from ${PRIMER_STEP_GIT_LFS_DOWNLOAD%%/}/v${PRIMER_STEP_GIT_LFS_VERSION}/sha256sums.asc"
                    sum256=$(   primer_net_curl "${PRIMER_STEP_GIT_LFS_DOWNLOAD%%/}/v${PRIMER_STEP_GIT_LFS_VERSION}/sha256sums.asc" |
                                grep "$_tar" |
                                awk '{print $1}')
                    if primer_net_curl "${PRIMER_STEP_GIT_LFS_DOWNLOAD%%/}/v${PRIMER_STEP_GIT_LFS_VERSION}/${_tar}" --progress-bar > "${tmpdir}/${_tar}"; then
                        # Check against the sha256 sum if necessary.
                        if [ -n "$sum256" ]; then
                            yush_debug "Verifying sha256 sum"
                            if ! printf "%s  %s\n" "$sum256" "${tmpdir}/${_tar}" | sha256sum -c - >/dev/null 2>&1; then
                                yush_error "SHA256 sum mismatch, should have been $sum256"
                                rm -f "${tmpdir}/${_tar}"
                            fi
                        else
                            yush_warn "No sha256 sum to verify tarpack against!"
                        fi
                        # Extract from the tarpack and verify we can run the
                        # binary in the first place. If that works, install it.
                        if [ -f "${tmpdir}/${_tar}" ]; then
                            tar -C "${tmpdir}" -zxf "${tmpdir}/$_tar" git-lfs
                            # Verify the binary actually works properly.
                            yush_debug "Verifying binary at ${tmpdir}/git-lfs"
                            chmod a+x "${tmpdir}/git-lfs"
                            if ! "${tmpdir}/git-lfs" --version >/dev/null 2>&1; then
                                yush_info "Downloaded binary at ${tmpdir}/git-lfs probaby invalid, will not install"
                                rm -f "${tmpdir}/git-lfs"
                            else
                                yush_notice "Installing as ${PRIMER_BINDIR%%/}/git-lfs"
                                ! [ -d "$PRIMER_BINDIR" ] && $PRIMER_OS_SUDO mkdir -p "$PRIMER_BINDIR"
                                $PRIMER_OS_SUDO mv -f "${tmpdir}/git-lfs" "${PRIMER_BINDIR%%/}/git-lfs"
                            fi
                        fi
                    else
                        yush_warn "No binary at ${PRIMER_STEP_GIT_LFS_DOWNLOAD%%/}/$PRIMER_STEP_GIT_LFS_VERSION/${_tar}"
                    fi
                else
                    yush_warn "Cannot download for this platform!"
                fi
                rm -rf "$tmpdir"
                # Check version
                yush_debug "Verifying installed version against $PRIMER_STEP_GIT_LFS_VERSION"
                if ! git-lfs --version | grep -q "$PRIMER_STEP_GIT_LFS_VERSION"; then
                    yush_warn "Installed git-lfs version mismatch: $(git-lfs --version||true|grep -E -o '[0-9]+(\.[0-9]+)*'|head -1)"
                fi
            fi

            if [ -n "$PRIMER_STEP_GIT_LFS_INSTALL" ]; then
                yush_info "Installing LFS for all users on system matching $PRIMER_STEP_GIT_LFS_INSTALL"
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
            yush_info "Removing git LFS"
            if [ -f "${PRIMER_BINDIR%%/}/git-lfs" ]; then
                $PRIMER_OS_SUDO rm -f "${PRIMER_BINDIR%%/}/git-lfs"
            fi
            ;;
    esac
}
