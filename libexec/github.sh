#!/usr/bin/env sh

# Download, verify and install binaries from the releases of projects at
# GitHub. Used by the github step, and by the steps installing a specific
# project, e.g. lazydocker or micro.

# Root of the GitHub API, only used when the latest release cannot be found
# through the web site.
PRIMER_GITHUB_API=${PRIMER_GITHUB_API:-https://api.github.com}

# Root of the web site, where releases are downloaded from.
PRIMER_GITHUB_DOWNLOAD=${PRIMER_GITHUB_DOWNLOAD:-https://github.com}

# Print the tag of the latest release of the project $1, e.g. owner/repo. The
# web site redirects .../releases/latest to the page of the tag, so no API call
# is needed, and the rate limits of the API do not apply. The API is used when
# that fails.
primer_github_latest() {
    yush_notice "Discovering latest release of $1"
    _gl_url=$(primer_net_curl "${PRIMER_GITHUB_DOWNLOAD%/}/$1/releases/latest" -o /dev/null -w '%{url_effective}' 2>/dev/null || true)
    case "$_gl_url" in
        */releases/tag/?*)
            printf %s\\n "${_gl_url##*/releases/tag/}"
            return 0;;
    esac
    yush_debug "No redirect to the latest release of $1, asking the API"
    primer_net_curl "${PRIMER_GITHUB_API%/}/repos/$1/releases/latest" 2>/dev/null |
        sed -nE 's/^[[:space:]]{2}"tag_name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' |
        head -n 1 || true
}

# Print the URL of the asset $3 of the release tagged $2 of the project $1.
primer_github_url() {
    printf '%s/%s/releases/download/%s/%s\n' "${PRIMER_GITHUB_DOWNLOAD%/}" "$1" "$2" "$3"
}

# Print $1 with its %-enclosed tokens replaced: %tag% and %semtag% from the tag
# $2, %version% and %semantic% from the version $3 (the tag by default), %asset%
# with $4, and the platform: %bits%, %Kernel%, %kernel%, %Machine%, %machine%.
primer_github_tokens() {
    _tk_version=${3:-$2}
    _tk_semantic=$(printf %s\\n "$_tk_version" | grep -oE '[0-9]+(\.[0-9]+)*' | head -n 1 || true)
    _tk_semtag=$(printf %s\\n "$2" | grep -oE '[0-9]+(\.[0-9]+)*' | head -n 1 || true)
    printf %s\\n "$1" |
        sed -e "s/%version%/$(_primer_github_sedesc "$_tk_version")/g" \
            -e "s/%semantic%/$_tk_semantic/g" \
            -e "s/%tag%/$(_primer_github_sedesc "$2")/g" \
            -e "s/%semtag%/$_tk_semtag/g" \
            -e "s/%bits%/$(getconf LONG_BIT)/g" \
            -e "s/%Machine%/$(uname -m)/g" \
            -e "s/%machine%/$(uname -m | tr '[:upper:]' '[:lower:]')/g" \
            -e "s/%Kernel%/$(uname -s)/g" \
            -e "s/%kernel%/$(uname -s | tr '[:upper:]' '[:lower:]')/g" \
            -e "s/%asset%/$(_primer_github_sedesc "${4:-}")/g"
}

# Print $1 escaped for the replacement part of a sed s command.
_primer_github_sedesc() {
    printf %s "$1" | sed 's/[\/&]/\\&/g'
}

# Verify the downloaded file at $1, named $2 in its release, against the
# checksum $3, which is either:
# - empty: no verification, with a warning.
# - a sha256 or sha512 sum, recognised by its length.
# - the URL of a checksum file (http, https or file).
# - otherwise, the name of a checksum file in the release tagged $5 of the
#   project $4, e.g. checksums.txt. It can contain tokens, e.g. %asset%.sha256.
# The algorithm of sums from checksum files comes from their tag (BSD format),
# or from the name of the file, e.g. SHA512SUMS, and otherwise from their length:
# other algorithms have sums of the same length, e.g. BLAKE2b and sha512. Fails
# when the file cannot be verified.
primer_github_verify() {
    if [ -z "$3" ]; then
        yush_warn "No checksum for $2, installing unverified"
        return 0
    fi

    # Hexadecimal strings are sums (their length is checked below), others
    # are checksum files.
    _vf_algo=
    if printf %s\\n "$3" | grep -qE '^[0-9a-fA-F]+$'; then
        _vf_expected=$3
        _vf_from="the given sum"
    else
        _vf_src=$(primer_github_tokens "$3" "${5:-}" "" "$2")
        case "$_vf_src" in
            http://* | https://* | file://*)
                _vf_url=$_vf_src;;
            *)
                if [ -z "${4:-}" ] || [ -z "${5:-}" ]; then
                    yush_error "No release to find the checksum file $_vf_src in, not installing $2"
                    return 1
                fi
                _vf_url=$(primer_github_url "$4" "$5" "$_vf_src");;
        esac
        _vf_sums=$(mktemp)
        if ! primer_net_curl "$_vf_url" > "$_vf_sums"; then
            rm -f "$_vf_sums"
            yush_error "Could not download checksums from $_vf_url, not installing $2"
            return 1
        fi
        read -r _vf_expected _vf_algo <<EOF
$(_primer_github_sum_lookup "$_vf_sums" "$2")
EOF
        rm -f "$_vf_sums"
        if [ -z "$_vf_expected" ]; then
            yush_error "No checksum for $2 in $_vf_url, not installing it"
            return 1
        fi
        [ -n "$_vf_algo" ] || _vf_algo=$(_primer_github_algo "$_vf_url")
        _vf_from=$_vf_url
    fi

    if ! _vf_tool=$(_primer_github_sum "$_vf_expected" "$_vf_algo"); then
        case "$_vf_algo" in
            "")
                yush_error "$_vf_expected is not a sha256 or sha512 sum, not installing $2";;
            sha256|sha512)
                yush_error "$_vf_expected is not a $_vf_algo sum (from $_vf_from), not installing $2";;
            *)
                yush_error "$_vf_algo sums are not supported, only sha256 and sha512 (from $_vf_from), not installing $2";;
        esac
        return 1
    fi
    _vf_expected=$(printf %s "$_vf_expected" | tr '[:upper:]' '[:lower:]')
    if [ "$($_vf_tool < "$1" | cut -d " " -f 1)" != "$_vf_expected" ]; then
        yush_error "Checksum mismatch for $2, should have been $_vf_expected (from $_vf_from), not installing it"
        return 1
    fi
    yush_info "Verified ${_vf_tool%sum} sum of $2"
}

