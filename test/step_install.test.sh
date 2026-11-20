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

# A directory copied into an existing directory: cleaning removes the copy, and
# never the existing directory, even when cleaning twice or before installing.
test_install_directory_clean_keeps_target() {
    in_container "$IMG_ALPINE" '
        mkdir -p /srv/data/sub /opt/keep
        echo hi > /srv/data/sub/f
        echo precious > /opt/keep/file
        spec="/srv/data:/opt"
        primer_run -s install --install:target "$spec" clean
        assert_equal 0 "$PRIMER_RC" "clean before install"
        assert_equal precious "$(cat /opt/keep/file)"
        primer_run -s install --install:target "$spec" install
        assert_equal 0 "$PRIMER_RC" "install status"
        assert_equal hi "$(cat /opt/data/sub/f)"
        primer_run -s install --install:target "$spec" clean
        assert_equal 0 "$PRIMER_RC" "first clean"
        assert_false [ -e /opt/data ]
        primer_run -s install --install:target "$spec" clean
        assert_equal 0 "$PRIMER_RC" "second clean"
        assert_equal precious "$(cat /opt/keep/file)"
        # Same, with a target ending with a slash and an empty target
        rm -rf /opt/keep
        primer_run -s install --install:target "/srv/data:/opt/" install
        primer_run -s install --install:target "/srv/data:/opt/" clean
        primer_run -s install --install:target "/srv/data:/opt/" clean
        primer_run -s install --install:target "/srv/data:/opt" clean
        assert_equal 0 "$PRIMER_RC"
        assert_true [ -d /opt ]'
}

# Copies that were modified after installation are kept.
test_install_directory_clean_keeps_modified_copy() {
    in_container "$IMG_ALPINE" '
        mkdir -p /srv/data /opt/existing
        echo hi > /srv/data/f
        primer_run -s install --install:target "/srv/data:/opt/copy" install
        primer_run -s install --install:target "/srv/data:/opt/existing" install
        assert_true [ -f /opt/copy/f ]
        assert_true [ -f /opt/existing/data/f ]
        echo extra > /opt/copy/added
        echo extra > /opt/existing/data/added
        primer_run -s install --install:target "/srv/data:/opt/copy" clean
        assert_equal 0 "$PRIMER_RC"
        assert_contains "/opt/copy is not a copy of /srv/data" "$PRIMER_ERR"
        assert_true [ -f /opt/copy/added ]
        primer_run -s install --install:target "/srv/data:/opt/existing" clean
        assert_equal 0 "$PRIMER_RC"
        assert_contains "/opt/existing/data is not a copy of /srv/data (anymore)" "$PRIMER_ERR"
        assert_true [ -f /opt/existing/data/added ]'
}

# Downloads replace the target only when they succeed: a failed download keeps
# the existing target as is. Served by a local web server.
test_install_download() {
    in_container "$IMG_ALPINE" '
        apk add -q busybox-extras >/dev/null
        mkdir -p /www && echo "new content" > /www/conf.txt
        httpd -p 127.0.0.1:8080 -h /www
        echo old > /tmp/conf
        chmod 0640 /tmp/conf
        primer_run -s install --install:target "http%3A%2F%2F127.0.0.1%3A8080%2Fmissing.txt:/tmp/conf:::0640" install
        assert_equal 0 "$PRIMER_RC" "failed download status"
        assert_contains "Could not download http://127.0.0.1:8080/missing.txt, /tmp/conf left untouched" "$PRIMER_ERR"
        assert_equal old "$(cat /tmp/conf)" "content after failed download"
        primer_run -s install --install:target "http%3A%2F%2F127.0.0.1%3A8080%2Fconf.txt:/tmp/conf:::0640" install
        assert_equal 0 "$PRIMER_RC" "download status"
        assert_equal "new content" "$(cat /tmp/conf)"
        assert_equal -rw-r----- "$(stat -c %A /tmp/conf)"'
}

