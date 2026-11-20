#!/bin/sh

# Unit tests for libexec/utils.sh. Each test runs in a fresh container with
# primer sourced in library mode (see unit in test/lib.sh).

# Create a fake step directory layout used by several tests:
# /tmp/a/foo.sh, /tmp/a/foo.txt, /tmp/a/sub/foo.sh, /tmp/b/foo.sh, /tmp/b/bar.sh
# shellcheck disable=SC2016
UTILS_STEPS_FIXTURE='
mkdir -p /tmp/a/sub /tmp/b
echo "FOO_LOADS=\$((\${FOO_LOADS:-0} + 1)); primer_step_foo() { echo foo-a; }" > /tmp/a/foo.sh
echo "primer_step_foo() { echo foo-txt; }" > /tmp/a/foo.txt
echo "primer_step_foo() { echo foo-sub; }" > /tmp/a/sub/foo.sh
echo "primer_step_foo() { echo foo-b; }" > /tmp/b/foo.sh
echo "primer_step_bar() { echo bar-b; }" > /tmp/b/bar.sh
echo "# Does not implement primer_step_empty" > /tmp/b/empty.sh
PRIMER_PATH=/tmp/a:/tmp/b
PRIMER_EXTS=".sh"
'

test_primer_utils_find() {
    unit "$IMG_ALPINE" "$UTILS_STEPS_FIXTURE"'
        # All matches, in path order, never in sub-directories
        assert_equal "/tmp/a/foo.sh
/tmp/b/foo.sh" "$(primer_utils_find foo)"
        assert_equal "/tmp/b/bar.sh" "$(primer_utils_find bar)"
        assert_equal "" "$(primer_utils_find nope)"
        # Several extensions, with or without leading dot
        PRIMER_EXTS=".sh txt"
        assert_equal "/tmp/a/foo.sh
/tmp/a/foo.txt
/tmp/b/foo.sh" "$(primer_utils_find foo)"
        # Trailing slashes in path are handled
        PRIMER_PATH=/tmp/b/
        PRIMER_EXTS=.sh
        assert_equal "/tmp/b/bar.sh" "$(primer_utils_find bar)"'
}

test_primer_utils_locate() {
    unit "$IMG_ALPINE" "$UTILS_STEPS_FIXTURE"'
        assert_equal /tmp/a/foo.sh "$(primer_utils_locate foo)"
        assert_equal /tmp/b/bar.sh "$(primer_utils_locate bar)"
        PRIMER_PATH=/tmp/b:/tmp/a
        assert_equal /tmp/b/foo.sh "$(primer_utils_locate foo)"
        assert_exit 1 primer_utils_locate nope'
}

test_primer_utils_syscmd_exists() {
    unit "$IMG_ALPINE" '
        assert_true primer_utils_syscmd_exists sh
        assert_false primer_utils_syscmd_exists no-such-command
        # Commands from sbin directories are found, even when not in PATH
        PATH=/bin:/usr/bin
        assert_true primer_utils_syscmd_exists apk
        assert_equal /bin:/usr/bin "$PATH"
        # Functions count as commands, which is what makes mocking work.
        my_function() { :; }
        assert_true primer_utils_syscmd_exists my_function'
}

test_primer_utils_var_exists() {
    unit "$IMG_ALPINE" '
        FOO=bar
        EMPTY=
        unset NOPE || true
        assert_true primer_utils_var_exists FOO
        assert_false primer_utils_var_exists EMPTY
        assert_false primer_utils_var_exists NOPE'
}

test_primer_utils_var_value() {
    unit "$IMG_ALPINE" '
        FOO=bar
        SPACED="a b  c"
        QUOTED="it'"'"'s \"quoted\" \$HOME"
        EMPTY=
        unset NOPE || true
        assert_equal bar "$(primer_utils_var_value FOO)"
        assert_equal "a b  c" "$(primer_utils_var_value SPACED)"
        assert_equal "$QUOTED" "$(primer_utils_var_value QUOTED)"
        assert_equal "" "$(primer_utils_var_value EMPTY)"
        # Unset variables are empty, even under set -u (as in primer)
        run primer_utils_var_value NOPE
        assert_equal 0 "$RUN_RC"
        assert_equal "" "$RUN_OUT"'
}

