#!/bin/sh

# Snippets are single-quoted on purpose: they are expanded in containers.
# shellcheck disable=SC2016

# Unit tests for libexec/auth.sh. Alpine uses busybox adduser/addgroup without
# usermod, Debian uses the shadow tools (useradd, usermod) and /etc/login.defs.

# Snippet creating regular users alice and bob on Alpine (busybox).
_AUTH_USERS_ALPINE='adduser -D alice; adduser -D bob'
# Same on Debian (shadow).
_AUTH_USERS_DEBIAN='useradd -m alice; useradd -m bob'

test_primer_auth_user_list_alpine() {
    unit "$IMG_ALPINE" "$_AUTH_USERS_ALPINE"'
        assert_false test -f /etc/login.defs
        users=$(primer_auth_user_list)
        assert_equal "alice
bob" "$users"
        all=$(primer_auth_user_list --all)
        assert_match "^root$" "$all"
        assert_match "^nobody$" "$all"
        assert_match "^alice$" "$(primer_auth_user_list -a)"'
}

test_primer_auth_user_list_debian() {
    unit "$IMG_TRIXIE" "$_AUTH_USERS_DEBIAN"'
        assert_true test -f /etc/login.defs
        assert_equal "alice
bob" "$(primer_auth_user_list)"
        assert_match "^root$" "$(primer_auth_user_list -a)"'
}

test__primer_auth_getent_passwd() {
    unit "$IMG_ALPINE" "$_AUTH_USERS_ALPINE"'
        assert_equal root "$(_primer_auth_getent_passwd 0 0)"
        alice=$(id -u alice)
        assert_equal alice "$(_primer_auth_getent_passwd "$alice" "$alice")"
        assert_equal "" "$(_primer_auth_getent_passwd 50000 50001)"'
}

test_primer_auth_group_add_alpine() {
    unit "$IMG_ALPINE" '
        primer_auth_group_add devs
        assert_match "^devs:" "$(getent group devs)"
        primer_auth_group_add devs
        assert_equal 1 "$(getent group | grep -c "^devs:")"
        primer_auth_group_add ""
        primer_auth_group_add'
}

test_primer_auth_group_add_debian() {
    unit "$IMG_TRIXIE" '
        primer_auth_group_add devs
        assert_match "^devs:" "$(getent group devs)"
        primer_auth_group_add devs
        assert_equal 1 "$(getent group | grep -c "^devs:")"'
}

# Membership must be an exact group match: being in dockerx does not make a
# user member of docker.
test_primer_auth_group_membership_alpine() {
    unit "$IMG_ALPINE" "$_AUTH_USERS_ALPINE"'
        addgroup dockerx; addgroup docker
        primer_auth_group_membership alice dockerx
        assert_match "(^| )dockerx( |$)" "$(id -Gn alice)"
        primer_auth_group_membership alice docker
        assert_match "(^| )docker( |$)" "$(id -Gn alice)"
        primer_auth_group_membership alice docker
        assert_equal 1 "$(id -Gn alice | tr " " "\n" | grep -cx docker)"
        primer_auth_group_membership alice'
}

test_primer_auth_group_membership_debian() {
    unit "$IMG_TRIXIE" "$_AUTH_USERS_DEBIAN"'
        groupadd dockerx; groupadd docker
        primer_auth_group_membership alice dockerx
        primer_auth_group_membership alice docker
        assert_match "(^| )docker( |$)" "$(id -Gn alice)"
        assert_match "(^| )dockerx( |$)" "$(id -Gn alice)"'
}

test__primer_auth_valid_shell() {
    unit "$IMG_ALPINE" '
        assert_true _primer_auth_valid_shell /bin/sh
        assert_false _primer_auth_valid_shell /bin/s
        assert_false _primer_auth_valid_shell sh
        assert_false _primer_auth_valid_shell /nonexistent
        rm -f /etc/shells
        assert_false _primer_auth_valid_shell /bin/sh'
}

# Verification snippet for jane, created with all options.
_AUTH_JANE='
    entry=$(getent passwd jane)
    assert_equal "Jane Doe" "$(echo "$entry" | cut -d: -f5)"
    assert_equal /bin/sh "$(echo "$entry" | cut -d: -f7)"
    assert_equal devs "$(id -gn jane)"
    assert_true test -d /home/jane
    assert_match "^\\$" "$(grep "^jane:" /etc/shadow | cut -d: -f2)" "password hash"
