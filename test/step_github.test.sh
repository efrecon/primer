#!/bin/sh
# shellcheck disable=SC2016

# Tests of the github step: binaries from GitHub release assets. Parsing is
# tested offline against fixtures in test/data/github, modelled after the
# (pretty-printed) GitHub API answers. One test uses the real API.

LAZYDOCKER_VERSION=0.25.2

# Container-side: a primer_net_curl serving the fixtures, and fake assets: a
# tarball containing an executable "tool" and a raw "toolctl" binary.
GITHUB_FIXTURES='
mkdir -p /tmp/fake/tool-1.2.3
printf "#!/bin/sh\necho tool 1.2.3\n" > /tmp/fake/tool-1.2.3/tool
chmod a+x /tmp/fake/tool-1.2.3/tool
tar -C /tmp/fake -czf /tmp/tool.tar.gz tool-1.2.3
printf "#!/bin/sh\necho toolctl 1.2.3\n" > /tmp/toolctl
printf "#!/bin/sh\necho toolgz 1.2.3\n" | gzip -c > /tmp/toolgz.gz
printf "!<arch>\ndebian-binary\n" > /tmp/tool.deb
printf "\177ELF\002\001\001\000" > /tmp/toolelf
# Checksum files for the tarball: coreutils format with another asset first,
# a single sum (published as an asset), BSD format (at another URL).
MD5=$(md5sum < /tmp/tool.tar.gz | cut -d " " -f 1)
SHA256=$(sha256sum < /tmp/tool.tar.gz | cut -d " " -f 1)
SHA512=$(sha512sum < /tmp/tool.tar.gz | cut -d " " -f 1)
printf "%s  other_1.2.3.tar.gz\n%s *tool_1.2.3_Linux_x86_64.tar.gz\n" "$(printf "%064d" 0)" "$SHA256" > /tmp/checksums.txt
printf "%s\n" "$SHA256" > /tmp/tool.sha256
printf "SHA512 (./tool_1.2.3_Linux_x86_64.tar.gz) = %s\r\n" "$SHA512" > /tmp/BSDSUMS
primer_net_curl() {
    mock_log primer_net_curl "$@"
    case "$1" in
        */repos/acme/tool/releases/latest) cat /primer/test/data/github/latest.json;;
        */repos/acme/tool/releases) cat /primer/test/data/github/releases.json;;
        */repos/acme/tool/releases/*/assets) cat /primer/test/data/github/assets.json;;
        */tool_1.2.3_Linux_x86_64.tar.gz) cat /tmp/tool.tar.gz;;
        */toolctl-linux-amd64) cat /tmp/toolctl;;
        */toolgz-linux-amd64.gz) cat /tmp/toolgz.gz;;
        */tool_1.2.3_amd64.deb) cat /tmp/tool.deb;;
        */toolelf-linux-amd64) cat /tmp/toolelf;;
        */v1.2.3/checksums.txt) cat /tmp/checksums.txt;;
        https://sums.example/*/B2SUMS) printf "%0128d  tool_1.2.3_Linux_x86_64.tar.gz\n" 0;;
        https://sums.example/*/blake.txt) printf "BLAKE2b (tool_1.2.3_Linux_x86_64.tar.gz) = %0128d\n" 0;;
        https://sums.example/*/openssl.txt) printf "SHA2-256(tool_1.2.3_Linux_x86_64.tar.gz)= %s\n" "$SHA256";;
        https://sums.example/*/SHA512SUMS) printf "%s  tool_1.2.3_Linux_x86_64.tar.gz\n" "$SHA256";;
        */tool_1.2.3_Linux_x86_64.tar.gz.sha256) cat /tmp/tool.sha256;;
        https://sums.example/v1.2.3/BSDSUMS) cat /tmp/BSDSUMS;;
        *) return 22;;
    esac
}
'

test_github_latest_release() {
    unit "$IMG_ALPINE" "$GITHUB_FIXTURES"'
        unit_step github
        # The release id, not the id of the author of the release.
        assert_equal "$(printf "v1.2.3\tv1.2.3\t111")" "$(_primer_step_github_latest acme/tool)"'
}

test_github_release_by_version() {
    unit "$IMG_ALPINE" "$GITHUB_FIXTURES"'
        unit_step github
        assert_equal "$(printf "v1.2.3\tv1.2.3\t111")" "$(_primer_step_github_by_version acme/tool "v1.2*")"
        assert_equal "$(printf "v1.0.0\tv1.0.0\t100")" "$(_primer_step_github_by_version acme/tool "v1.0*")"
        assert_equal "" "$(_primer_step_github_by_version acme/tool "v9*")"'
}