test_primer_utils_load() {
    unit "$IMG_ALPINE" "$UTILS_STEPS_FIXTURE"'
        primer_utils_load foo
        assert_equal 1 "$FOO_LOADS"
        assert_equal foo-a "$(primer_step_foo)"
        assert_equal /tmp/a/foo.sh "$PRIMER_STEP__FOO_PATH"
        # Not loaded again
        primer_utils_load foo
        assert_equal 1 "$FOO_LOADS"
        # Unknown steps are silently ignored
        primer_utils_load nope
        assert_false primer_utils_var_exists PRIMER_STEP__NOPE_PATH'
}

test_primer_utils_origin() {
    unit "$IMG_ALPINE" "$UTILS_STEPS_FIXTURE"'
        primer_utils_load bar
        assert_equal /tmp/b/bar.sh "$(primer_utils_origin bar)"
        assert_equal "" "$(primer_utils_origin nope)"
        # Steps implemented directly in the main script (amalgamation) have
        # the script as their origin.
        cat > /tmp/amalgamation.sh <<"EOF"
PRIMER_ROOT_DIR=/primer
PRIMER_LIBRARY=1
. /primer/primer
primer_step_inline() { :; }
primer_utils_origin inline
EOF
        assert_equal /tmp/amalgamation.sh "$(sh /tmp/amalgamation.sh)"'
}

test__primer_utils_is_function_alpine() {
    unit "$IMG_ALPINE" '
        my_function() { :; }
        assert_true _primer_utils_is_function my_function
        assert_false _primer_utils_is_function ls
        assert_false _primer_utils_is_function no_such_thing'
}

test__primer_utils_is_function_debian() {
    unit "$IMG_TRIXIE" '
        my_function() { :; }
        assert_true _primer_utils_is_function my_function
        assert_false _primer_utils_is_function ls
        assert_false _primer_utils_is_function no_such_thing'
}

test_primer_utils_loadif() {
    unit "$IMG_ALPINE" "$UTILS_STEPS_FIXTURE"'
        primer_utils_loadif bar
        assert_equal bar-b "$(primer_step_bar)"
        # Already implemented: not loaded again
        primer_utils_loadif foo
        primer_utils_loadif foo
        assert_equal 1 "$FOO_LOADS"
        # Missing step, or step file without implementation: abort
        run primer_utils_loadif nope
        assert_equal 1 "$RUN_RC"
        assert_contains "primer_step_nope not implemented" "$RUN_ERR"
        run primer_utils_loadif empty
        assert_equal 1 "$RUN_RC"
        assert_contains "primer_step_empty not implemented" "$RUN_ERR"'
}

test_primer_utils_sysfile_append() {
    unit "$IMG_ALPINE" '
        out=$(printf "a\nb\n" | primer_utils_sysfile_append /tmp/sysfile)
        assert_equal "" "$out"
        printf "c\n" | primer_utils_sysfile_append /tmp/sysfile
        assert_equal "a
b
c" "$(cat /tmp/sysfile)"'
}

# The replacement keeps ownership and access rights, happens through a rename
# (a new inode, so never a truncated file), and leaves no temporary file.
UTILS_REPLACE_TEST='
    mkdir -p /tmp/dir
    printf "old\n" > /tmp/dir/sysfile
    chown nobody /tmp/dir/sysfile
    chmod 604 /tmp/dir/sysfile
    inode=$(stat -c %i /tmp/dir/sysfile)
    printf "new 1\nnew 2\n" | primer_utils_sysfile_replace /tmp/dir/sysfile
    assert_equal "new 1
new 2" "$(cat /tmp/dir/sysfile)"
    assert_equal "604 nobody" "$(stat -c "%a %U" /tmp/dir/sysfile)"
    assert_false [ "$inode" = "$(stat -c %i /tmp/dir/sysfile)" ]
    assert_equal "sysfile" "$(ls -A /tmp/dir)" "no temporary file left"
    # Empty content
    primer_utils_sysfile_replace /tmp/dir/sysfile < /dev/null
    assert_false [ -s /tmp/dir/sysfile ]
    # New files are readable by all
    printf "x\n" | primer_utils_sysfile_replace /tmp/dir/newfile
    assert_equal "x" "$(cat /tmp/dir/newfile)"
    assert_equal "644" "$(stat -c %a /tmp/dir/newfile)"'

