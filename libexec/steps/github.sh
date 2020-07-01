#!/usr/bin/env sh

# Installation "contract" file. Lines should be space-separated and contain the
# following field, in order: name of project, filter to find among release
# assets, version to match (default to latest), name of binary to extract and
# install (default to basename of project)
PRIMER_STEP_GITHUB_PROJECTS=${PRIMER_STEP_GITHUB_PROJECTS:-}

# Root location of the github API.
PRIMER_STEP_GITHUB_API=https://api.github.com/

primer_step_github() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--projects"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --projects)
                        PRIMER_STEP_GITHUB_PROJECTS=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            if [ -f "$PRIMER_STEP_GITHUB_PROJECTS" ]; then
                yush_info "Installing binaries out of github projects specified at $PRIMER_STEP_GITHUB_PROJECTS"
                while IFS= read -r line || [ -n "$line" ]; do
                    line=$(printf %s\\n "$line" | sed '/^[[:space:]]*$/d' | sed '/^[[:space:]]*#/d')
                    if [ -n "$line" ]; then
                        _primer_step_github_parse "$line"
                        yush_info "Installing binary matching $bin from $project"
                        # Find out release id and details for latest release or
                        # for release which name matches the version from the
                        # project specification file (glob-style matching).
                        if [ -z "$version" ]; then
                            IFS='	' read -r version tag id <<EOF
$(_primer_step_github_latest "$project")
EOF
                        else
                            IFS='	' read -r version tag id <<EOF
$(_primer_step_github_by_version "$project" "$version")
EOF
                        fi

                        # If we found a release identifier, look for the assets
                        # that match the filter coming from the project
                        # specification list. If found, download, extract and
                        # install.
                        if [ -n "$id" ]; then
                            _releases=${PRIMER_STEP_GITHUB_API%/}/repos/${project}/releases
                            _semantic=$(printf %s\\n "$version" | grep -oE '[0-9]+(\.[0-9]+)*')
                            _semtag=$(printf %s\\n "$tag" | grep -oE '[0-9]+(\.[0-9]+)*')
                            filter=$(   printf %s\\n "$filter" |
                                        sed -e "s/%version%/$version/g" \
                                            -e "s/%semantic%/$_semantic/g" \
                                            -e "s/%tag%/$tag/g" \
                                            -e "s/%semtag%/$_semtag/g" \
                                            -e "s/%bits%/$(getconf LONG_BIT)/g" \
                                            -e "s/%Machine%/$(uname -m)/g" \
                                            -e "s/%machine%/$(uname -m | tr '[:upper:]' '[:lower:]')/g" \
                                            -e "s/%Kernel%/$(uname -s)/g" \
                                            -e "s/%kernel%/$(uname -s | tr '[:upper:]' '[:lower:]')/g")

                            yush_debug "Looking for first asset matching $filter in release $id"
                            a_download=
                            a_name=
                            a_id=
                            while IFS= read -r line; do
                                if printf %s\\n "$line" | grep -Eq '"name"[[:space:]]*:'; then
                                    a_name=$(printf %s\\n "$line" | sed -E 's/[[:space:]]*"name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/g')
                                fi
                                if printf %s\\n "$line" | grep -Eq '"browser_download_url"[[:space:]]*:'; then
                                    a_download=$(printf %s\\n "$line" | sed -E 's/[[:space:]]*"browser_download_url"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/g')
                                fi
                                if printf %s\\n "$line" | grep -Eq '"id"[[:space:]]*:'; then
                                    a_id=$(printf %s\\n "$line" | sed -E 's/[[:space:]]*"id"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/g')
                                fi

                                if [ -n "$a_name" ] && [ -n "$a_id" ] && [ -n "$a_download" ]; then
                                    if yush_glob "$filter" "$a_name"; then
                                        _primer_step_github_install_download "$a_download" "$bin"
                                        break
                                    fi
                                    a_download=
                                    a_name=
                                    a_id=
                                fi
                            done <<EOF