test_github_install_offline() {
    unit "$IMG_ALPINE" "$GITHUB_FIXTURES"'
        cat > /tmp/projects <<EOF
# Latest release, archive asset with substitutions
acme/tool tool_%semantic%_Linux_x86_64.tar.gz

# Release by version, raw binary asset
acme/tool toolctl-linux-amd64 v1.2* toolctl
EOF
        unit_step github
        primer_step_github option --projects /tmp/projects
        run primer_step_github install
        assert_equal 0 "$RUN_RC"
        assert_equal "tool 1.2.3" "$(/usr/local/bin/tool)"
        assert_equal "toolctl 1.2.3" "$(/usr/local/bin/toolctl)"
        assert_contains "/releases/111/assets" "$(mock_calls)"

        # Clean only removes the binaries from the top of the binaries directory.
        mkdir -p /usr/local/bin/sub
        cp /usr/local/bin/tool /usr/local/bin/sub/tool
        run primer_step_github clean
        assert_equal 0 "$RUN_RC"
        assert_false test -e /usr/local/bin/tool
        assert_false test -e /usr/local/bin/toolctl
        assert_true test -x /usr/local/bin/sub/tool'
}

# Single files: compressed binaries are uncompressed, binaries (ELF) and
# scripts installed, anything else (e.g. packages) is not.
test_github_install_single_files() {
    unit "$IMG_ALPINE" "$GITHUB_FIXTURES"'
        cat > /tmp/projects <<EOF
acme/tool toolgz-linux-amd64.gz v1.2* toolgz
acme/tool tool_1.2.3_amd64.deb v1.2* tool
acme/tool toolelf-linux-amd64 v1.2* toolelf
EOF
        unit_step github
        primer_step_github option --projects /tmp/projects
        run primer_step_github install
        assert_equal 0 "$RUN_RC"
        assert_equal "toolgz 1.2.3" "$(/usr/local/bin/toolgz)"
        assert_true test -x /usr/local/bin/toolelf
        assert_true cmp /tmp/toolelf /usr/local/bin/toolelf
        assert_contains "tool is neither a binary nor a script, not installing it" "$RUN_ERR"
        assert_false test -e /usr/local/bin/tool'
}

test_github_unknown_release() {
    unit "$IMG_ALPINE" "$GITHUB_FIXTURES"'
        echo "acme/tool tool_%semantic%_Linux_x86_64.tar.gz v9*" > /tmp/projects
        unit_step github
        primer_step_github option --projects /tmp/projects
        run primer_step_github install
        assert_equal 0 "$RUN_RC"
        assert_contains "Cannot find release id" "$RUN_ERR"
        assert_false test -e /usr/local/bin/tool'
}

# Real GitHub API and download, with a version glob, verified against the
# checksums published with the release.
test_github_install_real() {
    in_container "$IMG_ALPINE" '
        echo "jesseduffield/lazydocker lazydocker_%semantic%_%Kernel%_%Machine%.tar.gz v'"$LAZYDOCKER_VERSION"' \"\" checksums.txt" > /tmp/projects
        primer_run -v info -s github --github:projects /tmp/projects --github:verify 1 install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "Verified sha256 sum of lazydocker_" "$PRIMER_ERR"
        assert_contains "Version: '"$LAZYDOCKER_VERSION"'" "$(/usr/local/bin/lazydocker --version)"
        primer_run -s github --github:projects /tmp/projects clean
        assert_equal 0 "$PRIMER_RC"
        assert_false test -e /usr/local/bin/lazydocker'
}

# Clean only removes the binaries of the projects, not other executables.
test_github_clean_keeps_other_binaries() {
    unit "$IMG_ALPINE" '
        mkdir -p /usr/local/bin
        for b in othertool toolbox; do
            printf "#!/bin/sh\n" > /usr/local/bin/$b; chmod a+x /usr/local/bin/$b
        done
        printf "#!/bin/sh\n" > /usr/local/bin/tool; chmod a+x /usr/local/bin/tool
        printf "acme/tool tool_%%semantic%%_Linux_x86_64.tar.gz\n" > /tmp/projects
        unit_step github
        primer_step_github option --projects /tmp/projects
        run primer_step_github clean
        assert_equal 0 "$RUN_RC"
        assert_false test -e /usr/local/bin/tool
        assert_true test -x /usr/local/bin/othertool
        assert_true test -x /usr/local/bin/toolbox
        run primer_step_github clean
        assert_equal 0 "$RUN_RC" "second clean"'
}

