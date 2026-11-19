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

# Cleaning a branch never removes the link to another one. No network.
test_machinery_clean_other_branch() {
    in_container "$IMG_ALPINE" '
        mkdir -p /usr/local/opt/machinery/master /usr/local/bin
        printf "#!/bin/sh\n" > /usr/local/opt/machinery/master/machinery
        chmod a+x /usr/local/opt/machinery/master/machinery
        ln -s /usr/local/opt/machinery/master/machinery /usr/local/bin/machinery
        primer_run -s machinery --machinery:branch dev clean
        assert_equal 0 "$PRIMER_RC"
        assert_equal /usr/local/opt/machinery/master/machinery "$(readlink /usr/local/bin/machinery)"
        assert_true [ -x /usr/local/opt/machinery/master/machinery ]
        primer_run -s machinery clean
        assert_false [ -L /usr/local/bin/machinery ]
        assert_false [ -e /usr/local/opt/machinery ]'
}

# Branches coexist: installing another one clones it and points the link to it.
test_machinery_second_branch() {
    in_container "$IMG_ALPINE" '
        mkdir -p /usr/local/opt/machinery/master/.git /usr/local/bin
        printf "#!/bin/sh\n" > /usr/local/opt/machinery/master/machinery
        chmod a+x /usr/local/opt/machinery/master/machinery
        ln -s /usr/local/opt/machinery/master/machinery /usr/local/bin/machinery
        # A fake repository with a dev branch, so no network is needed.
        apk add -q git >/dev/null
        git init -q -b dev /tmp/repo
        printf "#!/bin/sh\necho 1.0\n" > /tmp/repo/machinery
        git -C /tmp/repo add machinery
        git -C /tmp/repo -c user.name=t -c user.email=t@t commit -qm init
        unit_load
        unit_step machinery
        primer_os_packages() { :; }
        PRIMER_STEP_MACHINERY_REPO=/tmp/repo
        primer_step_machinery option --branch dev
        run primer_step_machinery install
        assert_equal 0 "$RUN_RC"
        assert_equal /usr/local/opt/machinery/dev/machinery "$(readlink /usr/local/bin/machinery)"
        assert_true [ -x /usr/local/opt/machinery/master/machinery ]'
}