'

test_primer_auth_user_add_alpine() {
    unit "$IMG_ALPINE" '
        primer_auth_user_add jane --group devs --gecos "Jane Doe" --shell /bin/sh --password s3cr3t
        '"$_AUTH_JANE"'
        # Defaults: group named after the user, shell of the caller, no password
        primer_auth_user_add bob
        assert_equal bob "$(id -gn bob)"
        assert_equal "$(getent passwd root | cut -d: -f7)" "$(getent passwd bob | cut -d: -f7)"
        assert_false grep -q "^bob:\\$" /etc/shadow
        # Invalid shell
        assert_exit 1 primer_auth_user_add eve --shell /bin/nope
        assert_equal "" "$(getent passwd eve || true)"'
}

test_primer_auth_user_add_debian() {
    unit "$IMG_TRIXIE" '
        primer_auth_user_add jane --group devs --gecos "Jane Doe" --shell /bin/sh --password s3cr3t
        '"$_AUTH_JANE"'
        primer_auth_user_add bob
        assert_equal bob "$(id -gn bob)"
        assert_equal /bin/bash "$(getent passwd bob | cut -d: -f7)"
        assert_exit 1 primer_auth_user_add eve --shell /bin/nope'
}

test_primer_auth_user_password_alpine() {
    unit "$IMG_ALPINE" "$_AUTH_USERS_ALPINE"'
        before=$(grep "^alice:" /etc/shadow | cut -d: -f2)
        primer_auth_user_password alice ""
        assert_equal "$before" "$(grep "^alice:" /etc/shadow | cut -d: -f2)"
        primer_auth_user_password alice "n3w p4ss"
        after=$(grep "^alice:" /etc/shadow | cut -d: -f2)
        assert_match "^\\$" "$after"
        primer_auth_user_password alice other
        assert_true test "$after" != "$(grep "^alice:" /etc/shadow | cut -d: -f2)"'
}

test_primer_auth_user_password_debian() {
    unit "$IMG_TRIXIE" "$_AUTH_USERS_DEBIAN"'
        primer_auth_user_password alice "n3w p4ss"
        assert_match "^\\$" "$(grep "^alice:" /etc/shadow | cut -d: -f2)"'
}

# Snippet modifying alice and checking the result, the mode of /etc/passwd
# must not change.
_AUTH_MOD='
    mode=$(stat -c "%a %U %G" /etc/passwd)
    primer_auth_user_mod alice --gecos "Alice Liddell" --shell /bin/sh --group wonder
    entry=$(getent passwd alice)
    assert_equal "Alice Liddell" "$(echo "$entry" | cut -d: -f5)"
    assert_equal /bin/sh "$(echo "$entry" | cut -d: -f7)"
    assert_equal wonder "$(id -gn alice)"
    assert_equal "$mode" "$(stat -c "%a %U %G" /etc/passwd)"
    # Options default to current settings
    primer_auth_user_mod alice --gecos "Alice"
    assert_equal wonder "$(id -gn alice)"
    assert_equal /bin/sh "$(getent passwd alice | cut -d: -f7)"
    # Other users are untouched
    assert_equal "$bob" "$(getent passwd bob)"
    # Errors
    assert_exit 1 primer_auth_user_mod alice --shell /bin/nope
    assert_exit 1 primer_auth_user_mod nosuchuser --shell /bin/sh
    # Password
    primer_auth_user_mod alice --password s3cr3t
    assert_match "^\\$" "$(grep "^alice:" /etc/shadow | cut -d: -f2)"
'

test_primer_auth_user_mod_alpine() {
    unit "$IMG_ALPINE" "$_AUTH_USERS_ALPINE"'
        sed -i "s|^alice:\(.*\):/bin/sh$|alice:\1:/bin/ash|" /etc/passwd
        bob=$(getent passwd bob)
        assert_false command -v usermod
        '"$_AUTH_MOD"
}

test_primer_auth_user_mod_debian() {
    unit "$IMG_TRIXIE" "$_AUTH_USERS_DEBIAN"'
        bob=$(getent passwd bob)
        '"$_AUTH_MOD"
}