$(primer_net_curl "${_releases}/${id}/assets")
EOF
                        else
                            yush_error "Cannot find release id for tag $version"
                        fi
                    fi
                done <"$PRIMER_STEP_GITHUB_PROJECTS"
            fi
            ;;
        "clean")
            if [ -f "$PRIMER_STEP_GITHUB_PROJECTS" ]; then
                yush_info "Removing binaries from github projects specified at $PRIMER_STEP_GITHUB_PROJECTS"
                while IFS= read -r line || [ -n "$line" ]; do
                    line=$(printf %s\\n "$line" | sed '/^[[:space:]]*$/d' | sed '/^[[:space:]]*#/d')
                    if [ -n "$line" ]; then
                        _primer_step_github_parse "$line"
                        yush_debug "Looking for executable matching $bin under $PRIMER_BINDIR"
                        find "${PRIMER_BINDIR}" -name "$bin" -perm -a=x |
                        while IFS= read -r fpath; do
                            yush_notice "Removing $fpath"
                            $PRIMER_OS_SUDO rm -f "$fpath"
                        done
                    fi
                done <"$PRIMER_STEP_GITHUB_PROJECTS"
            fi
            ;;
    esac
}

# Parse one line (passed as a parameter) of the projects specification file.
# This will "leak" variables that will be used further in the
# installation/cleaning process.
_primer_step_github_parse() {
    project=$(printf %s\\n "$1" | awk '{print $1}')
    filter=$(printf %s\\n "$1" | awk '{print $2}')
    # Parse "" or '' as a version glob-filter
    version=$(printf %s\\n "$1" | awk '{print $3}')
    if printf %s\\n "$version" | grep -qE "^[\"']{2}$"; then
        version=""
    fi
    # Name of binary/ies to find in destination, a glob-filter is the last
    # field. It defaults to the name of the project.
    bin=$(printf %s\\n "$1" | awk '{print $4}')
    if printf %s\\n "$bin" | grep -qE "^[\"']{2}$"; then
        bin=""
    fi
    if [ -z "$bin" ]; then
        bin=$(yush_basename "$project")
    fi
}

# Find the details for the latest release of a given project at github. The name
# of the project is passed as an argument and the details are pushed back,
# separated from one another with a tab. In order: the name of the release (will
# often be the version), the tag of the release (will often start with a v), the
# github identifier of the release.
_primer_step_github_latest() {
    _releases=${PRIMER_STEP_GITHUB_API%/}/repos/${1}/releases
    yush_notice "Discovering last version of $1"
    yush_trace "Getting latest release from $_releases"
    r_name=
    r_id=
    r_tag=
    while IFS= read -r line; do
        if printf %s\\n "$line" | grep -Eq '"name"[[:space:]]*:'; then
            r_name=$(printf %s\\n "$line" | sed -E 's/[[:space:]]*"name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/g')
        fi
        if printf %s\\n "$line" | grep -Eq '"tag_name"[[:space:]]*:'; then
            r_tag=$(printf %s\\n "$line" | sed -E 's/[[:space:]]*"tag_name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/g')
        fi
        if printf %s\\n "$line" | grep -Eq '"id"[[:space:]]*:'; then
            r_id=$(printf %s\\n "$line" | sed -E 's/[[:space:]]*"id"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/g')
        fi

        if [ -n "$r_name" ] && [ -n "$r_id" ] && [ -n "$r_tag" ]; then
            yush_debug "Latest release #$r_id, $r_name has tag: $r_tag"
            printf %s\\t%s\\t%d\\n "$r_name" "$r_tag" "$r_id"
            break
        fi
    done <<EOF
$(primer_net_curl "${_releases}/latest")
EOF
}

