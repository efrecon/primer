#!/usr/bin/env sh

# Installation "contract" file. Lines should be space-separated and contain the
# following field, in order: name of project, filter to find among release
# assets, version to match (default to latest), name of binary to extract and
# install (default to basename of project), checksum of the asset: a sha256
# or sha512 sum, or the URL or asset filter of a checksum file (default to
# none).
PRIMER_STEP_GITHUB_PROJECTS=${PRIMER_STEP_GITHUB_PROJECTS:-}

# When true, assets without a checksum are not installed, and the step fails.
PRIMER_STEP_GITHUB_VERIFY=${PRIMER_STEP_GITHUB_VERIFY:-0}

primer_step_github() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--projects --verify"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --projects)
                        PRIMER_STEP_GITHUB_PROJECTS=$2; shift 2;;
                    --verify)
                        PRIMER_STEP_GITHUB_VERIFY=$2; shift 2;;
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
                        _primer_step_github_install "$line" || return 1
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
                        _primer_step_github_clean "$line"
                    fi
                done <"$PRIMER_STEP_GITHUB_PROJECTS"
            fi
            ;;
    esac
}

# Install the binaries of the line $1 of the projects file. Fails when the
# asset cannot be downloaded, verified or installed. A release or an asset that
# cannot be found is only reported.
_primer_step_github_install() {
    _rs_rc=0
    _primer_step_github_resolve "$1" || _rs_rc=$?
    case "$_rs_rc" in
        0) ;;
        1) return 0;;
        *) return 1;;
    esac
    yush_info "Installing binary matching $bin from $project"
    if [ -z "$checksum" ] && yush_is_true "$PRIMER_STEP_GITHUB_VERIFY"; then
        yush_error "No checksum for $asset of $project, not installing it"
        return 1
    fi
    _gi_rc=0
    primer_github_install --sum "$sum" "$project" "$tag" "$asset" "$bin" || _gi_rc=$?
    # 2: no binary in the asset, only reported.
    [ "$_gi_rc" != 1 ]
}

# Remove the binaries of the line $1 of the projects file, but only those
# identical to the ones in the asset, fetched again: other binaries with the
# same name might not have been installed by this step.
_primer_step_github_clean() {
    _rs_rc=0
    _primer_step_github_resolve "$1" || _rs_rc=$?
    _cl_tmp=$(mktemp -d)
    if [ "$_rs_rc" != 0 ] \
            || ! primer_github_fetch "$project" "$tag" "$asset" "$sum" "$_cl_tmp" "$(_primer_step_github_single "$bin")"; then
        rm -rf "$_cl_tmp"
        find "${PRIMER_BINDIR}" -mindepth 1 -maxdepth 1 -name "$bin" -perm -a=x |
        while IFS= read -r fpath; do
            yush_warn "Keeping $fpath, cannot compare it to the release of $project"
        done
        return 0
    fi
    find "${PRIMER_BINDIR}" -mindepth 1 -maxdepth 1 -name "$bin" -perm -a=x |
    while IFS= read -r fpath; do
        _cl_ref=$(find "$_cl_tmp" -type f -name "$(yush_basename "$fpath")" | head -n 1)
        if [ -n "$_cl_ref" ] && cmp -s "$_cl_ref" "$fpath"; then
            yush_notice "Removing $fpath"
            $PRIMER_OS_SUDO rm -f "$fpath"
        else
            yush_warn "Keeping $fpath, not the one from $asset of $project"
        fi
    done
    rm -rf "$_cl_tmp"
}

# Print the name of single file assets for the binary $1: the binary itself,
# unless a glob-filter.
_primer_step_github_single() {
    case "$1" in
        *[\*\?\[]*) ;;
        *) printf %s\\n "$1";;
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
    # Checksum of the asset, empty for none.
    checksum=$(printf %s\\n "$1" | awk '{print $5}')
    if printf %s\\n "$checksum" | grep -qE "^[\"']{2}$"; then
        checksum=""
    fi
}

