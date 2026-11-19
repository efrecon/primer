#!/bin/sh
# Snippets are single-quoted on purpose: they are expanded in the containers.
# shellcheck disable=SC2016

# Tests of the dynufw step. Enabling ufw changes the netfilter rules of the
# container, so real runs need privileged containers (and network access to
# clone dynufw from GitHub). The mocked test checks the rules and the cron
# setup without privileges, ufw, crontab or network.

# Real installation and cleaning on the image passed as $1.
_dynufw_real() {
    require_privileged
    in_container -P "$1" '
        set -- -s dynufw \
            --dynufw:static 22 \
            --dynufw:static 10.0.0.0~8:2222 \
            --dynufw:static localhost:9000/udp/d \
            --dynufw:rules /primer/test/data/dynufw/rules
        primer_run "$@" install
        assert_equal 0 "$PRIMER_RC" "install status"
        status=$(ufw status)
        assert_contains "Status: active" "$status"
        assert_match "^22/tcp +ALLOW +Anywhere" "$status"
        assert_match "^2222/tcp +ALLOW +10.0.0.0/8" "$status"
        assert_match "^8443/tcp +ALLOW +127.0.0.1 +# localhost" "$status" "dynamic rule from rules file"
        assert_match "^9000/udp +ALLOW +127.0.0.1 +# localhost" "$status" "dynamic rule from static option"
        assert_match "dport 22 " "$(iptables -S ufw-user-input)"
        assert_true grep -qx "IPV6=no" /etc/default/ufw
        assert_true [ -L /usr/local/bin/ufw-dynamic-host-update.sh ]
        assert_true [ -L /usr/local/bin/ufw-clean.sh ]
        assert_contains "/usr/local/bin/ufw-dynamic-host-update.sh -q" "$(crontab -l)"

        # Rules that do not belong to dynufw, one on the port of a dynamic rule,
        # one that dynufw is also asked to open (it must not take it over).
        ufw allow 4444/tcp
        ufw allow 5555/tcp
        ufw allow from 127.0.0.2 to any port 8443 proto tcp comment mine

        primer_run "$@" --dynufw:static 5555 install
        assert_equal 0 "$PRIMER_RC" "second install status"
        assert_equal "ufw allow 5555/tcp" "$(ufw show added | grep "5555")" "existing rule left unmarked"
        assert_equal 1 "$(crontab -l | grep -c ufw-dynamic-host-update.sh)" "cron lines"
        assert_equal 1 "$(grep -c "^udp:9000:localhost$" /etc/ufw-dynamic-hosts.allow)" "dynamic rules"

        primer_run "$@" clean
        assert_equal 0 "$PRIMER_RC" "clean status"
        assert_contains "Status: active" "$(ufw status)" "firewall left enabled"
        added=$(ufw show added)
        assert_not_contains "22" "$added" "rules left after clean"
        assert_not_contains "localhost" "$added" "dynamic rules left after clean"
        assert_not_contains "primer dynufw" "$added" "static rules left after clean"
        assert_contains "ufw allow 4444/tcp" "$added" "other rules kept"
        assert_contains "ufw allow 5555/tcp" "$added" "rule also requested from dynufw kept"
        assert_contains "from 127.0.0.2 to any port 8443 proto tcp comment" "$added" "other rules kept"
        assert_not_contains "ufw-dynamic-host-update.sh" "$(crontab -l 2>/dev/null || true)"
        assert_false [ -e /usr/local/bin/ufw-dynamic-host-update.sh ]
        assert_false [ -e /usr/local/opt/dynufw ]
        assert_false [ -e /etc/ufw-dynamic-hosts.allow ]'
}

test_dynufw_debian() {
    _dynufw_real "$IMG_TRIXIE"
}

test_dynufw_alpine() {
    _dynufw_real "$IMG_ALPINE"
}