# Install the tarball of acme/tool with the checksum field $1, from the latest
# release. Container-side, after the fixtures.
GITHUB_CHECKSUM='
unit_step github
primer_step_github option --projects /tmp/projects
install_with() {
    rm -f /usr/local/bin/tool
    printf "acme/tool tool_%%semantic%%_Linux_x86_64.tar.gz %s %s %s\n" "${2:-\"\"}" "${3:-\"\"}" "$1" > /tmp/projects
    run primer_step_github install
}
'

# Sums in the projects file, recognised by their length: sha256, sha512, in any
# case. Wrong sums, or sums of other lengths (e.g. md5), install nothing and
# fail.
test_github_checksum_direct() {
    unit "$IMG_ALPINE" "$GITHUB_FIXTURES$GITHUB_CHECKSUM"'
        YUSH_LOG_LEVEL=info
        for sum in "$SHA256" "$(printf %s "$SHA512" | tr a-f A-F)"; do
            install_with "$sum"
            assert_equal 0 "$RUN_RC" "${#sum} digits: $RUN_ERR"
            assert_equal "tool 1.2.3" "$(/usr/local/bin/tool)"
        done
        assert_contains "Verified sha512 sum of tool_1.2.3_Linux_x86_64.tar.gz" "$RUN_ERR"
        install_with "$MD5"
        assert_equal 1 "$RUN_RC" "md5"
        assert_contains "is not a sha256 or sha512 sum" "$RUN_ERR"
        assert_false test -e /usr/local/bin/tool
        install_with "$(printf "%064d" 0)"
        assert_equal 1 "$RUN_RC" "wrong sum"
        assert_contains "Checksum mismatch for tool_1.2.3_Linux_x86_64.tar.gz" "$RUN_ERR"
        assert_false test -e /usr/local/bin/tool
        install_with "$(printf "%040d" 0)"
        assert_equal 1 "$RUN_RC" "sha1 length"
        assert_contains "is not a sha256 or sha512 sum" "$RUN_ERR"
        assert_false test -e /usr/local/bin/tool'
}

# Checksum files: an asset of the release by name or with %asset%, or a URL
# with tokens, in coreutils, single-sum and BSD formats.
test_github_checksum_files() {
    unit "$IMG_ALPINE" "$GITHUB_FIXTURES$GITHUB_CHECKSUM"'
        YUSH_LOG_LEVEL=info
        install_with checksums.txt
        assert_equal 0 "$RUN_RC" "checksums.txt: $RUN_ERR"
        assert_contains "Verified sha256 sum" "$RUN_ERR"
        assert_contains "/v1.2.3/checksums.txt" "$(mock_calls)"
        assert_equal "tool 1.2.3" "$(/usr/local/bin/tool)"
        install_with "%asset%.sha256"
        assert_equal 0 "$RUN_RC" "single sum: $RUN_ERR"
        assert_true test -x /usr/local/bin/tool
        install_with "https://sums.example/%tag%/BSDSUMS"
        assert_equal 0 "$RUN_RC" "BSD format: $RUN_ERR"
        assert_contains "Verified sha512 sum" "$RUN_ERR"
        assert_true test -x /usr/local/bin/tool
        install_with "https://sums.example/%tag%/openssl.txt"
        assert_equal 0 "$RUN_RC" "OpenSSL format: $RUN_ERR"
        assert_contains "Verified sha256 sum" "$RUN_ERR"'
}

# A checksum file that cannot be found, downloaded, or that has no sum for the
# asset: nothing is installed, and the step fails.
test_github_checksum_failures() {
    unit "$IMG_ALPINE" "$GITHUB_FIXTURES$GITHUB_CHECKSUM"'
        install_with "nosuch*.txt"
        assert_equal 1 "$RUN_RC" "no asset"
        assert_contains "No checksum file matching nosuch*.txt" "$RUN_ERR"
        install_with "https://sums.example/missing"
        assert_equal 1 "$RUN_RC" "download"
        assert_contains "Could not download checksums from https://sums.example/missing" "$RUN_ERR"
        echo "acme/tool toolctl-linux-amd64 v1.2* toolctl checksums.txt" > /tmp/projects
        run primer_step_github install
        assert_equal 1 "$RUN_RC" "no entry"
        assert_contains "No checksum for toolctl-linux-amd64 in" "$RUN_ERR"
        assert_false test -e /usr/local/bin/toolctl
        assert_false test -e /usr/local/bin/tool'
}

