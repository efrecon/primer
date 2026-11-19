#!/bin/sh

# Snippets in single quotes are expanded in the containers, not here.
# shellcheck disable=SC2016

# Tests for the install step, using the bundle at test/data/copy.bdl.

# Verification of the state after installing test/data/copy.bdl
_install_copy_bdl_verify='
    assert_equal 0 "$PRIMER_RC"
    assert_true [ -d /tmp/test1 ]
    assert_equal drwxrwxrwx "$(stat -c %A /tmp/test1)"
    assert_true [ -f /tmp/test2/empty ]
    assert_false [ -s /tmp/test2/empty ]
    assert_equal -rw-r----- "$(stat -c %A /tmp/test2/empty)"
    assert_equal root:root "$(stat -c %U:%G /tmp/test2/empty)"
'

test_install_bundle_alpine() {
    primer_in "$IMG_ALPINE" -s install --install:bundle /primer/test/data/copy.bdl install -- "$_install_copy_bdl_verify"
}

test_install_bundle_debian() {
    primer_in "$IMG_TRIXIE" -s install --install:bundle /primer/test/data/copy.bdl install -- "$_install_copy_bdl_verify"
}

test_install_bundle_clean() {
    in_container "$IMG_ALPINE" '
        primer_run -s install --install:bundle /primer/test/data/copy.bdl install
        assert_equal 0 "$PRIMER_RC"
        primer_run -s install --install:bundle /primer/test/data/copy.bdl clean
        assert_equal 0 "$PRIMER_RC"
        assert_false [ -e /tmp/test1 ]
        assert_false [ -e /tmp/test2/empty ]'
}

test_install_targets_from_command_line() {
    primer_in "$IMG_ALPINE" -s install \
            --install:target "/primer/test/data/users.db:/tmp/copy.db:::0600" \
            --install:target "/primer/test/data/freeform/install:/tmp/" \
            install -- '
        assert_equal 0 "$PRIMER_RC"
        assert_true cmp /primer/test/data/users.db /tmp/copy.db
        assert_equal -rw------- "$(stat -c %A /tmp/copy.db)"
        assert_true [ -f /tmp/install/10-a.sh ]
        primer_run -s install \
            --install:target "/primer/test/data/users.db:/tmp/copy.db:::0600" \
            --install:target "/primer/test/data/freeform/install:/tmp/" \
            clean
        assert_equal 0 "$PRIMER_RC"
        assert_false [ -e /tmp/copy.db ]
        assert_false [ -e /tmp/install ]
        assert_true [ -d /tmp ]'
}

test_install_no_overwrite() {
    in_container "$IMG_ALPINE" '
        echo original > /tmp/existing
        chmod 0644 /tmp/existing
        primer_run -s install --install:overwrite 0 \
            --install:target "/primer/test/data/users.db:/tmp/existing:::0600" install
        assert_equal 0 "$PRIMER_RC"
        assert_equal original "$(cat /tmp/existing)"
        assert_equal -rw-r--r-- "$(stat -c %A /tmp/existing)"
        primer_run -s install \
            --install:target "/primer/test/data/users.db:/tmp/existing:::0600" install
        assert_equal 0 "$PRIMER_RC"
        assert_true cmp /primer/test/data/users.db /tmp/existing
        assert_equal -rw------- "$(stat -c %A /tmp/existing)"'
}

test_install_urlencoded_paths() {
    primer_in "$IMG_ALPINE" -s install --install:target ":/tmp/with%20space/:::" install -- '
        assert_equal 0 "$PRIMER_RC"
        assert_true [ -d "/tmp/with space" ]'
}

# A directory copied to a path that does not exist becomes that path.
test_install_directory_as_copy() {
    in_container "$IMG_TRIXIE" '
        primer_run -s install --install:target "/primer/test/data/freeform:/opt/ff:::u+rwx,go-rwx" install
        assert_equal 0 "$PRIMER_RC"
        assert_true [ -x /opt/ff/install/10-a.sh ]
        assert_equal drwx------ "$(stat -c %A /opt/ff)"
        assert_equal drwxr-xr-x "$(stat -c %A /opt)"
        primer_run -s install --install:target "/primer/test/data/freeform:/opt/ff" clean
        assert_equal 0 "$PRIMER_RC"
        assert_false [ -e /opt/ff ]
        assert_true [ -d /opt ]'
}

# Permissions only apply to what was copied into an existing directory, and
# cleaning, even twice, never removes that directory.
test_install_into_existing_directory() {
    in_container "$IMG_ALPINE" '
        mkdir -p /srv/data
        chmod 0755 /srv/data
        primer_run -s install --install:target "/primer/test/data/users.db:/srv/data:::0600" install
        assert_equal 0 "$PRIMER_RC"
        assert_equal -rw------- "$(stat -c %A /srv/data/users.db)"
        assert_equal drwxr-xr-x "$(stat -c %A /srv/data)"
        primer_run -s install --install:target "/primer/test/data/users.db:/srv/data" clean
        assert_equal 0 "$PRIMER_RC"
        assert_false [ -e /srv/data/users.db ]
        primer_run -s install --install:target "/primer/test/data/users.db:/srv/data" clean
        assert_equal 0 "$PRIMER_RC"
        assert_true [ -d /srv/data ]'
}

# Specifications without any colon have no destination: they are skipped, and
# the source is left untouched.
test_install_spec_without_destination() {
    in_container "$IMG_ALPINE" '
        cp /primer/test/data/users.db /tmp/source.db
        chmod 0644 /tmp/source.db
        primer_run -v warn -s install --install:target /tmp/source.db install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "No destination in installation specification /tmp/source.db" "$PRIMER_ERR"
        assert_equal -rw-r--r-- "$(stat -c %A /tmp/source.db)"
        primer_run -s install --install:target /tmp/source.db clean
        assert_equal 0 "$PRIMER_RC"
        assert_true [ -f /tmp/source.db ]'
}

# Missing trailing fields get their defaults.
test_install_spec_defaults() {
    in_container "$IMG_ALPINE" '
        primer_run -s install --install:target "/primer/test/data/users.db:/tmp/defaults.db" install
        assert_equal 0 "$PRIMER_RC"
        assert_equal root:root "$(stat -c %U:%G /tmp/defaults.db)"
        assert_equal -rw-r----- "$(stat -c %A /tmp/defaults.db)"'
}
