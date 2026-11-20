#!/bin/sh
# shellcheck disable=SC2016

# Unit tests for libexec/github.sh: downloads of release assets from GitHub,
# verification and installation. A fake release of the project acme/tool,
# tagged v1.0, is served by primer_net_curl.

GITHUB_RELEASE='
mkdir -p /tmp/rel/tool-1.0
printf "#!/bin/sh\necho tool 1.0\n" > /tmp/rel/tool-1.0/tool
printf "#!/bin/sh\nexit 3\n" > /tmp/rel/tool-1.0/broken
printf "not executable\n" > /tmp/rel/tool-1.0/README
chmod a+x /tmp/rel/tool-1.0/tool /tmp/rel/tool-1.0/broken
tar -C /tmp/rel -czf /tmp/tool.tar.gz tool-1.0
printf "#!/bin/sh\necho raw 1.0\n" > /tmp/toolraw
printf "#!/bin/sh\necho gz 1.0\n" | gzip -c > /tmp/toolgz.gz
printf "!<arch>\ndebian-binary\n" > /tmp/tool.deb
SUM=$(sha256sum < /tmp/tool.tar.gz | cut -d " " -f 1)
printf "%s  other.tar.gz\n%s *tool.tar.gz\n%s  toolraw\n" "$(printf "%064d" 0)" "$SUM" \
    "$(sha256sum < /tmp/toolraw | cut -d " " -f 1)" > /tmp/checksums.txt
REL=https://github.com/acme/tool/releases/download/v1.0
primer_net_curl() {
    mock_log primer_net_curl "$@"
    case "$1" in
        "$REL"/tool.tar.gz) cat /tmp/tool.tar.gz;;
        "$REL"/toolraw) cat /tmp/toolraw;;
        "$REL"/toolgz.gz) cat /tmp/toolgz.gz;;
        "$REL"/tool.deb) cat /tmp/tool.deb;;
        "$REL"/checksums.txt) cat /tmp/checksums.txt;;
        "$REL"/tool.tar.gz.sha256) printf "%s\n" "$SUM";;
        *) return 22;;
    esac
}
'

# The latest tag comes from the redirect of the web site, without any API call,
# or from the API when that fails.
test_primer_github_latest() {
    unit "$IMG_ALPINE" '
        primer_net_curl() {
            mock_log primer_net_curl "$@"
            case "$1" in
                https://github.com/acme/tool/releases/latest)
                    [ -n "${REDIRECT:-}" ] && printf "%s" "$REDIRECT";;
                https://api.github.com/repos/acme/tool/releases/latest)
                    printf "{\n  \"url\": \"x\",\n  \"author\": {\n    \"tag_name\": \"nested\"\n  },\n  \"tag_name\": \"v2.0\"\n}\n";;
                *) return 22;;
            esac
        }
        REDIRECT=https://github.com/acme/tool/releases/tag/v1.0
        assert_equal v1.0 "$(primer_github_latest acme/tool)"
        assert_not_contains api.github.com "$(mock_calls)"
        assert_contains "-w %{url_effective}" "$(mock_calls)"
        # No redirect to a tag: the API.
        REDIRECT=https://github.com/acme/tool/releases
        assert_equal v2.0 "$(primer_github_latest acme/tool)"
        REDIRECT=
        assert_equal v2.0 "$(primer_github_latest acme/tool)"
        # Nothing at all: empty, no failure.
        assert_equal "" "$(primer_github_latest acme/none)"'
}

test_primer_github_url() {
    unit "$IMG_ALPINE" '
        assert_equal https://github.com/acme/tool/releases/download/v1.0/tool.tar.gz \
            "$(primer_github_url acme/tool v1.0 tool.tar.gz)"
        PRIMER_GITHUB_DOWNLOAD=http://mirror.example/
        assert_equal http://mirror.example/acme/tool/releases/download/v1.0/x \
            "$(primer_github_url acme/tool v1.0 x)"'
}