# Sums of other algorithms, with the length of sha256 or sha512 sums, are told
# by the name of the checksum file or their tag: refused, not checked as sha
# sums. The name or tag also has to agree with the length.
test_github_checksum_algorithms() {
    unit "$IMG_ALPINE" "$GITHUB_FIXTURES$GITHUB_CHECKSUM"'
        install_with "https://sums.example/%tag%/B2SUMS"
        assert_equal 1 "$RUN_RC" "B2SUMS"
        assert_contains "blake2b sums are not supported" "$RUN_ERR"
        assert_not_contains "mismatch" "$RUN_ERR"
        install_with "https://sums.example/%tag%/blake.txt"
        assert_equal 1 "$RUN_RC" "BLAKE2b tag"
        assert_contains "blake2b sums are not supported" "$RUN_ERR"
        install_with "https://sums.example/%tag%/SHA512SUMS"
        assert_equal 1 "$RUN_RC" "sha256 sum in SHA512SUMS"
        assert_contains "is not a sha512 sum" "$RUN_ERR"
        assert_false test -e /usr/local/bin/tool'
}

# Without checksum: installed with a warning, unless verification is required.
test_github_checksum_none() {
    unit "$IMG_ALPINE" "$GITHUB_FIXTURES$GITHUB_CHECKSUM"'
        install_with ""
        assert_equal 0 "$RUN_RC"
        assert_contains "No checksum for tool_1.2.3_Linux_x86_64.tar.gz of acme/tool, installing unverified" "$RUN_ERR"
        assert_true test -x /usr/local/bin/tool
        primer_step_github option --verify 1
        install_with ""
        assert_equal 1 "$RUN_RC" "with --verify"
        assert_contains "not installing it" "$RUN_ERR"
        assert_false test -e /usr/local/bin/tool
        assert_contains "--verify" "$(primer_step_github option)"'
}

# Sums from checksum files: the line for the asset, compared without leading
# directories or *, or the only sum of a file without names.
test_github_checksum_lookup() {
    unit "$IMG_ALPINE" '
        unit_step github
        printf "aaa  ./dir/x.tar.gz\nbbb *y.tar.gz\nSHA256 (z.tar.gz) = ccc\nddd  name with space.zip\n" > /tmp/sums
        assert_equal aaa "$(_primer_step_github_sum_lookup /tmp/sums x.tar.gz)"
        assert_equal bbb "$(_primer_step_github_sum_lookup /tmp/sums y.tar.gz)"
        assert_equal "ccc sha256" "$(_primer_step_github_sum_lookup /tmp/sums z.tar.gz)"
        assert_equal ddd "$(_primer_step_github_sum_lookup /tmp/sums "name with space.zip")"
        assert_equal "" "$(_primer_step_github_sum_lookup /tmp/sums w.tar.gz)"
        printf "\n eee \n" > /tmp/single
        assert_equal eee "$(_primer_step_github_sum_lookup /tmp/single anything)"
        assert_false _primer_step_github_sum "$(printf "%032d" 0)"
        assert_equal sha256sum "$(_primer_step_github_sum "$(printf "%064d" 0)")"
        assert_equal sha512sum "$(_primer_step_github_sum "$(printf "%0128d" 0)")"
        assert_equal sha512sum "$(_primer_step_github_sum "$(printf "%0128d" 0)" sha512)"
        assert_false _primer_step_github_sum "$(printf "%0128d" 0)" blake2b
        assert_false _primer_step_github_sum "$(printf "%064d" 0)" sha512
        assert_false _primer_step_github_sum "$(printf "%063dg" 0)"
        for pair in SHA256SUMS:sha256 sha512sums.txt:sha512 x.tar.gz.sha384:sha384 \
                B2SUMS:blake2b x.b2:blake2b x.md5:md5 SHA1SUMS:sha1 checksums.txt: \
                "https://h/v1/SHA256SUMS?raw=1:sha256" x.sha:; do
            assert_equal "${pair##*:}" "$(_primer_step_github_algo "${pair%:*}")" "$pair"
        done'
}