test_dynufw_mocked() {
    unit "$IMG_ALPINE" '
        unit_step dynufw
        . test/data/dynufw/ufw.sh
        # Rules of the user, existing before: they must stay theirs.
        printf "ufw allow 22/tcp\nufw limit 8080:8090/udp\n" > /tmp/ufw.added
        crontab() {
            case "$1" in
                -l) [ -f /tmp/crontab ] && cat /tmp/crontab;;
                -) cat > /tmp/crontab.new && mv /tmp/crontab.new /tmp/crontab;;
            esac
        }
        # Fake clone of dynufw: scripts that log their calls.
        git() {
            mock_log git "$@"
            for _last; do :; done
            mkdir -p "$_last"
            for _s in ufw-clean ufw-dynamic-host-update; do
                printf "#!/bin/sh\necho \"%s \$*\" >> %s\n" "$_s" "$MOCK_LOG" > "$_last/$_s.sh"
            done
        }
        primer_step_dynufw option \
            --static 22 --static 8080-8090/udp --static 10.0.0.0~8:2222 \
            --static example.com:443/tcp/d --static bad_host:22 --static 80/icmp \
            --dns 1.1.1.1
        # Notices tell about existing rules
        YUSH_LOG_LEVEL=notice
        run primer_step_dynufw install
        assert_equal 0 "$RUN_RC" "install status"
        assert_contains "bad_host:22 is not a valid port opening specification" "$RUN_ERR"
        assert_contains "80/icmp is not a valid port opening specification" "$RUN_ERR"
        calls=$(mock_calls)
        assert_contains "git clone https://github.com/efrecon/dynufw.git --recurse --branch master --depth 1 /usr/local/opt/dynufw/master" "$calls"
        added=$(grep "^ufw " /tmp/ufw.added)
        assert_contains "ufw allow from 10.0.0.0/8 to any port 2222 proto tcp comment '"'"'primer dynufw'"'"'" "$added" "new rule marked"
        assert_equal "ufw allow 22/tcp" "$(grep " 22/tcp" /tmp/ufw.added)" "existing rule untouched"
        assert_equal "ufw limit 8080:8090/udp" "$(grep " 8080:8090/udp" /tmp/ufw.added)" "existing limit rule untouched"
        assert_contains "A rule for 22/tcp already exists (allow), keeping it as is" "$RUN_ERR"
        assert_contains "A rule for 8080:8090/udp already exists (limit), keeping it as is" "$RUN_ERR"
        assert_not_contains "ufw allow 22/tcp" "$calls" "existing rule not modified"
        assert_not_contains "ufw allow 8080:8090/udp" "$calls" "existing rule not modified"
        assert_not_contains "not listed as expected" "$RUN_ERR"
        assert_contains "ufw-dynamic-host-update -q -s 1.1.1.1" "$calls"
        assert_equal "ufw --force enable" "$(grep "^ufw " "$MOCK_LOG" | tail -n 1)" "firewall enabled last"
        assert_true grep -qx "tcp:443:example.com" /etc/ufw-dynamic-hosts.allow
        assert_equal "* * * * * /usr/local/bin/ufw-dynamic-host-update.sh -q -s 1.1.1.1" "$(cat /tmp/crontab)"

        run primer_step_dynufw install
        assert_equal 0 "$RUN_RC" "second install status"
        assert_equal "$added" "$(grep "^ufw " /tmp/ufw.added)" "rules after second install"
        assert_equal 1 "$(grep -c ufw-dynamic-host-update /tmp/crontab)" "cron lines"
        assert_equal 1 "$(grep -c "^tcp:443:example.com$" /etc/ufw-dynamic-hosts.allow)" "dynamic rules"

        echo "0 0 * * * /usr/bin/other" >> /tmp/crontab
        printf "tcp:22:localhost\nudp:6000-6010:localhost\n" >> /etc/ufw-dynamic-hosts.allow
        # Rules as listed by ufw: the ones of dynufw, and others that must
        # be kept, even when similar to the dynamic ones.
        cat > /tmp/ufw.added <<EOF
Added user rules (see '"'"'ufw status'"'"' for running firewall):
ufw allow 22/tcp
ufw allow 8080:8090/udp comment '"'"'primer dynufw'"'"'
ufw allow from 10.0.0.0/8 to any port 2222 proto tcp comment '"'"'primer dynufw'"'"'
ufw allow from 93.184.215.14 to any port 443 proto tcp comment '"'"'example.com'"'"'
ufw allow from 127.0.0.1 to any port 22 proto tcp comment '"'"'localhost'"'"'
ufw allow from 127.0.0.1 to any port 6000:6010 proto udp comment '"'"'localhost'"'"'
ufw allow from 93.184.215.14 to any port 4430 proto tcp comment '"'"'example.com'"'"'
ufw allow from 127.0.0.1 to any port 2222 proto tcp comment '"'"'localhost'"'"'
ufw allow from 127.0.0.1 to any port 22 proto udp comment '"'"'localhost'"'"'
ufw allow 2200/tcp comment '"'"'primer dynufw too'"'"'
ufw allow 4444/tcp
EOF
        mock_reset
        run primer_step_dynufw clean
        assert_equal 0 "$RUN_RC" "clean status"
        calls=$(mock_calls)
        assert_not_contains "ufw delete allow 22/tcp" "$calls" "rule of the user kept"
        assert_contains "ufw delete allow 8080:8090/udp" "$calls"
        assert_contains "ufw delete allow from 10.0.0.0/8 to any port 2222 proto tcp" "$calls"
        assert_contains "ufw delete allow from 93.184.215.14 to any port 443 proto tcp" "$calls"
        assert_contains "ufw delete allow from 127.0.0.1 to any port 22 proto tcp" "$calls"
        assert_contains "ufw delete allow from 127.0.0.1 to any port 6000:6010 proto udp" "$calls"
        assert_equal 5 "$(grep -c "^ufw delete " "$MOCK_LOG")" "deleted rules"
        assert_not_contains "disable" "$calls" "firewall left enabled"
        assert_equal "0 0 * * * /usr/bin/other" "$(cat /tmp/crontab)" "other cron lines kept"
        assert_false [ -e /usr/local/bin/ufw-dynamic-host-update.sh ]
        assert_false [ -e /usr/local/opt/dynufw ]
        assert_false [ -e /etc/ufw-dynamic-hosts.allow ]'
}