test_primer_github_tokens() {
    unit "$IMG_ALPINE" '
        uname() { case "$1" in -m) echo X86_64;; *) echo Linux;; esac; }
        assert_equal "tool_1.2.3_Linux_x86_64-Version 1.2.3-v1.2.3-1.2.3-a&b/c.sha" \
            "$(primer_github_tokens "tool_%semantic%_%Kernel%_%machine%-%version%-%tag%-%semtag%-%asset%.sha" v1.2.3 "Version 1.2.3" "a&b/c")"
        # The version defaults to the tag.
        assert_equal "v1.0 1.0" "$(primer_github_tokens "%version% %semantic%" v1.0)"
        assert_match "^(32|64)$" "$(primer_github_tokens %bits% v1)"'
}

test__primer_github_sedesc() {
    unit "$IMG_ALPINE" '
        assert_equal "a\\&b\\/c" "$(_primer_github_sedesc "a&b/c")"
        assert_equal "x/y" "$(echo z | sed "s/z/$(_primer_github_sedesc "x/y")/")"'
}

# Sums given directly, checksum files by URL or by name in the release.
test_primer_github_verify() {
    unit "$IMG_ALPINE" "$GITHUB_RELEASE"'
        YUSH_LOG_LEVEL=info
        run primer_github_verify /tmp/tool.tar.gz tool.tar.gz "$SUM"
        assert_equal 0 "$RUN_RC" "direct sum"
        assert_contains "Verified sha256 sum of tool.tar.gz" "$RUN_ERR"
        run primer_github_verify /tmp/tool.tar.gz tool.tar.gz checksums.txt acme/tool v1.0
        assert_equal 0 "$RUN_RC" "file in the release"
        run primer_github_verify /tmp/tool.tar.gz tool.tar.gz "%asset%.sha256" acme/tool v1.0
        assert_equal 0 "$RUN_RC" "file named after the asset"
        run primer_github_verify /tmp/tool.tar.gz tool.tar.gz "$REL/checksums.txt"
        assert_equal 0 "$RUN_RC" "URL"
        run primer_github_verify /tmp/tool.tar.gz tool.tar.gz ""
        assert_equal 0 "$RUN_RC" "no checksum"
        assert_contains "No checksum for tool.tar.gz, installing unverified" "$RUN_ERR"
        # Failures
        run primer_github_verify /tmp/tool.tar.gz tool.tar.gz "$(printf "%064d" 0)"
        assert_equal 1 "$RUN_RC" "mismatch"
        assert_contains "Checksum mismatch for tool.tar.gz" "$RUN_ERR"
        run primer_github_verify /tmp/tool.tar.gz tool.tar.gz "$(printf "%032d" 0)"
        assert_equal 1 "$RUN_RC" "md5"
        assert_contains "is not a sha256 or sha512 sum" "$RUN_ERR"
        run primer_github_verify /tmp/tool.tar.gz tool.tar.gz checksums.txt
        assert_equal 1 "$RUN_RC" "no release"
        assert_contains "No release to find the checksum file checksums.txt in" "$RUN_ERR"
        run primer_github_verify /tmp/tool.tar.gz tool.tar.gz missing.txt acme/tool v1.0
        assert_equal 1 "$RUN_RC" "missing file"
        assert_contains "Could not download checksums from $REL/missing.txt" "$RUN_ERR"
        run primer_github_verify /tmp/tool.tar.gz absent.tar.gz checksums.txt acme/tool v1.0
        assert_equal 1 "$RUN_RC" "no entry"
        assert_contains "No checksum for absent.tar.gz in" "$RUN_ERR"'
}

