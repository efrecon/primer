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
primer_net_curl() {
    mock_log primer_net_curl "$@"
    case "$1" in
        */repos/acme/tool/releases/latest) cat /primer/test/data/github/latest.json;;
        */repos/acme/tool/releases) cat /primer/test/data/github/releases.json;;
        */repos/acme/tool/releases/*/assets) cat /primer/test/data/github/assets.json;;
        */tool_1.2.3_Linux_x86_64.tar.gz) cat /tmp/tool.tar.gz;;
        */toolctl-linux-amd64) cat /tmp/toolctl;;
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

# Real GitHub API and download, with a version glob.
test_github_install_real() {
    in_container "$IMG_ALPINE" '
        echo "jesseduffield/lazydocker lazydocker_%semantic%_%Kernel%_%Machine%.tar.gz v'"$LAZYDOCKER_VERSION"'" > /tmp/projects
        primer_run -s github --github:projects /tmp/projects install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "Version: '"$LAZYDOCKER_VERSION"'" "$(/usr/local/bin/lazydocker --version)"
        primer_run -s github --github:projects /tmp/projects clean
        assert_equal 0 "$PRIMER_RC"
        assert_false test -e /usr/local/bin/lazydocker'
}