# Download the asset $3 of the release tagged $2 of the project $1, verify it
# against the checksum $4 (see primer_github_verify), and unpack it into the
# directory $5. Archives are unpacked, compressed files uncompressed, installing
# the necessary tools, e.g. unzip. Single files are named $6, the name of the
# asset (without compression extension) by default, and made executable when
# they are binaries or scripts (removed otherwise). Fails, leaving nothing in
# the directory, when the download or the verification fails.
primer_github_fetch() {
    _ft_url=$(primer_github_url "$1" "$2" "$3")
    _ft_dl=$(mktemp -d)
    _ft_file="${_ft_dl}/$3"
    yush_info "Downloading $_ft_url"
    if ! primer_net_curl "$_ft_url" > "$_ft_file"; then
        rm -rf "$_ft_dl"
        yush_error "No binary at $_ft_url, not installing"
        return 1
    fi
    if ! primer_github_verify "$_ft_file" "$3" "$4" "$1" "$2"; then
        rm -rf "$_ft_dl"
        return 1
    fi

    _ft_rc=0
    case "$3" in
        *.tar)
            _primer_github_untar "$_ft_file" "$5" "" || _ft_rc=1;;
        *.tar.gz | *.tgz)
            _primer_github_untar "$_ft_file" "$5" "z" || _ft_rc=1;;
        *.tar.bz2 | *.tar.bzip2)
            _primer_github_untar "$_ft_file" "$5" "j" || _ft_rc=1;;
        *.tar.xz)
            _primer_github_untar "$_ft_file" "$5" "J" || _ft_rc=1;;
        *.tar.Z)
            _primer_github_untar "$_ft_file" "$5" "Z" || _ft_rc=1;;
        *.zip)
            primer_os_dependency unzip
            unzip -q "$_ft_file" -d "$5" || _ft_rc=1;;
        *.gz)
            _ft_dst="${5}/${6:-${3%.gz}}"
            { gzip -dc < "$_ft_file" > "$_ft_dst" && _primer_github_executable "$_ft_dst"; } || _ft_rc=1;;
        *.bz2)
            primer_os_dependency bzip2
            _ft_dst="${5}/${6:-${3%.bz2}}"
            { bzip2 -dc < "$_ft_file" > "$_ft_dst" && _primer_github_executable "$_ft_dst"; } || _ft_rc=1;;
        *.xz)
            _primer_github_xz_dependency
            _ft_dst="${5}/${6:-${3%.xz}}"
            { xz -dc < "$_ft_file" > "$_ft_dst" && _primer_github_executable "$_ft_dst"; } || _ft_rc=1;;
        *)
            # Not an archive: a binary released as-is.
            _ft_dst="${5}/${6:-$3}"
            { mv -f "$_ft_file" "$_ft_dst" && _primer_github_executable "$_ft_dst"; } || _ft_rc=1;;
    esac
    rm -rf "$_ft_dl"
    if [ "$_ft_rc" != 0 ]; then
        yush_error "Could not unpack $3"
        find "$5" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    fi
    return "$_ft_rc"
}

