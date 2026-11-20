#!/bin/sh
# Snippets are single-quoted on purpose: they are expanded in containers.
# shellcheck disable=SC2016

# Unit tests for libexec/net.sh. Firewalls are never touched for real: the
# firewall commands are mocked (functions, or stub executables for dashed
# names such as firewall-cmd).

test__primer_net_ip_debian() {
    # The Debian image has no ip command: iproute2 gets installed.
    unit "$IMG_TRIXIE" '
        assert_false primer_utils_syscmd_exists ip
        _primer_net_ip
        assert_true primer_utils_syscmd_exists ip'
}

test__primer_net_ip_packages() {
    unit "$IMG_ALPINE" '
        mock primer_os_dependency
        for distro in ubuntu debian alpine clear-linux-os fedora; do
            PRIMER_OS_DISTRO=$distro
            _primer_net_ip
        done
        assert_equal "primer_os_dependency ip iproute2
primer_os_dependency ip iproute2
primer_os_dependency ip iproute2
primer_os_dependency ip iproute2
primer_os_dependency ip iproute" "$(mock_calls)"
        PRIMER_OS_DISTRO=unknown
        run _primer_net_ip
        assert_contains "ip installation NYI for unknown" "$RUN_ERR"'
}

test_primer_net_interfaces() {
    unit "$IMG_ALPINE" '
        out=$(primer_net_interfaces)
        assert_match "^lo$" "$out"
        assert_match "^$(default_route_dev)$" "$out"
        assert_not_contains "@" "$out"'
}

test_primer_net_interfaces_parsing() {
    unit "$IMG_ALPINE" '
        ip() {
            cat <<"EOF"
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
2: eth0@if42: <BROADCAST,MULTICAST,UP,LOWER_UP,M-DOWN> mtu 1500 qdisc noqueue state UP
    link/ether 02:42:ac:11:00:02 brd ff:ff:ff:ff:ff:ff
10: wlp3s0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN qlen 1000
    link/ether 3c:a9:f4:00:11:22 brd ff:ff:ff:ff:ff:ff
EOF
        }
        assert_equal "lo
eth0
wlp3s0" "$(primer_net_interfaces)"'
}

test_primer_net_macaddr() {
    unit "$IMG_ALPINE" '
        mac=$(primer_net_macaddr "$(default_route_dev)")
        assert_match "^([0-9a-f]{2}:){5}[0-9a-f]{2}$" "$mac"
        # All interfaces but the loopback
        assert_equal "$mac" "$(primer_net_macaddr)"
        assert_equal "" "$(primer_net_macaddr "")"'
}

test_primer_net_macaddr_parsing() {
    unit "$IMG_ALPINE" '
        ip() {
            case "$*" in
                "addr list")
                    printf "1: lo: <LOOPBACK>\n2: eth0: <UP>\n3: eth1: <UP>\n";;
                "addr show eth0")
                    printf "2: eth0: <UP>\n    link/ether 02:42:AC:11:00:02 brd ff:ff:ff:ff:ff:ff\n";;
                "addr show eth1")
                    printf "3: eth1: <UP>\n    link/ether 3C:A9:F4:00:11:22 brd ff:ff:ff:ff:ff:ff\n";;
            esac
        }
        assert_equal 02:42:ac:11:00:02 "$(primer_net_macaddr eth0)"
        assert_equal "02:42:ac:11:00:02
3c:a9:f4:00:11:22" "$(primer_net_macaddr)"'
}

test_primer_net_primary_interface() {
    unit "$IMG_ALPINE" '
        dev=$(primary_dev_or_skip)
        assert_equal "$dev" "$(primer_net_primary_interface)"
        primer_net_interfaces() { printf "lo\nwlan0\nenp3s0\neth1\n"; }
        assert_equal enp3s0 "$(primer_net_primary_interface)"
        primer_net_interfaces() { printf "lo\nwlan0\ndocker0\n"; }
        assert_equal "" "$(primer_net_primary_interface)"'
}