# Archives are unpacked, single files named and made executable, anything else
# removed. Failures leave nothing behind.
test_primer_github_fetch() {
    unit "$IMG_ALPINE" "$GITHUB_RELEASE"'
        mkdir /tmp/out
        primer_github_fetch acme/tool v1.0 tool.tar.gz checksums.txt /tmp/out
        assert_true test -x /tmp/out/tool-1.0/tool
        rm -rf /tmp/out/*
        primer_github_fetch acme/tool v1.0 toolraw "" /tmp/out toolctl
        assert_equal "raw 1.0" "$(/tmp/out/toolctl)"
        primer_github_fetch acme/tool v1.0 toolgz.gz "" /tmp/out
        assert_equal "gz 1.0" "$(/tmp/out/toolgz)"
        rm -rf /tmp/out/*
        run primer_github_fetch acme/tool v1.0 tool.deb "" /tmp/out
        assert_equal 0 "$RUN_RC" "package"
        assert_contains "neither a binary nor a script" "$RUN_ERR"
        assert_equal "" "$(ls /tmp/out)"
        run primer_github_fetch acme/tool v1.0 tool.tar.gz "$(printf "%064d" 0)" /tmp/out
        assert_equal 1 "$RUN_RC" "mismatch"
        run primer_github_fetch acme/tool v1.0 missing.tar.gz "" /tmp/out
        assert_equal 1 "$RUN_RC" "missing asset"
        assert_contains "No binary at $REL/missing.tar.gz" "$RUN_ERR"
        assert_equal "" "$(ls /tmp/out)"
        assert_equal "" "$(ls /tmp/tmp.* 2>/dev/null)" "temporary files"'
}

# Installation directory and name, checks before installation, root-owned
# binaries, nothing installed on failure.
test_primer_github_install() {
    unit "$IMG_ALPINE" "$GITHUB_RELEASE"'
        primer_github_install --sum checksums.txt acme/tool v1.0 tool.tar.gz
        assert_equal "tool 1.0" "$(/usr/local/bin/tool)"
        assert_equal "755 root" "$(stat -c "%a %U" /usr/local/bin/tool)"
        primer_github_install --dest /opt/plugins --name docker-tool --check --version \
            --sum checksums.txt acme/tool v1.0 tool.tar.gz tool
        assert_equal "tool 1.0" "$(/opt/plugins/docker-tool)"
        primer_github_install --sum checksums.txt acme/tool v1.0 toolraw toolctl
        assert_equal "raw 1.0" "$(/usr/local/bin/toolctl)"
        # From another URL, e.g. as given by the API.
        mock_reset
        primer_github_install --url "$REL/toolraw" acme/tool "v#1" toolraw toolurl 2>/dev/null
        assert_equal "raw 1.0" "$(/usr/local/bin/toolurl)"
        assert_contains "primer_net_curl $REL/toolraw" "$(mock_calls)"
        # The check fails: nothing installed.
        run primer_github_install --check --version --sum checksums.txt acme/tool v1.0 tool.tar.gz "*o*"
        assert_equal 1 "$RUN_RC" "failed check"
        assert_contains "Downloaded binary broken from tool.tar.gz probably invalid" "$RUN_ERR"
        assert_false test -e /usr/local/bin/broken
        # Several binaries for one name.
        run primer_github_install --name x --sum checksums.txt acme/tool v1.0 tool.tar.gz "*o*"
        assert_equal 1 "$RUN_RC" "several binaries"
        assert_false test -e /usr/local/bin/x
        # No binary: 2.
        run primer_github_install --sum checksums.txt acme/tool v1.0 tool.tar.gz nothing
        assert_equal 2 "$RUN_RC" "no binary"
        assert_contains "No executable matching nothing in tool.tar.gz" "$RUN_ERR"
        # Verification failure.
        rm -f /usr/local/bin/tool
        run primer_github_install --sum "$(printf "%064d" 0)" acme/tool v1.0 tool.tar.gz
        assert_equal 1 "$RUN_RC" "mismatch"
        assert_false test -e /usr/local/bin/tool'
}

test__primer_github_sum() {
    unit "$IMG_ALPINE" '
        assert_false _primer_github_sum "$(printf "%032d" 0)"
        assert_equal sha256sum "$(_primer_github_sum "$(printf "%064d" 0)")"
        assert_equal sha256sum "$(_primer_github_sum "$(printf "%064d" 0)" sha256)"
        assert_equal sha512sum "$(_primer_github_sum "$(printf "%0128d" 0)")"
        assert_equal sha512sum "$(_primer_github_sum "$(printf "%0128d" 0)" sha512)"
        assert_false _primer_github_sum "$(printf "%0128d" 0)" blake2b
        assert_false _primer_github_sum "$(printf "%064d" 0)" sha512
        assert_false _primer_github_sum "$(printf "%063dg" 0)"'
}

test__primer_github_algo() {
    unit "$IMG_ALPINE" '
        for pair in SHA256SUMS:sha256 sha512sums.txt:sha512 x.tar.gz.sha384:sha384 \
                B2SUMS:blake2b x.b2:blake2b x.md5:md5 SHA1SUMS:sha1 checksums.txt: \
                "https://h/v1/SHA256SUMS?raw=1:sha256" x.sha:; do
            assert_equal "${pair##*:}" "$(_primer_github_algo "${pair%:*}")" "$pair"
        done
        # The name of the asset does not count.
        assert_equal "" "$(_primer_github_algo https://h/sha1dc-MD5.tar.gz.sha sha1dc-md5.tar.gz)"
        assert_equal sha256 "$(_primer_github_algo https://h/sha1dc.tar.gz.sha256 sha1dc.tar.gz)"
        assert_equal md5 "$(_primer_github_algo https://h/md5tool.tar.gz.sha)"
        assert_equal "" "$(_primer_github_algo https://h/md5tool.tar.gz.sha md5tool.tar.gz)"'
}

# Sums from checksum files: the line for the asset, compared without leading
# directories or *, with the algorithm of BSD lines, or the only sum of a file
# without names.
test__primer_github_sum_lookup() {
    unit "$IMG_ALPINE" '
        printf "aaa  ./dir/x.tar.gz\nbbb *y.tar.gz\nSHA256 (z.tar.gz) = ccc\nddd  name with space.zip\nSHA2-512(o.tar.gz)= fff\r\n" > /tmp/sums
        assert_equal aaa "$(_primer_github_sum_lookup /tmp/sums x.tar.gz)"
        assert_equal bbb "$(_primer_github_sum_lookup /tmp/sums y.tar.gz)"
        assert_equal "ccc sha256" "$(_primer_github_sum_lookup /tmp/sums z.tar.gz)"
        assert_equal ddd "$(_primer_github_sum_lookup /tmp/sums "name with space.zip")"
        assert_equal "fff sha512" "$(_primer_github_sum_lookup /tmp/sums o.tar.gz)"
        assert_equal "" "$(_primer_github_sum_lookup /tmp/sums w.tar.gz)"
        printf "\n eee \n" > /tmp/single
        assert_equal eee "$(_primer_github_sum_lookup /tmp/single anything)"
        # As printed by sha256sum < file, alone in the file.
        printf "abc  -\n" > /tmp/dash
        assert_equal abc "$(_primer_github_sum_lookup /tmp/dash anything)"
        printf "abc  -\nbcd  -\n" > /tmp/dashes
        assert_equal "" "$(_primer_github_sum_lookup /tmp/dashes anything)"
        # PGP-signed files, e.g. sha256sums.asc of git LFS.
        printf "%s\n" "-----BEGIN PGP SIGNED MESSAGE-----" "Hash: SHA256" "" "abc *lfs.tar.gz" "-----BEGIN PGP SIGNATURE-----" "xyz" > /tmp/asc
        assert_equal abc "$(_primer_github_sum_lookup /tmp/asc lfs.tar.gz)"
        assert_equal "" "$(_primer_github_sum_lookup /tmp/asc SHA256)"'
}

# All compression letters of tar.
test__primer_github_untar() {
    unit "$IMG_ALPINE" '
        apk add -q xz >/dev/null
        mkdir -p /tmp/src && echo hi > /tmp/src/f
        for l in "" z j J; do
            tar -C /tmp/src -c${l}f /tmp/a.tar f
            rm -rf /tmp/dst && mkdir /tmp/dst
            _primer_github_untar /tmp/a.tar /tmp/dst "$l"
            assert_equal hi "$(cat /tmp/dst/f)" "letter [$l]"
        done'
}

test__primer_github_executable() {
    unit "$IMG_ALPINE" '
        printf "#!/bin/sh\n" > /tmp/script
        printf "\177ELF\002\001" > /tmp/elf
        printf "PK\003\004" > /tmp/other
        for f in script elf other; do _primer_github_executable /tmp/$f; done
        assert_true test -x /tmp/script
        assert_true test -x /tmp/elf
        assert_false test -e /tmp/other'
}

test__primer_github_xz_dependency() {
    unit "$IMG_TRIXIE" '
        mock primer_os_packages
        primer_utils_syscmd_exists() { return 1; }
        _primer_github_xz_dependency
        PRIMER_OS_DISTRO=alpine
        _primer_github_xz_dependency
        assert_equal "primer_os_packages add xz-utils
primer_os_packages add xz" "$(mock_calls)"'
}