# Installing a directory again refreshes the copy, rather than copying the
# directory into it, also when the source has new files.
test_install_directory_reinstall() {
    in_container "$IMG_ALPINE" '
        mkdir -p /src/app/sub && echo a > /src/app/a && echo b > /src/app/sub/b
        primer_run -s install --install:target "/src/app:/opt/app" install
        primer_run -s install --install:target "/src/app:/opt/app" install
        assert_equal 0 "$PRIMER_RC"
        assert_false [ -e /opt/app/app ]
        echo c > /src/app/c
        primer_run -s install --install:target "/src/app:/opt/app" install
        assert_false [ -e /opt/app/app ]
        assert_equal c "$(cat /opt/app/c)"
        assert_equal "./a ./c ./sub ./sub/b" "$(cd /opt/app && find . -mindepth 1 | sort | tr "\n" " " | sed "s/ $//")"
        primer_run -s install --install:target "/src/app:/opt/app" clean
        assert_false [ -e /opt/app ]'
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

# Clean never removes files that existed before: from an empty source (only
# ensured to exist), or not overwritten.
test_install_clean_keeps_preexisting_files() {
    in_container "$IMG_ALPINE" '
        printf "PATH=/usr/bin\nFOO=bar\n" > /etc/environment
        primer_run -s install --install:target ":/etc/environment" install
        assert_equal 0 "$PRIMER_RC"
        primer_run -s install --install:target ":/etc/environment" clean
        assert_equal 0 "$PRIMER_RC"
        assert_true grep -qx FOO=bar /etc/environment
        primer_run -s install --install:target ":/tmp/created" install
        primer_run -s install --install:target ":/tmp/created" clean
        assert_false [ -e /tmp/created ]
        echo original > /etc/motd.local
        spec="/primer/test/data/users.db:/etc/motd.local"
        primer_run -s install --install:overwrite 0 --install:target "$spec" install
        assert_equal original "$(cat /etc/motd.local)"
        primer_run -s install --install:overwrite 0 --install:target "$spec" clean
        assert_equal 0 "$PRIMER_RC"
        assert_equal original "$(cat /etc/motd.local)" "file not installed is kept"'
}

# Owner and group fields (3 and 4) of specifications.
test_install_owner_group() {
    in_container "$IMG_ALPINE" '
        primer_run -s install \
            --install:target ":/srv/owned/:daemon:daemon:0750" \
            --install:target "/primer/test/data/users.db:/srv/owned/db:daemon::0640" \
            install
        assert_equal 0 "$PRIMER_RC"
        assert_equal daemon:daemon "$(stat -c %U:%G /srv/owned)"
        assert_equal drwxr-x--- "$(stat -c %A /srv/owned)"
        assert_equal daemon:root "$(stat -c %U:%G /srv/owned/db)" "group defaults to the caller"
        assert_equal -rw-r----- "$(stat -c %A /srv/owned/db)"'
}

# Downloaded files are only removed when still equal to a fresh download, and
# kept when the download fails.
test_install_clean_downloads() {
    in_container "$IMG_ALPINE" '
        apk add -q busybox-extras >/dev/null
        mkdir -p /www && echo "served" > /www/conf.txt
        httpd -p 127.0.0.1:8080 -h /www
        spec="http%3A%2F%2F127.0.0.1%3A8080%2Fconf.txt:/tmp/conf"
        primer_run -s install --install:target "$spec" install
        assert_equal served "$(cat /tmp/conf)"
        echo "changed" > /tmp/conf
        primer_run -s install --install:target "$spec" clean
        assert_equal 0 "$PRIMER_RC"
        assert_equal changed "$(cat /tmp/conf)" "changed file kept"
        echo "served" > /tmp/conf
        rm /www/conf.txt
        primer_run -s install --install:target "$spec" clean
        assert_equal 0 "$PRIMER_RC"
        assert_true [ -f /tmp/conf ]
        assert_contains "keeping /tmp/conf" "$PRIMER_ERR"
        echo "served" > /www/conf.txt
        primer_run -s install --install:target "$spec" clean
        assert_false [ -e /tmp/conf ]'
}

# Targets from the environment, installed after the bundle.
test_install_targets_after_bundle() {
    in_container -e "PRIMER_STEP_INSTALL_TARGETS=:/tmp/t1 /tmp/b:/tmp/order" "$IMG_ALPINE" '
        echo bundle > /tmp/a
        echo targets > /tmp/b
        echo "/tmp/a:/tmp/order" > /tmp/bundle
        primer_run -s install --install:bundle /tmp/bundle install
        assert_equal 0 "$PRIMER_RC"
        assert_true [ -f /tmp/t1 ]
        assert_equal targets "$(cat /tmp/order)" "targets after the bundle"'
}