# Decoding must work with all shells: dash (Debian) has no \x in printf %b.
NET_URLDEC_TEST='
    assert_equal "a b/c" "$(primer_net_urldec "a+b%2Fc")"
    assert_equal "a b/c" "$(primer_net_urldec "a+b%2fc")"
    assert_equal "x:y" "$(printf "x%%3Ay\n" | primer_net_urldec)"
    assert_equal "api\.github\.com" "$(primer_net_urldec "api%5C.github%5C.com")"
    assert_equal "100%" "$(primer_net_urldec "100%25")"
    assert_equal "%zz stays" "$(primer_net_urldec "%zz+stays")"
    assert_equal "plain" "$(primer_net_urldec plain)"
    assert_equal "" "$(primer_net_urldec "")"
    assert_equal "été" "$(primer_net_urldec "%C3%A9t%C3%A9")"
    # Several lines on stdin
    assert_equal "a b
c:d" "$(printf "a+b\nc%%3Ad\n" | primer_net_urldec)"'

test_primer_net_urldec_alpine() {
    unit "$IMG_ALPINE" "$NET_URLDEC_TEST"
}

test_primer_net_urldec_debian() {
    unit "$IMG_TRIXIE" "$NET_URLDEC_TEST"
}

NET_URLENC_TEST='
    assert_equal "abc-XYZ_0.9~" "$(primer_net_urlenc "abc-XYZ_0.9~")"
    assert_equal "a%20b%2fc%3a%25" "$(primer_net_urlenc "a b/c:%")"
    assert_equal "" "$(primer_net_urlenc "")"
    for s in "api\.github\.com" "a b+c" "path/with:colons" "100%" "x=1&y=2"; do
        assert_equal "$s" "$(primer_net_urldec "$(primer_net_urlenc "$s")")" "round trip"
    done'

test_primer_net_urlenc_alpine() {
    unit "$IMG_ALPINE" "$NET_URLENC_TEST"
}

test_primer_net_urlenc_debian() {
    unit "$IMG_TRIXIE" "$NET_URLENC_TEST"
}

test_primer_net_hostname() {
    unit -h primer-unit "$IMG_ALPINE" '
        assert_equal primer-unit "$(primer_net_hostname)"'
}

test_primer_net_active_firewall_ufw() {
    unit "$IMG_ALPINE" '
        ufw() { mock_log ufw "$@"; echo "Status: active"; }
        assert_equal ufw "$(primer_net_active_firewall)"
        assert_equal "ufw status" "$(mock_calls)"'
}

test_primer_net_active_firewall_firewalld() {
    unit "$IMG_ALPINE" '
        # Installed but inactive ufw is skipped
        ufw() { echo "Status: inactive"; }
        mock -o running firewall-cmd
        assert_equal firewalld "$(primer_net_active_firewall)"
        assert_equal "firewall-cmd --state" "$(mock_calls)"'
}

test_primer_net_active_firewall_nftables_systemd() {
    unit "$IMG_ALPINE" '
        mock -o "not running" -r 252 firewall-cmd
        mock nft
        systemctl() { mock_log systemctl "$@"; [ "$1 $2" = "is-active --quiet" ] && [ "$3" = nftables ]; }
        assert_equal nftables "$(primer_net_active_firewall)"
        assert_contains "systemctl is-active --quiet nftables" "$(mock_calls)"
        # Inactive service
        systemctl() { return 3; }
        assert_equal "" "$(primer_net_active_firewall)"'
}

test_primer_net_active_firewall_nftables_openrc() {
    unit "$IMG_ALPINE" '
        mock nft rc-service
        assert_equal nftables "$(primer_net_active_firewall)"
        assert_contains "rc-service nftables status" "$(mock_calls)"
        # Stopped service
        mock -r 3 rc-service
        assert_equal "" "$(primer_net_active_firewall)"'
}

test_primer_net_active_firewall_none() {
    unit "$IMG_ALPINE" '
        run primer_net_active_firewall
        assert_equal 0 "$RUN_RC"
        assert_equal "" "$RUN_OUT"
        # nft without a service manager telling it runs
        mock nft
        assert_equal "" "$(primer_net_active_firewall)"'
}

test__primer_net_port_allow() {
    unit "$IMG_ALPINE" '
        mock ufw nft firewall-cmd
        _primer_net_port_allow ufw 80 tcp
        _primer_net_port_allow firewalld 53 udp
        _primer_net_port_allow nftables 443 tcp
        _primer_net_port_allow unknown 22 tcp
        assert_equal "ufw allow 80/tcp
firewall-cmd --permanent --add-port=53/udp
firewall-cmd --add-port=53/udp
nft add rule inet filter input tcp dport 443 accept" "$(mock_calls)"'
}