test_primer_utils_sysfile_replace_alpine() {
    unit "$IMG_ALPINE" "$UTILS_REPLACE_TEST"
}

test_primer_utils_sysfile_replace_debian() {
    unit "$IMG_TRIXIE" "$UTILS_REPLACE_TEST"
}

# The clip keeps ownership and access rights of the original file, and works
# also when all lines are removed.
UTILS_CLIP_TEST='
    printf "keep 1\nremove me\nkeep 2\nremove too\n" > /tmp/sysfile
    chown nobody /tmp/sysfile
    chmod 640 /tmp/sysfile
    primer_utils_sysfile_clip /tmp/sysfile remove
    assert_equal "keep 1
keep 2" "$(cat /tmp/sysfile)"
    assert_equal "640 nobody" "$(stat -c "%a %U" /tmp/sysfile)"
    primer_utils_sysfile_clip /tmp/sysfile "^keep"
    assert_equal "" "$(cat /tmp/sysfile)"
    assert_equal "640 nobody" "$(stat -c "%a %U" /tmp/sysfile)"
    # Nothing to remove
    printf "line\n" > /tmp/other
    primer_utils_sysfile_clip /tmp/other nothing
    assert_equal line "$(cat /tmp/other)"
    # Missing files are an error
    run primer_utils_sysfile_clip /tmp/missing line
    assert_false [ "$RUN_RC" = 0 ]'

test_primer_utils_sysfile_clip_alpine() {
    unit "$IMG_ALPINE" "$UTILS_CLIP_TEST"
}

test_primer_utils_sysfile_clip_debian() {
    unit "$IMG_TRIXIE" "$UTILS_CLIP_TEST"
}

# Create user bob (and group bob), then exercise all options.
# shellcheck disable=SC2016
UTILS_OWNERSHIP_TEST='
    mkdir -p /tmp/tree/sub
    chmod 755 /tmp/tree /tmp/tree/sub
    touch /tmp/tree/sub/file
    chmod 644 /tmp/tree/sub/file
    chown -R nobody /tmp/tree
    # Default: owned by caller, only accessible by caller
    primer_utils_path_ownership /tmp/tree
    assert_equal "711 root root" "$(stat -c "%a %U %G" /tmp/tree)"
    assert_equal "600 root root" "$(stat -c "%a %U %G" /tmp/tree/sub/file)"
    # User, and implicitly the user main group
    primer_utils_path_ownership /tmp/tree --user bob
    assert_equal "bob bob" "$(stat -c "%U %G" /tmp/tree/sub/file)"
    # User and explicit group
    primer_utils_path_ownership /tmp/tree --user bob --group users
    assert_equal "bob users" "$(stat -c "%U %G" /tmp/tree/sub/file)"
    # Permissions
    primer_utils_path_ownership /tmp/tree --perm 750
    assert_equal "750 root root" "$(stat -c "%a %U %G" /tmp/tree/sub/file)"
    primer_utils_path_ownership /tmp/tree --perm u=rw,g=r,o=
    assert_equal "640" "$(stat -c "%a" /tmp/tree/sub/file)"
    # Everything from a reference file
    touch /tmp/reference
    chown bob:users /tmp/reference
    chmod 604 /tmp/reference
    printf "data\n" > /tmp/target
    primer_utils_path_ownership /tmp/target --as /tmp/reference
    assert_equal "604 bob users" "$(stat -c "%a %U %G" /tmp/target)"
    chmod 2750 /tmp/reference
    primer_utils_path_ownership /tmp/target --as /tmp/reference
    assert_equal "2750 bob users" "$(stat -c "%a %U %G" /tmp/target)"
    # Owners without names
    chown 4242:4343 /tmp/reference
    primer_utils_path_ownership /tmp/target --as /tmp/reference
    assert_equal "4242 4343" "$(stat -c "%u %g" /tmp/target)"
    # Variables of the caller are kept
    _username=caller _group=callers
    primer_utils_path_ownership /tmp/target --as /tmp/reference
    assert_equal "caller callers" "$_username $_group"'

test_primer_utils_path_ownership_alpine() {
    unit "$IMG_ALPINE" 'adduser -D bob'"$UTILS_OWNERSHIP_TEST"
}

