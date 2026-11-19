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

        primer_run "$@" install
        assert_equal 0 "$PRIMER_RC" "second install status"
        assert_equal 1 "$(crontab -l | grep -c ufw-dynamic-host-update.sh)" "cron lines"
        assert_equal 1 "$(grep -c "^udp:9000:localhost$" /etc/ufw-dynamic-hosts.allow)" "dynamic rules"

        primer_run "$@" clean
        assert_equal 0 "$PRIMER_RC" "clean status"
        assert_contains "Status: inactive" "$(ufw status)"
        added=$(ufw show added)
        assert_not_contains "22" "$added" "rules left after clean"
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
        mock ufw
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
        run primer_step_dynufw install
        assert_equal 0 "$RUN_RC" "install status"
        assert_contains "bad_host:22 is not a valid port opening specification" "$RUN_ERR"
        assert_contains "80/icmp is not a valid port opening specification" "$RUN_ERR"
        calls=$(mock_calls)
        assert_contains "git clone https://github.com/efrecon/dynufw.git --recurse --branch master --depth 1 /usr/local/opt/dynufw/master" "$calls"
        assert_contains "ufw allow 22/tcp" "$calls"
        assert_contains "ufw allow 8080:8090/udp" "$calls"
        assert_contains "ufw allow proto tcp from 10.0.0.0/8 to any port 2222" "$calls"
        assert_contains "ufw-dynamic-host-update -q -s 1.1.1.1" "$calls"
        assert_equal "ufw --force enable" "$(grep "^ufw " "$MOCK_LOG" | tail -n 1)" "firewall enabled last"
        assert_true grep -qx "tcp:443:example.com" /etc/ufw-dynamic-hosts.allow
        assert_equal "* * * * * /usr/local/bin/ufw-dynamic-host-update.sh -q -s 1.1.1.1" "$(cat /tmp/crontab)"

        run primer_step_dynufw install
        assert_equal 0 "$RUN_RC" "second install status"
        assert_equal 1 "$(grep -c ufw-dynamic-host-update /tmp/crontab)" "cron lines"
        assert_equal 1 "$(grep -c "^tcp:443:example.com$" /etc/ufw-dynamic-hosts.allow)" "dynamic rules"

        echo "0 0 * * * /usr/bin/other" >> /tmp/crontab
        mock_reset
        run primer_step_dynufw clean
        assert_equal 0 "$RUN_RC" "clean status"
        calls=$(mock_calls)
        assert_contains "ufw delete allow 22/tcp" "$calls"
        assert_contains "ufw delete allow 8080:8090/udp" "$calls"
        assert_contains "ufw delete allow proto tcp from 10.0.0.0/8 to any port 2222" "$calls"
        assert_contains "ufw --force disable" "$calls"
        assert_equal "0 0 * * * /usr/bin/other" "$(cat /tmp/crontab)" "other cron lines kept"
        assert_false [ -e /usr/local/bin/ufw-dynamic-host-update.sh ]
        assert_false [ -e /usr/local/opt/dynufw ]
        assert_false [ -e /etc/ufw-dynamic-hosts.allow ]'
}