test_primer_net_port_allow() {
    unit "$IMG_ALPINE" '
        mock -o ufw primer_net_active_firewall
        mock _primer_net_port_allow
        run primer_net_port_allow 80 443/TCP 0 70000 abc 80/icmp 22/udp
        assert_equal 0 "$RUN_RC"
        assert_equal "primer_net_active_firewall
_primer_net_port_allow ufw 80 tcp
_primer_net_port_allow ufw 80 udp
_primer_net_port_allow ufw 443 tcp
_primer_net_port_allow ufw 22 udp" "$(mock_calls | sed "s/ *$//")"
        assert_contains "Invalid port rule: 0" "$RUN_ERR"
        assert_contains "Invalid port rule: 70000" "$RUN_ERR"
        assert_contains "Invalid port rule: abc" "$RUN_ERR"
        assert_contains "Invalid port protocol in rule: 80/icmp" "$RUN_ERR"
        assert_not_contains "nftables rules are not persistent" "$RUN_ERR"'
}

test_primer_net_port_allow_nftables() {
    unit "$IMG_ALPINE" '
        mock -o nftables primer_net_active_firewall
        mock _primer_net_port_allow
        run primer_net_port_allow 8080/tcp
        assert_equal 0 "$RUN_RC"
        assert_contains "_primer_net_port_allow nftables 8080 tcp" "$(mock_calls)"
        assert_contains "nftables rules are not persistent" "$RUN_ERR"'
}

test_primer_net_port_allow_no_firewall() {
    unit "$IMG_ALPINE" '
        mock primer_net_active_firewall
        mock _primer_net_port_allow
        run primer_net_port_allow 80
        assert_equal 1 "$RUN_RC"
        assert_contains "No active UFW, firewalld, or nftables firewall found" "$RUN_ERR"
        assert_not_contains "_primer_net_port_allow" "$(mock_calls)"'
}

# Options file: first matching (URL-encoded) regex wins, comments are skipped.
NET_CURLOPTS_FIXTURE='
cat > /tmp/curl.opts <<"EOF"
# Comments are skipped, even when matching: .* --comment
api%5C.github%5C.com -u x-access-token:secret
example%5C.com/private --retry 3   -H X-Test:1
.* --catch-all
EOF
'

# Options quoted as in the shell (test/data/net/curlconfig.in), converted to a
# curl config (curlconfig.out): one option per line, values in double quotes,
# with backslashes and quotes escaped. Run with busybox awk and mawk.
NET_CURLCONFIG_CHECKS='
_curlconfig_checks() {
    assert_equal "$(cat /primer/test/data/net/curlconfig.out)" \
        "$(_primer_net_curlconfig < /primer/test/data/net/curlconfig.in)"
}
'

test__primer_net_curlconfig() {
    unit "$IMG_ALPINE" "$NET_CURLCONFIG_CHECKS"'
        _curlconfig_checks'
}

test__primer_net_curlconfig_debian() {
    unit "$IMG_TRIXIE" "$NET_CURLCONFIG_CHECKS"'
        _curlconfig_checks'
}

test__primer_net_curlopts() {
    unit "$IMG_ALPINE" "$NET_CURLOPTS_FIXTURE$NET_CURLCONFIG_CHECKS"'
        _curlconfig_checks
        PRIMER_CURL_OPTIONS=/tmp/curl.opts
        assert_equal "-u \"x-access-token:secret\"" "$(_primer_net_curlopts https://api.github.com/repos/a/b)"
        assert_equal "--retry \"3\"
-H \"X-Test:1\"" "$(_primer_net_curlopts https://example.com/private/file)"
        assert_equal "--catch-all" "$(_primer_net_curlopts https://example.com/public)"
        # Options are never logged, even at the debug level, as they carry
        # secrets
        YUSH_LOG_LEVEL=debug
        assert_not_contains "secret" "$(_primer_net_curlopts https://api.github.com/x 2>&1 >/dev/null)"
        YUSH_LOG_LEVEL=warn
        # No options file, or a missing one: no options
        PRIMER_CURL_OPTIONS=
        assert_equal "" "$(_primer_net_curlopts https://api.github.com/)"
        PRIMER_CURL_OPTIONS=/tmp/missing.opts
        assert_equal "" "$(_primer_net_curlopts https://api.github.com/)"'
}

