#!/bin/sh

# Snippets in single quotes are expanded in the containers, not here.
# shellcheck disable=SC2016

# Tests for the freeform step, using the fixture tree at test/data/freeform.

test_freeform_runs_executables_in_order() {
    primer_in "$IMG_ALPINE" -s freeform --freeform:root /primer/test/data/freeform install -- '
        assert_equal 0 "$PRIMER_RC"
        # Only executable *.sh files directly under install/, sorted. The first
        # one reads its stdin, which must not swallow the remaining scripts.
        assert_equal "stdin a b" "$(tr "\n" " " < /tmp/freeform.log | sed "s/ $//")"'
}

test_freeform_filter() {
    primer_in "$IMG_TRIXIE" -s freeform --freeform:root /primer/test/data/freeform --freeform:filter "*" install -- '
        assert_equal 0 "$PRIMER_RC"
        assert_equal "stdin a b bin" "$(tr "\n" " " < /tmp/freeform.log | sed "s/ $//")"'
}

test_freeform_clean() {
    primer_in "$IMG_ALPINE" -s freeform --freeform:root /primer/test/data/freeform clean -- '
        assert_equal 0 "$PRIMER_RC"
        assert_equal clean "$(cat /tmp/freeform.log)"'
}

test_freeform_without_sudo() {
    primer_in "$IMG_ALPINE" -s freeform --freeform:root /primer/test/data/freeform --freeform:sudo 0 install -- '
        assert_equal 0 "$PRIMER_RC"
        assert_equal "stdin a b" "$(tr "\n" " " < /tmp/freeform.log | sed "s/ $//")"'
}

test_freeform_failing_script_stops() {
    in_container "$IMG_ALPINE" '
        mkdir -p /tmp/ff/install
        printf "#!/bin/sh\necho one >> /tmp/ff.log\n" > /tmp/ff/install/1.sh
        printf "#!/bin/sh\nexit 3\n" > /tmp/ff/install/2.sh
        printf "#!/bin/sh\necho three >> /tmp/ff.log\n" > /tmp/ff/install/3.sh
        chmod a+x /tmp/ff/install/*.sh
        primer_run -s freeform --freeform:root /tmp/ff install
        assert_false [ "$PRIMER_RC" = 0 ]
        assert_equal one "$(cat /tmp/ff.log)"'
}

test_freeform_missing_directory() {
    in_container "$IMG_ALPINE" '
        mkdir -p /tmp/ff/install
        primer_run -s freeform --freeform:root /tmp/ff clean
        assert_equal 0 "$PRIMER_RC"
        assert_contains "No clean directory under /tmp/ff" "$PRIMER_ERR"
        primer_run -s freeform --freeform:root /tmp/nonexisting install
        assert_equal 0 "$PRIMER_RC"'
}

# Links to executable files run, links to directories are skipped.
test_freeform_runs_symlinks() {
    in_container "$IMG_ALPINE" '
        mkdir -p /tmp/ff/install /tmp/scripts/dir
        printf "#!/bin/sh\necho linked >> /tmp/ff.log\n" > /tmp/scripts/linked.sh
        printf "#!/bin/sh\necho plain >> /tmp/ff.log\n" > /tmp/ff/install/1.sh
        chmod a+x /tmp/scripts/linked.sh /tmp/ff/install/1.sh
        ln -s /tmp/scripts/linked.sh /tmp/ff/install/2.sh
        ln -s /tmp/scripts/dir /tmp/ff/install/3.sh
        primer_run -s freeform --freeform:root /tmp/ff install
        assert_equal 0 "$PRIMER_RC"
        assert_equal "plain linked" "$(tr "\n" " " < /tmp/ff.log | sed "s/ $//")"'
}
