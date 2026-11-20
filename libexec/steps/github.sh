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

# Root location of the github API.
PRIMER_STEP_GITHUB_API=https://api.github.com/

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

                        # If we found a release identifier, look for the first
                        # asset that matches the filter coming from the project
                        # specification list. If found, download, verify,
                        # extract and install: the step fails when this fails.
                        if [ -n "$id" ]; then
                            filter=$(_primer_step_github_tokens "$filter")
                            yush_debug "Looking for first asset matching $filter in release $id"
                            _assets=$(_primer_step_github_assets "$project" "$id")
                            _asset=$(printf %s\\n "$_assets" | _primer_step_github_pick "$filter")
                            if [ -n "$_asset" ]; then
                                _primer_step_github_install_download \
                                    "$(printf %s\\n "$_asset" | cut -f 2)" "$bin" \
                                    "$(printf %s\\n "$_asset" | cut -f 1)" "$checksum" "$_assets" || return 1
                            fi
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
                        find "${PRIMER_BINDIR}" -mindepth 1 -maxdepth 1 -name "$bin" -perm -a=x |
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
    # Checksum of the asset, empty for none.
    checksum=$(printf %s\\n "$1" | awk '{print $5}')
    if printf %s\\n "$checksum" | grep -qE "^[\"']{2}$"; then
        checksum=""
    fi
}

# Print $1 with its %-enclosed tokens replaced, using the release (version,
# tag) and the platform. %asset% is replaced with $2.
_primer_step_github_tokens() {
    _semantic=$(printf %s\\n "$version" | grep -oE '[0-9]+(\.[0-9]+)*' || true)
    _semtag=$(printf %s\\n "$tag" | grep -oE '[0-9]+(\.[0-9]+)*' || true)
    printf %s\\n "$1" |
        sed -e "s/%version%/$version/g" \
            -e "s/%semantic%/$_semantic/g" \
            -e "s/%tag%/$tag/g" \
            -e "s/%semtag%/$_semtag/g" \
            -e "s/%bits%/$(getconf LONG_BIT)/g" \
            -e "s/%Machine%/$(uname -m)/g" \
            -e "s/%machine%/$(uname -m | tr '[:upper:]' '[:lower:]')/g" \
            -e "s/%Kernel%/$(uname -s)/g" \
            -e "s/%kernel%/$(uname -s | tr '[:upper:]' '[:lower:]')/g" \
            -e "s/%asset%/$(printf %s "${2:-}" | sed 's/[\/&]/\\&/g')/g"
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
$(primer_net_curl "${PRIMER_STEP_GITHUB_API%/}/repos/${1}/releases/${2}/assets")
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
    _releases=${PRIMER_STEP_GITHUB_API%/}/repos/${1}/releases
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
    _releases=${PRIMER_STEP_GITHUB_API%/}/repos/${1}/releases
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

# Download the asset $3 from the URL $1, verify it against the checksum $4 (see
# _primer_step_github_verify, $5 is the list of assets of the release), then
# install the binaries matching $2 from it. Archives are unpacked, compressed
# binaries uncompressed, installing all proper dependencies, e.g. tar, unzip.
# Matching binaries are installed to PRIMER_BINDIR, e.g. /usr/local/bin in most
# cases. Fails, installing nothing, when the download or the verification
# fails.
_primer_step_github_install_download() {
    tmpdir=$(mktemp -d)
    _dldir=$(mktemp -d)
    _file="${_dldir}/$3"
    yush_info "Downloading $1"
    if ! primer_net_curl "$1" > "$_file"; then
        yush_error "Could not download $3 from $1, not installing"
        rm -rf "$tmpdir" "$_dldir"
        return 1
    fi
    if ! _primer_step_github_verify "$_file" "$3" "$4" "$5"; then
        rm -rf "$tmpdir" "$_dldir"
        return 1
    fi

    # Uncompress and unpack to temporary directory based on the file
    # extension. This can probably be improved, but should cover most cases.
    case "$3" in
        *.tar)
            _primer_step_github_untar "$_file" "$tmpdir" ""
            ;;
        *.tar.gz | *.tgz)
            _primer_step_github_untar "$_file" "$tmpdir" "z"
            ;;
        *.tar.bz2 | *.tar.bzip2)
            _primer_step_github_untar "$_file" "$tmpdir" "j"
            ;;
        *.tar.xz)
            _primer_step_github_untar "$_file" "$tmpdir" "J"
            ;;
        *.tar.Z)
            _primer_step_github_untar "$_file" "$tmpdir" "Z"
            ;;
        *.zip)
            primer_os_dependency unzip
            unzip "$_file" -d "$tmpdir"
            ;;
        *.gz)
            # A single compressed binary.
            _dst=$(_primer_step_github_binname "$2" "${3%.gz}")
            gzip -dc < "$_file" > "${tmpdir}/${_dst}"
            _primer_step_github_executable "${tmpdir}/${_dst}"
            ;;
        *.bz2)
            primer_os_dependency bzip2
            _dst=$(_primer_step_github_binname "$2" "${3%.bz2}")
            bzip2 -dc < "$_file" > "${tmpdir}/${_dst}"
            _primer_step_github_executable "${tmpdir}/${_dst}"
            ;;
        *.xz)
            _primer_step_github_xz_dependency
            _dst=$(_primer_step_github_binname "$2" "${3%.xz}")
            xz -dc < "$_file" > "${tmpdir}/${_dst}"
            _primer_step_github_executable "${tmpdir}/${_dst}"
            ;;
        *)
            # Not an archive: a binary released as-is.
            _dst=$(_primer_step_github_binname "$2" "$3")
            mv -f "$_file" "${tmpdir}/${_dst}"
            _primer_step_github_executable "${tmpdir}/${_dst}"
            ;;
    esac
    rm -rf "$_dldir"

    # Find something that is executable by everybody and matches the filter
    # passed as $2. For all matching binaries, install them to $PRIMER_BINDIR,
    # e.g. /usr/local/bin in most cases.
    [ -d "$PRIMER_BINDIR" ] || $PRIMER_OS_SUDO mkdir -p "$PRIMER_BINDIR"
    find "$tmpdir" -type f -name "$2" -perm -a=x |
    while IFS= read -r fpath; do
        yush_notice "Installing $(yush_basename "$fpath") to $PRIMER_BINDIR"
        primer_utils_install_bin "$fpath" "${PRIMER_BINDIR}"
    done
    rm -rf "$tmpdir"
}