test__primer_net_curlopts_debian() {
    # The URL-encoded regexes must decode with dash too.
    unit "$IMG_TRIXIE" "$NET_CURLOPTS_FIXTURE$NET_CURLCONFIG_CHECKS"'
        PRIMER_CURL_OPTIONS=/tmp/curl.opts
        assert_equal "-u \"x-access-token:secret\"" "$(_primer_net_curlopts https://api.github.com/repos/a/b)"
        assert_equal "--catch-all" "$(_primer_net_curlopts https://apixgithubxcom.example/)"
        _curlconfig_checks'
}

test_primer_net_curl() {
    unit "$IMG_ALPINE" "$NET_CURLOPTS_FIXTURE"'
        # Logs its arguments, and the config it reads on stdin.
        curl() {
            mock_log curl "$@"
            while IFS= read -r _l; do mock_log "  $_l"; done
        }
        # No options file to start with, even when the prelude made one for
        # GITHUB_TOKEN (CI).
        PRIMER_CURL_OPTIONS=
        # Quiet: failures are errors, no progress
        primer_net_curl https://example.com/a -o /tmp/a
        # Info (the default): no progress either
        YUSH_LOG_LEVEL=info
        primer_net_curl https://example.com/b0
        # Debug: progress bar, failures still errors
        YUSH_LOG_LEVEL=debug
        primer_net_curl https://example.com/b
        # Options from the options file come before the caller options
        YUSH_LOG_LEVEL=warn
        PRIMER_CURL_OPTIONS=/tmp/curl.opts
        primer_net_curl https://api.github.com/x --max-time 5
        assert_equal "curl -K - -fsSL -o /tmp/a https://example.com/a
curl -K - -fsSL https://example.com/b0
curl -K - -fSL --progress-bar https://example.com/b
curl -K - -fsSL --max-time 5 https://api.github.com/x
  -u \"x-access-token:secret\"" "$(mock_calls)"'
}

test_primer_net_curl_debian() {
    # Installs curl when missing, and fails on HTTP errors.
    unit "$IMG_TRIXIE" '
        assert_false command -v curl
        primer_net_curl https://github.com/efrecon/primer -o /dev/null
        assert_true command -v curl
        run primer_net_curl https://github.com/efrecon/primer/this-does-not-exist-404
        assert_equal 22 "$RUN_RC"
        # Options with spaces reach the real curl, through its config.
        echo hello > /tmp/src.txt
        printf "%s\n" "file%3A -o \"/tmp/with space.txt\"" > /tmp/curl.opts
        PRIMER_CURL_OPTIONS=/tmp/curl.opts
        primer_net_curl file:///tmp/src.txt
        assert_equal hello "$(cat "/tmp/with space.txt")"'
}

# Files are only installed when downloaded, never left empty.
test_primer_net_install_file() {
    unit "$IMG_ALPINE" '
        primer_net_curl() {
            case "$1" in
                */ok) echo content;;
                */empty) ;;
                *) return 22;;
            esac
        }
        primer_net_install_file https://x/ok /tmp/new/dir/file
        assert_equal content "$(cat /tmp/new/dir/file)"
        assert_equal 644 "$(stat -c %a /tmp/new/dir/file)"
        for u in empty missing; do
            run primer_net_install_file "https://x/$u" "/tmp/$u"
            assert_equal 1 "$RUN_RC" "$u"
            assert_false test -e "/tmp/$u"
        done
        assert_equal "" "$(ls /tmp/tmp.* 2>/dev/null)" "temporary files"'
}

