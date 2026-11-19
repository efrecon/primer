#!/bin/sh
# shellcheck disable=SC2016

# Tests of the machinery step: Tcl dependencies and a clone of the machinery
# repository, linked into the binaries directory.

test_machinery_install_debian() {
    in_container "$IMG_TRIXIE" '
        primer_run -s machinery install
        assert_equal 0 "$PRIMER_RC"
        assert_true test -L /usr/local/bin/machinery
        assert_equal /usr/local/opt/machinery/master/machinery "$(readlink /usr/local/bin/machinery)"
        assert_true test -d /usr/local/opt/machinery/master/.git
        assert_true command -v tclsh
        primer_run -s machinery clean
        assert_equal 0 "$PRIMER_RC"
        assert_false test -e /usr/local/bin/machinery
        assert_false test -L /usr/local/bin/machinery
        assert_false test -e /usr/local/opt/machinery/master'
}

test_machinery_install_alpine() {
    in_container "$IMG_ALPINE" '
        primer_run -s machinery install
        assert_equal 0 "$PRIMER_RC"
        assert_true test -L /usr/local/bin/machinery
        assert_true test -d /usr/local/opt/machinery/master/.git
        assert_true apk info -e tcl-lib'
}

# A dangling link left behind must not prevent installation.
test_machinery_dangling_link() {
    in_container "$IMG_TRIXIE" '
        mkdir -p /usr/local/bin
        ln -s /nonexistent/machinery /usr/local/bin/machinery
        primer_run -s machinery install
        assert_equal 0 "$PRIMER_RC"
        assert_equal /usr/local/opt/machinery/master/machinery "$(readlink /usr/local/bin/machinery)"'
}