test_primer_utils_path_ownership_debian() {
    unit "$IMG_TRIXIE" 'useradd -m -U bob'"$UTILS_OWNERSHIP_TEST"
}

# Replacing a file through a symbolic link updates the target and keeps the
# link. FAILS NOW: the link becomes a regular file with mode 777.
test_primer_utils_sysfile_replace_symlink() {
    unit "$IMG_ALPINE" '
        mkdir -p /tmp/real
        printf "old\n" > /tmp/real/conf
        chmod 640 /tmp/real/conf
        ln -s /tmp/real/conf /tmp/link
        printf "new\n" | primer_utils_sysfile_replace /tmp/link
        assert_true test -L /tmp/link
        assert_equal new "$(cat /tmp/real/conf)"
        assert_equal 640 "$(stat -c %a /tmp/real/conf)"
        assert_equal "" "$(ls -A /tmp /tmp/real | grep -E "^\.(link|conf)\.")" "no temporary file left"'
}

# The system file helpers as a non-root user with real sudo, as on most hosts.
# Needs network (apk add sudo).
test_primer_utils_sysfile_clip_sudo() {
    unit "$IMG_ALPINE" '
        apk add -q sudo >/dev/null
        adduser -D op
        echo "op ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/op
        printf "old\nkeep\n" > /etc/primer.conf
        chmod 640 /etc/primer.conf
        cat > /tmp/as-op.sh <<"EOF"
. /primer/test/lib.sh
unit_load
primer_os_sudo
assert_equal sudo "$PRIMER_OS_SUDO"
printf "new\nkeep\n" | primer_utils_sysfile_replace /etc/primer.conf
printf "more\n" | primer_utils_sysfile_append /etc/primer.conf
primer_utils_sysfile_clip /etc/primer.conf "^new"
EOF
        run su op -s /bin/sh -c "sh /tmp/as-op.sh"
        assert_equal 0 "$RUN_RC" "$RUN_ERR"
        assert_equal "keep
more" "$(cat /etc/primer.conf)"
        assert_equal "640 root root" "$(stat -c "%a %U %G" /etc/primer.conf)"'
}

# Installed binaries belong to root, whoever owned the source, e.g. the uid
# recorded in a tar archive, and are executable by all.
test_primer_utils_install_bin() {
    unit "$IMG_ALPINE" '
        printf "#!/bin/sh\necho hi\n" > /tmp/tool
        chown 1001:127 /tmp/tool
        chmod 700 /tmp/tool
        primer_utils_install_bin /tmp/tool /usr/local/bin/tool
        assert_equal "755 0 0" "$(stat -c "%a %u %g" /usr/local/bin/tool)"
        assert_equal hi "$(/usr/local/bin/tool)"
        assert_false test -e /tmp/tool
        # Into a directory, replacing an existing file
        printf "#!/bin/sh\necho ho\n" > /tmp/tool
        chown 1001:127 /tmp/tool
        primer_utils_install_bin /tmp/tool /usr/local/bin
        assert_equal "755 0 0" "$(stat -c "%a %u %g" /usr/local/bin/tool)"
        assert_equal ho "$(/usr/local/bin/tool)"
        assert_equal "" "$(find /usr/local/bin -name ".tool.*")" "no temporary file left"
        # Missing source: fails, nothing left
        assert_false primer_utils_install_bin /tmp/nope /usr/local/bin/nope
        assert_equal "" "$(find /usr/local/bin -name ".nope.*")"'
}

# As a non-root user with sudo: the binary belongs to root, not to the user.
test_primer_utils_install_bin_sudo() {
    unit "$IMG_ALPINE" '
        apk add -q sudo >/dev/null
        adduser -D op
        echo "op ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/op
        cat > /tmp/as-op.sh <<"EOF"
. /primer/test/lib.sh
unit_load
primer_os_sudo
d=$(mktemp -d)
printf "#!/bin/sh\necho hi\n" > "$d/tool"
primer_utils_install_bin "$d/tool" /usr/local/bin/tool
EOF
        run su op -s /bin/sh -c "sh /tmp/as-op.sh"
        assert_equal 0 "$RUN_RC" "$RUN_ERR"
        assert_equal "755 root root" "$(stat -c "%a %U %G" /usr/local/bin/tool)"'
}