# Checkouts at a commit, from local repositories: the commit and its
# submodules are checked out, existing checkouts move to a new commit, unknown
# commits fail and leave nothing. Without a commit, the branch is cloned.
test_primer_net_git_clone() {
    unit "$IMG_ALPINE" '
        apk add -q git >/dev/null
        git config --global user.email t@t; git config --global user.name t
        git config --global protocol.file.allow always
        git init -q -b master /tmp/sub && echo sub > /tmp/sub/s && git -C /tmp/sub add s && git -C /tmp/sub commit -qm s
        git init -q -b master /tmp/src
        echo 1 > /tmp/src/f && git -C /tmp/src add f && git -C /tmp/src commit -qm 1
        git -C /tmp/src submodule -q add file:///tmp/sub sub && git -C /tmp/src commit -qm sub
        c1=$(git -C /tmp/src rev-parse HEAD)
        echo 2 > /tmp/src/f && git -C /tmp/src commit -qam 2
        c2=$(git -C /tmp/src rev-parse HEAD)
        git -C /tmp/src config uploadpack.allowAnySHA1InWant true
        primer_net_git_clone file:///tmp/src master "$c1" /opt/src/master
        assert_equal "$c1" "$(git -C /opt/src/master rev-parse HEAD)"
        assert_equal 1 "$(cat /opt/src/master/f)"
        assert_equal sub "$(cat /opt/src/master/sub/s)" "submodule"
        primer_net_git_clone file:///tmp/src master "$c2" /opt/src/master
        assert_equal 2 "$(cat /opt/src/master/f)" "moved to the new commit"
        run primer_net_git_clone file:///tmp/src master "$(printf "%040d" 0)" /opt/src/bad
        assert_equal 1 "$RUN_RC" "unknown commit"
        assert_false test -e /opt/src/bad
        # Short hashes are resolved, tags are refused: they can move.
        primer_net_git_clone file:///tmp/src master "$(printf %s "$c1" | cut -c1-8)" /opt/src/short 2>/dev/null
        assert_equal "$c1" "$(git -C /opt/src/short rev-parse HEAD)" "short hash"
        primer_net_git_clone file:///tmp/src master "$(printf %s "$c2" | cut -c1-7)" /opt/src/short 2>/dev/null
        assert_equal "$c2" "$(git -C /opt/src/short rev-parse HEAD)" "short hash, existing checkout"
        git -C /tmp/src tag v1 "$c1"
        run primer_net_git_clone file:///tmp/src master v1 /opt/src/tag
        assert_equal 1 "$RUN_RC" "tag"
        assert_contains "v1 is not a commit hash" "$RUN_ERR"
        assert_false test -e /opt/src/tag
        # Pinned before, now unpinned: the tip of the branch.
        run primer_net_git_clone file:///tmp/src master "" /opt/src/master
        assert_equal 0 "$RUN_RC" "unpinned after pinned: $RUN_ERR"
        assert_equal master "$(git -C /opt/src/master symbolic-ref --short HEAD)"
        assert_equal "$c2" "$(git -C /opt/src/master rev-parse HEAD)"
        run primer_net_git_clone file:///tmp/src master "" /opt/src/branch
        assert_equal 0 "$RUN_RC" "branch"
        assert_contains "No commit given for file:///tmp/src, installing branch master unverified" "$RUN_ERR"
        assert_equal 2 "$(cat /opt/src/branch/f)"
        echo 3 > /tmp/src/f && git -C /tmp/src commit -qam 3
        primer_net_git_clone file:///tmp/src master "" /opt/src/branch 2>/dev/null
        assert_equal 2 "$(cat /opt/src/branch/f)" "no update"
        primer_net_git_clone file:///tmp/src master "" /opt/src/branch update 2>/dev/null
        assert_equal 3 "$(cat /opt/src/branch/f)" "update"'
}

# Short hashes are resolved from the history of the branch only: unknown
# hashes, or commits of other branches, fail.
test__primer_net_git_resolve() {
    unit "$IMG_ALPINE" '
        apk add -q git >/dev/null
        git config --global user.email t@t; git config --global user.name t
        git init -q -b master /tmp/src
        echo 1 > /tmp/src/f && git -C /tmp/src add f && git -C /tmp/src commit -qm 1
        c1=$(git -C /tmp/src rev-parse HEAD)
        git -C /tmp/src checkout -q -b other && echo 2 > /tmp/src/f && git -C /tmp/src commit -qam 2
        other=$(git -C /tmp/src rev-parse HEAD)
        git -C /tmp/src checkout -q master
        git init -q /tmp/co && git -C /tmp/co remote add origin file:///tmp/src
        assert_equal "$c1" "$(_primer_net_git_resolve /tmp/co master "$c1")" "full hash as is"
        assert_equal "$c1" "$(_primer_net_git_resolve /tmp/co master "$(printf %s "$c1" | cut -c1-6)")"
        assert_false _primer_net_git_resolve /tmp/co master "$(printf %s "$other" | cut -c1-8)"
        assert_false _primer_net_git_resolve /tmp/co master 0000000
        assert_false _primer_net_git_resolve /tmp/co nosuchbranch "$(printf %s "$c1" | cut -c1-8)"'
}