# primer_github_install [--dest DIR] [--name NAME] [--check ARGS] [--sum SUM]
#                       PROJECT TAG ASSET [BINARY]
# Download the asset ASSET of the release tagged TAG of the project PROJECT,
# verify it against SUM (see primer_github_verify) and install the binaries it
# contains that match the glob-filter BINARY (the basename of the project by
# default), and are executable by all. Assets that are single files are the
# binary, named BINARY (when not a glob-filter). Binaries are installed in DIR,
# PRIMER_BINDIR by default, under their own name or NAME (when there is only
# one), owned by root. When ARGS are given, binaries must run successfully with
# them, e.g. --version, before anything is installed. Returns 1 on failures,
# installing nothing, 2 when there was no binary to install.
primer_github_install() {
    _in_dest=$PRIMER_BINDIR
    _in_name=
    _in_check=
    _in_sum=
    while [ $# -gt 0 ]; do
        case "$1" in
            --dest) _in_dest=$2; shift 2;;
            --name) _in_name=$2; shift 2;;
            --check) _in_check=$2; shift 2;;
            --sum) _in_sum=$2; shift 2;;
            --) shift; break;;
            *) break;;
        esac
    done
    _in_bin=${4:-$(yush_basename "$1")}
    # Name of single files: the binary, unless a glob-filter.
    case "$_in_bin" in
        *[\*\?\[]*) _in_single=;;
        *) _in_single=$_in_bin;;
    esac

    _in_tmp=$(mktemp -d)
    if ! primer_github_fetch "$1" "$2" "$3" "$_in_sum" "$_in_tmp" "$_in_single"; then
        rm -rf "$_in_tmp"
        return 1
    fi
    _in_found=$(find "$_in_tmp" -type f -name "$_in_bin" -perm -a=x)
    if [ -z "$_in_found" ]; then
        rm -rf "$_in_tmp"
        yush_warn "No executable matching $_in_bin in $3"
        return 2
    fi
    if [ -n "$_in_name" ] && [ "$(printf %s\\n "$_in_found" | wc -l)" -gt 1 ]; then
        rm -rf "$_in_tmp"
        yush_error "Several binaries match $_in_bin in $3, cannot install them as $_in_name"
        return 1
    fi
    # Check all binaries before installing any.
    if [ -n "$_in_check" ]; then
        while IFS= read -r _in_path; do
            # shellcheck disable=SC2086 # The arguments are split on purpose.
            if ! "$_in_path" $_in_check >/dev/null 2>&1; then
                rm -rf "$_in_tmp"
                yush_error "Downloaded binary $(yush_basename "$_in_path") from $3 probably invalid, not installing"
                return 1
            fi
        done <<EOF
$_in_found
EOF
    fi
    [ -d "$_in_dest" ] || $PRIMER_OS_SUDO mkdir -p "$_in_dest"
    _in_rc=0
    while IFS= read -r _in_path; do
        _in_target="${_in_dest%/}/${_in_name:-$(yush_basename "$_in_path")}"
        yush_notice "Installing $(yush_basename "$_in_path") from $3 as $_in_target"
        primer_utils_install_bin "$_in_path" "$_in_target" || _in_rc=1
    done <<EOF
$_in_found
EOF
    rm -rf "$_in_tmp"
    return "$_in_rc"
}

# Print the command computing the sum $1, of the algorithm $2 when given (e.g.
# sha256, sha512), from its length otherwise: sha256 or sha512. Fails for other
# algorithms or lengths, e.g. md5, or when $1 is not hexadecimal.
_primer_github_sum() {
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
_primer_github_algo() {
    _al_name=$(printf %s\\n "${1##*/}" | sed 's/[?#].*//' | tr '[:upper:]' '[:lower:]')
    case "$_al_name" in
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

# Print the sum for the file $2 from the checksum file $1, followed by its
# algorithm when the file tells it (BSD format), e.g. sha256. Recognised
# formats: <sum>  <name> and <sum> *<name> (coreutils), ALGO (<name>) = <sum>
# (BSD, also ALGO(<name>)= <sum> as printed by OpenSSL), or a file with a single
# sum and nothing else. Names are compared without leading directories.
_primer_github_sum_lookup() {
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
        NF >= 2 && $1 ~ /^[0-9A-Fa-f]+$/ {
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
_primer_github_untar() {
    primer_os_dependency tar
    if yush_loglevel_le debug; then
        tar -C "$2" -"${3}xvf" "$1"
    else
        tar -C "$2" -"${3}xf" "$1"
    fi
}

# Make the downloaded file passed as an argument executable when it is a
# binary (ELF) or a script. Remove it otherwise, e.g. for packages (.deb,
# .rpm) or checksums, so that it is not installed.
_primer_github_executable() {
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
_primer_github_xz_dependency() {
    if ! primer_utils_syscmd_exists xz; then
        case "$(primer_os_distribution)" in
            *buntu|*bian) primer_os_packages add xz-utils;;
            *) primer_os_packages add xz;;
        esac
    fi
}