# Find the details for the release of a given project at github matching a
# version filter. The name of the project is passed as a first argument, and the
# filter for the version name as the second argument. The details are pushed
# back, separated from one another with a tab. In order: the name of the release
# (will often be the version), the tag of the release (will often start with a
# v), the github identifier of the release.
_primer_step_github_by_version() {
    _releases=${PRIMER_STEP_GITHUB_API%/}/repos/${1}/releases
    yush_notice "Discovering version of $1 glob-matching $2"
    yush_trace "Getting latest release from $_releases"
    r_name=
    r_id=
    r_tag=
    while IFS= read -r line; do
        # Only consider lines at the first level of identation in the objects of
        # the array returned, i.e. 2x2spaces: 2 spaces of indentation, two
        # levels.
        if printf %s\\n "$line" | grep -Eq '^\s{4}"'; then
            if printf %s\\n "$line" | grep -Eq '"name"[[:space:]]*:'; then
                r_name=$(printf %s\\n "$line" | sed -E 's/[[:space:]]*"name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/g')
            fi
            if printf %s\\n "$line" | grep -Eq '"tag_name"[[:space:]]*:'; then
                r_tag=$(printf %s\\n "$line" | sed -E 's/[[:space:]]*"tag_name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/g')
            fi
            if printf %s\\n "$line" | grep -Eq '"id"[[:space:]]*:'; then
                r_id=$(printf %s\\n "$line" | sed -E 's/[[:space:]]*"id"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/g')
            fi

            if [ -n "$r_name" ] && [ -n "$r_id" ] && [ -n "$r_tag" ]; then
                if yush_glob "$2" "$r_name"; then
                    yush_debug "Release #$r_id, $r_name matches $2, tag: $r_tag"
                    printf %s\\t%s\\t%d\\n "$r_name" "$r_tag" "$r_id"
                    break
                else
                    yush_trace "No match for release #$r_id, $r_name against $2, tag: $r_tag"
                fi
                r_name=
                r_id=
                r_tag=
            fi
        fi
    done <<EOF
$(primer_net_curl "${_releases}")
EOF
}

# Download and install the binaries matching $2 from the URL pointed at by $1.
# This will automatically untar, uncompress or unzip, installing all proper
# dependencies, e.g. tar, unzip. This uses a temporary directory where the
# content is downloaded before being analysed and copied to PRIMER_BINDIR, e.g.
# /usr/local/bin in most cases.
_primer_step_github_install_download() {
    tmpdir=$(mktemp -d)
    _fname=$(yush_basename "$1")
    yush_info "Downloading $1"

    # Download, uncompress and unpack to temporary directory based on the file
    # extension. This can probably be improved, but should cover most cases.
    case "$_fname" in
        *.tar)
            _primer_step_github_untar "$1" "$tmpdir" ""
            ;;
        *.tar.gz | *.tgz)
            _primer_step_github_untar "$1" "$tmpdir" "z"
            ;;
        *.tar.bz2 | *.tar.bzip2)
            _primer_step_github_untar "$1" "$tmpdir" "j"
            ;;
        *.tar.xz)
            _primer_step_github_untar "$1" "$tmpdir" "J"
            ;;
        *.tar.Z)
            _primer_step_github_untar "$1" "$tmpdir" "Z"
            ;;
        *.zip)
            primer_os_dependency unzip
            primer_net_curl "$1" > "${tmpdir}/$_fname"
            unzip "${tmpdir}/$_fname" -d "$tmpdir"
            rm -f "${tmpdir}/$_fname"; # Remove ZIP file at once, we are done
            ;;
        default)
            yush_warn "Does not recognise archive type of $_fname";;
    esac

    # Find something that is executable by everybody and matches the filter
    # passed as $2. For all matching binaries, install them to $PRIMER_BINDIR,
    # e.g. /usr/local/bin in most cases.
    find "$tmpdir" -name "$2" -perm -a=x |
    while IFS= read -r fpath; do
        yush_notice "Installing $(yush_basename "$fpath") to $PRIMER_BINDIR"
        $PRIMER_OS_SUDO mv -f "$fpath" "${PRIMER_BINDIR}"
    done
    rm -rf "$tmpdir"
}

# Download, uncompress, untar. $1 is the URL, $2 is the destination directory
# and $3 (can be empty) the compression "letter" for the tar options, e.g. Z for
# (old-style) compress format, etc.
_primer_step_github_untar() {
    primer_os_dependency tar
    if yush_loglevel_le verbose; then
        primer_net_curl "$1" | tar -C "$2" -"${3}xvf" -
    else
        primer_net_curl "$1" | tar -C "$2" -"${3}xf" -
    fi
}
