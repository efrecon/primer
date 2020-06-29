#!/usr/bin/env sh

# Installation contract file
PRIMER_STEP_GITHUB_PROJECTS=${PRIMER_STEP_GITHUB_PROJECTS:-}

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
                while IFS= read -r line || [ -n "$line" ]; do
                    line=$(printf %s\\n "$line" | sed '/^[[:space:]]*$/d' | sed '/^[[:space:]]*#/d')
                    if [ -n "$line" ]; then
                        project=$(printf %s\\n "$line" | awk '{print $1}')
                        filter=$(printf %s\\n "$line" | awk '{print $2}')
                        bin=$(printf %s\\n "$line" | awk '{print $3}')
                        printf %s\\n "$bin" | grep -qE '(""|'')' && bin=""
                        version=$(printf %s\\n "$line" | awk '{print $4}')
                        printf %s\\n "$version" | grep -qE '(""|'')' && version=""
                        [ -z "$bin" ] && bin=$(yush_basename "$project")

                        yush_trace "$project $filter $bin $version"
                        yush_info "Installing binary matching $bin from $project"
                        _releases=${PRIMER_STEP_GITHUB_API%/}/repos/${project}/releases
                        if [ -z "$version" ]; then
                            yush_notice "Discovering last version of $project"
                            yush_trace "Getting latest release from $_releases"
                            version=$(  primer_net_curl "$_releases" |
                                        grep -E '"name"[[:space:]]*:[[:space:]]*"v?[0-9]+(\.[0-9]+)*"' |
                                        sed -E 's/[[:space:]]*"name"[[:space:]]*:[[:space:]]*"(v?[0-9]+(\.[0-9]+)*)",/\1/g' |
                                        head -1)
                        fi
                        yush_debug "Discovering release ID for $project at version $version"
                        id=$(   primer_net_curl "${_releases}/tags/$version" |
                                grep -E '"id"[[:space:]]*:[[:space:]]*[0-9]+' |
                                sed -E 's/[[:space:]]*"id"[[:space:]]*:[[:space:]]*([0-9]+),/\1/g' |
                                head -1)

                        _semantic=$(printf %s\\n "$version" | grep -oE '[0-9]+(\.[0-9]+)*')
                        filter=$(   printf %s\\n "$filter" |
                                    sed -e "s/%version%/$version/g" \
                                        -e "s/%semantic%/$_semantic/g" \
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
                    fi
                done <"$PRIMER_STEP_GITHUB_PROJECTS"
            fi
            ;;
        "clean")
            if [ -f "$PRIMER_STEP_GITHUB_PROJECTS" ]; then
                while IFS= read -r line || [ -n "$line" ]; do
                    line=$(printf %s\\n "$line" | sed '/^[[:space:]]*$/d' | sed '/^[[:space:]]*#/d')
                    if [ -n "$line" ]; then
                        project=$(printf %s\\n "$line" | awk '{print $1}')
                        filter=$(printf %s\\n "$line" | awk '{print $2}')
                        bin=$(printf %s\\n "$line" | awk '{print $3}')
                        printf %s\\n "$bin" | grep -qE '(""|'')' && bin=""
                        version=$(printf %s\\n "$line" | awk '{print $4}')
                        printf %s\\n "$version" | grep -qE '(""|'')' && version=""
                        [ -z "$bin" ] && bin=$(yush_basename "$project")

                        yush_debug "Looking for executable matching $bin under $PRIMER_BINDIR"
                        match=$(find "${PRIMER_BINDIR}" -name "$bin" -executable | head -n 1)
                        if [ -n "$match" ]; then
                            yush_notice "Removing $match"
                            $PRIMER_OS_SUDO rm -f "$match"
                        fi
                    fi
                done
            fi
            ;;
    esac
}

_primer_step_github_install_download() {
    tmpdir=$(mktemp -d)
    _fname=$(yush_basename "$1")
    yush_info "Downloading $1"

    case "$_fname" in
        *.tar)
            primer_os_dependency tar
            primer_net_curl "$1" | tar -C "$tmpdir" -xvf -
            ;;
        *.tar.gz | *.tgz)
            primer_os_dependency tar
            primer_net_curl "$1" | tar -C "$tmpdir" -zxvf -
            ;;
        *.tar.bz2 | *.tar.bzip2)
            primer_os_dependency tar
            primer_net_curl "$1" | tar -C "$tmpdir" -jxvf -
            ;;
        *.tar.xz)
            primer_os_dependency tar
            primer_net_curl "$1" | tar -C "$tmpdir" -Jxvf -
            ;;
        *.tar.Z)
            primer_os_dependency tar
            primer_net_curl "$1" | tar -C "$tmpdir" -Zxvf -
            ;;
        *.zip)
            primer_os_dependency unzip
            primer_net_curl "$1" > "${tmpdir}/$_fname"
            unzip "${tmpdir}/$_fname" -d "$tmpdir"
            rm -f "${tmpdir}/$_fname"
            ;;
        default)
            yush_warn "Does not recognise archive type of $_fname";;
    esac

    bin=$(find "$tmpdir" -name "$2" -executable | head -n 1)
    if [ -n "$bin" ]; then
        yush_notice "Installing $(yush_basename "$bin") to $PRIMER_BINDIR"
        $PRIMER_OS_SUDO mv -f "$bin" "${PRIMER_BINDIR}"
    fi
    rm -rf "$tmpdir"
}