# Verify the downloaded asset at $1, named $2, against the checksum field $3 of
# the projects file. The field is either:
# - empty: no verification, with a warning, or a failure when
#   PRIMER_STEP_GITHUB_VERIFY is true.
# - a sha256 or sha512 sum, recognised by its length.
# - the URL of a checksum file (http, https or file).
# - otherwise, a glob-filter for the checksum file among the assets of the
#   release ($4, see _primer_step_github_assets).
# URLs and filters can contain the same tokens as asset filters, and %asset%.
# The algorithm of sums from checksum files comes from their tag (BSD format),
# or from the name of the file, e.g. SHA512SUMS, and otherwise from their length:
# other algorithms have sums of the same length, e.g. BLAKE2b and sha512.
_primer_step_github_verify() {
    if [ -z "$3" ]; then
        if yush_is_true "$PRIMER_STEP_GITHUB_VERIFY"; then
            yush_error "No checksum for $2 of $project, not installing it"
            return 1
        fi
        yush_warn "No checksum for $2 of $project, installing unverified"
        return 0
    fi

    # Hexadecimal strings as long as the shortest sum are sums, others are
    # checksum files.
    _algo=
    if printf %s\\n "$3" | grep -qE '^[0-9a-fA-F]{32,}$'; then
        _expected=$3
        _from="the projects file"
    else
        _cksrc=$(_primer_step_github_tokens "$3" "$2")
        case "$_cksrc" in
            http://* | https://* | file://*)
                _url=$_cksrc;;
            *)
                _url=$(printf %s\\n "$4" | _primer_step_github_pick "$_cksrc" | cut -f 2)
                if [ -z "$_url" ]; then
                    yush_error "No checksum file matching $_cksrc among the assets of $project, not installing $2"
                    return 1
                fi
                ;;
        esac
        _sums=$(mktemp)
        if ! primer_net_curl "$_url" > "$_sums"; then
            rm -f "$_sums"
            yush_error "Could not download checksums from $_url, not installing $2"
            return 1
        fi
        read -r _expected _algo <<EOF
$(_primer_step_github_sum_lookup "$_sums" "$2")
EOF
        rm -f "$_sums"
        if [ -z "$_expected" ]; then
            yush_error "No checksum for $2 in $_url, not installing it"
            return 1
        fi
        [ -n "$_algo" ] || _algo=$(_primer_step_github_algo "$_url")
        _from=$_url
    fi

    if ! _tool=$(_primer_step_github_sum "$_expected" "$_algo"); then
        case "$_algo" in
            "")
                yush_error "$_expected is not a sha256 or sha512 sum, not installing $2";;
            sha256|sha512)
                yush_error "$_expected is not a $_algo sum (from $_from), not installing $2";;
            *)
                yush_error "$_algo sums are not supported, only sha256 and sha512 (from $_from), not installing $2";;
        esac
        return 1
    fi
    _expected=$(printf %s "$_expected" | tr '[:upper:]' '[:lower:]')
    if [ "$($_tool < "$1" | cut -d " " -f 1)" != "$_expected" ]; then
        yush_error "Checksum mismatch for $2, should have been $_expected (from $_from), not installing it"
        return 1
    fi
    yush_info "Verified ${_tool%sum} sum of $2"
}