# Parse the line $1 of the projects file (see _primer_step_github_parse), find
# its release, and the first asset that matches the filter. Sets tag and asset,
# and sum: the checksum, with tokens replaced, and with checksum files among
# the assets of the release replaced by their URL. Returns 1 when the release
# or the asset cannot be found, 2 when the checksum file cannot be found.
_primer_step_github_resolve() {
    _primer_step_github_parse "$1"
    tag=
    id=
    asset=
    sum=
    # Latest release, or release which name matches the version (glob-style).
    if [ -z "$version" ]; then
        IFS='	' read -r version tag id <<EOF
$(_primer_step_github_latest "$project")
EOF
    else
        IFS='	' read -r version tag id <<EOF
$(_primer_step_github_by_version "$project" "$version")
EOF
    fi
    if [ -z "$id" ]; then
        yush_error "Cannot find release id for tag $version"
        return 1
    fi

    filter=$(primer_github_tokens "$filter" "$tag" "$version")
    yush_debug "Looking for first asset matching $filter in release $id"
    _rs_assets=$(_primer_step_github_assets "$project" "$id")
    asset=$(printf %s\\n "$_rs_assets" | _primer_step_github_pick "$filter" | cut -f 1)
    if [ -z "$asset" ]; then
        yush_warn "No asset matching $filter in release $tag of $project"
        return 1
    fi

    # Sums are kept, URLs and asset filters get their tokens replaced, asset
    # filters are then replaced with the URL of the asset.
    if [ -z "$checksum" ] || printf %s\\n "$checksum" | grep -qE '^[0-9a-fA-F]+$'; then
        sum=$checksum
        return 0
    fi
    sum=$(primer_github_tokens "$checksum" "$tag" "$version" "$asset")
    case "$sum" in
        http://* | https://* | file://*) ;;
        *)
            _rs_filter=$sum
            sum=$(printf %s\\n "$_rs_assets" | _primer_step_github_pick "$_rs_filter" | cut -f 2)
            if [ -z "$sum" ]; then
                yush_error "No checksum file matching $_rs_filter among the assets of $project, not installing $asset"
                return 2
            fi
            ;;
    esac
}

# Print the assets of the release $2 of the project $1, one per line: their
# name and download URL, separated by a tab.
_primer_step_github_assets() {
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
            printf '%s\t%s\n' "$a_name" "$a_download"
            a_download=
            a_name=
            a_id=
        fi
    done <<EOF
$(primer_net_curl "${PRIMER_GITHUB_API%/}/repos/${1}/releases/${2}/assets")
EOF
}

# Print the first asset, from the list of assets on stdin (see
# _primer_step_github_assets), which name matches the glob-filter $1.
_primer_step_github_pick() {
    while IFS='	' read -r _pk_name _pk_url; do
        if [ -n "$_pk_name" ] && yush_glob "$1" "$_pk_name"; then
            printf '%s\t%s\n' "$_pk_name" "$_pk_url"
            return 0
        fi
    done
}

# Find the details for the latest release of a given project at github. The name
# of the project is passed as an argument and the details are pushed back,
# separated from one another with a tab. In order: the name of the release (will
# often be the version), the tag of the release (will often start with a v), the
# github identifier of the release.
_primer_step_github_latest() {
    _releases=${PRIMER_GITHUB_API%/}/repos/${1}/releases
    yush_notice "Discovering last version of $1"
    yush_debug "Getting latest release from $_releases"
    r_name=
    r_id=
    r_tag=
    while IFS= read -r line; do
        # Only consider lines at the first level of indentation of the object
        # returned, i.e. 2 spaces. Nested objects, e.g. the author of the
        # release, also have an "id" and a "name".
        if ! printf %s\\n "$line" | grep -Eq '^[[:space:]]{2}"'; then
            continue
        fi
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
    _releases=${PRIMER_GITHUB_API%/}/repos/${1}/releases
    yush_notice "Discovering version of $1 glob-matching $2"
    yush_debug "Getting latest release from $_releases"
    r_name=
    r_id=
    r_tag=
    while IFS= read -r line; do
        # Only consider lines at the first level of identation in the objects of
        # the array returned, i.e. 2x2spaces: 2 spaces of indentation, two
        # levels.
        if printf %s\\n "$line" | grep -Eq '^[[:space:]]{4}"'; then
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