# Print the command computing the sum $1, of the algorithm $2 when given (e.g.
# sha256, sha512), from its length otherwise: sha256 or sha512. Fails for other
# algorithms or lengths, e.g. md5, or when $1 is not hexadecimal.
_primer_step_github_sum() {
    printf %s\\n "$1" | grep -qE '^[0-9a-fA-F]+$' || return 1
    case "${#1}:${2:-}" in
        64:|64:sha256) echo sha256sum;;
        128:|128:sha512) echo sha512sum;;
        *) return 1;;
    esac
}

# Print the algorithm of the checksum file at the URL $1, guessed from its name,
# e.g. sha256 for SHA256SUMS, blake2b for B2SUMS. Nothing when the name does not
# tell, e.g. checksums.txt.
_primer_step_github_algo() {
    _an=$(printf %s\\n "${1##*/}" | sed 's/[?#].*//' | tr '[:upper:]' '[:lower:]')
    case "$_an" in
        *sha512*|*sha2-512*) echo sha512;;
        *sha384*) echo sha384;;
        *sha256*|*sha2-256*) echo sha256;;
        *sha224*) echo sha224;;
        *sha3*) echo sha3;;
        *sha1*) echo sha1;;
        *md5*) echo md5;;
        *b2sum*|*.b2|*blake2*) echo blake2b;;
        *b3sum*|*.b3|*blake3*) echo blake3;;
    esac
}

# Print the sum for the asset $2 from the checksum file $1, followed by its
# algorithm when the file tells it (BSD format), e.g. sha256. Recognised
# formats: <sum>  <name> and <sum> *<name> (coreutils), ALGO (<name>) = <sum>
# (BSD, also ALGO(<name>)= <sum> as printed by OpenSSL), or a file with a single
# sum and nothing else. Names are compared without leading directories.
_primer_step_github_sum_lookup() {
    awk -v a="$2" '
        function base(n) { sub(/^\*/, "", n); sub(/^.*\//, "", n); return n }
        { sub(/\r$/, "") }
        NF == 0 { next }
        { lines++ }
        /^[A-Za-z0-9-]+ ?\(.*\) ?= ?[0-9A-Fa-f]+$/ {
            n = $0
            sub(/^[^(]*\(/, "", n)
            sub(/\) ?= ?[0-9A-Fa-f]+$/, "", n)
            if (base(n) == a && s == "") {
                s = $NF; sub(/^.*=/, "", s)
                t = tolower($0); sub(/ ?\(.*$/, "", t)
                sub(/^sha2-/, "sha", t)
            }
            next
        }
        NF >= 2 {
            n = $0
            sub(/^[^ \t]+[ \t]+/, "", n)
            if (base(n) == a && s == "") s = $1
            next
        }
        $1 ~ /^[0-9A-Fa-f]+$/ { single = $1 }
        END {
            if (s != "") print s (t != "" ? " " t : "")
            else if (lines == 1 && single != "") print single
        }' "$1"
}

# Uncompress, untar. $1 is the tar file, $2 is the destination directory and $3
# (can be empty) the compression "letter" for the tar options, e.g. Z for
# (old-style) compress format, etc.
_primer_step_github_untar() {
    primer_os_dependency tar
    if yush_loglevel_le debug; then
        tar -C "$2" -"${3}xvf" "$1"
    else
        tar -C "$2" -"${3}xf" "$1"
    fi
}

# Print the name to give to a downloaded binary: the binary to install ($1),
# unless that is a glob-filter, in which case the name of the download ($2).
_primer_step_github_binname() {
    case "$1" in
        *[\*\?\[]*) printf %s\\n "$2";;
        *) printf %s\\n "$1";;
    esac
}

# Make the downloaded file passed as an argument executable when it is a
# binary (ELF) or a script. Remove it otherwise, e.g. for packages (.deb,
# .rpm) or checksums, so that it is not installed.
_primer_step_github_executable() {
    # ELF binaries start with \177ELF, scripts with #!
    if [ "$(head -c 4 "$1" | tail -c 3)" = "ELF" ] || [ "$(head -c 2 "$1")" = "#!" ]; then
        chmod a+x "$1"
    else
        yush_warn "$(yush_basename "$1") is neither a binary nor a script, not installing it"
        rm -f "$1"
    fi
}

# Make sure xz can be used for decompression: busybox only provides unxz and
# xzcat, and the package is called differently on Debian derivatives.
_primer_step_github_xz_dependency() {
    if ! primer_utils_syscmd_exists xz; then
        case "$(primer_os_distribution)" in
            *buntu|*bian) primer_os_packages add xz-utils;;
            *) primer_os_packages add xz;;
        esac
    fi
}
