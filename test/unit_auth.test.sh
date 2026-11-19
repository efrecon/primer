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

test__primer_auth_valid_gecos() {
    unit "$IMG_ALPINE" '
        assert_true _primer_auth_valid_gecos ""
        assert_true _primer_auth_valid_gecos "Jane Doe,Room 1,+46 123"
        assert_false _primer_auth_valid_gecos "Jane:Doe"
        assert_false _primer_auth_valid_gecos "Jane
Doe"
        assert_exit 1 primer_auth_user_add jane --gecos "Jane:Doe"
        assert_equal "" "$(getent passwd jane)"'
}

# Default login shells, as verified on the distributions: /bin/sh on Alpine
# (busybox adduser, root), /bin/bash on Debian (adduser, installer), the
# default of useradd elsewhere, e.g. /bin/bash on Fedora.
test__primer_auth_default_shell_alpine() {
    unit "$IMG_ALPINE" '
        assert_equal /bin/sh "$(_primer_auth_default_shell)"
        # The useradd of shadow (default /bin/ash) is ignored on Alpine...
        useradd() { [ "$1" = "-D" ] && printf "GROUP=100\nSHELL=%s\nSKEL=/etc/skel\n" "$USERADD_SHELL"; }
        USERADD_SHELL=/bin/ash
        assert_equal /bin/sh "$(_primer_auth_default_shell)" "shadow on Alpine"
        # ...but used elsewhere, when valid
        primer_os_distribution() { echo fedora; }
        assert_equal /bin/ash "$(_primer_auth_default_shell)"
        USERADD_SHELL=/bin/nope
        assert_equal /bin/sh "$(_primer_auth_default_shell)" "invalid useradd default"
        unset -f useradd
        assert_equal /bin/sh "$(_primer_auth_default_shell)" "no useradd"'
}

test__primer_auth_default_shell_debian() {
    unit "$IMG_TRIXIE" '
        assert_false [ -f /etc/adduser.conf ]
        assert_equal /bin/bash "$(_primer_auth_default_shell)"
        echo "#DSHELL=/usr/bin/dash" > /etc/adduser.conf
        assert_equal /bin/bash "$(_primer_auth_default_shell)" "commented"
        echo "DSHELL=/usr/bin/dash" > /etc/adduser.conf
        assert_equal /usr/bin/dash "$(_primer_auth_default_shell)"
        echo "DSHELL = \"/bin/sh\"  # quoted" > /etc/adduser.conf
        assert_equal /bin/sh "$(_primer_auth_default_shell)" "quoted"
        echo "DSHELL=/bin/dash" > /etc/adduser.conf
        assert_equal /bin/sh "$(_primer_auth_default_shell)" "not in /etc/shells"'
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
        # Defaults: group named after the user, shell of the platform, no
        # password
        primer_auth_user_add bob
        assert_equal bob "$(id -gn bob)"
        assert_equal /bin/sh "$(getent passwd bob | cut -d: -f7)"
        primer_auth_user_add carol --shell ""
        assert_equal /bin/sh "$(getent passwd carol | cut -d: -f7)"
        assert_false grep -q "^bob:\\$" /etc/shadow
        # Invalid shell
        assert_exit 1 primer_auth_user_add eve --shell /bin/nope
        assert_equal "" "$(getent passwd eve || true)"'
}

test_primer_auth_user_add_debian() {
    unit "$IMG_TRIXIE" '
        primer_auth_user_add jane --group devs --gecos "Jane Doe" --shell /bin/sh --password s3cr3t
        '"$_AUTH_JANE"'
        # Default shell of the platform, not the one of useradd (/bin/sh)
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
    root=$(grep "^root:" /etc/shadow)
    primer_auth_user_mod alice --gecos "Alice Liddell" --shell /bin/sh --group wonder
    entry=$(getent passwd alice)
    assert_equal "Alice Liddell" "$(echo "$entry" | cut -d: -f5)"
    assert_equal /bin/sh "$(echo "$entry" | cut -d: -f7)"
    assert_equal wonder "$(id -gn alice)"
    assert_equal "$mode" "$(stat -c "%a %U %G" /etc/passwd)"
    # Options default to current settings, empty values keep them
    primer_auth_user_mod alice --gecos "Alice" --shell ""
    assert_equal wonder "$(id -gn alice)"
    assert_equal /bin/sh "$(getent passwd alice | cut -d: -f7)"
    primer_auth_user_mod alice --group "" --gecos "" --shell ""
    assert_equal wonder "$(id -gn alice)"
    assert_equal Alice "$(getent passwd alice | cut -d: -f5)"
    # Backslashes are kept as-is
    primer_auth_user_mod alice --gecos "Dr\\tAlice"
    assert_equal "Dr\\tAlice" "$(getent passwd alice | cut -d: -f5)"
    # Other users are untouched
    assert_equal "$bob" "$(getent passwd bob)"
    assert_equal "$mode" "$(stat -c "%a %U %G" /etc/passwd)"
    # Errors
    assert_exit 1 primer_auth_user_mod alice --gecos "Alice:Liddell"
    assert_equal "Dr\\tAlice" "$(getent passwd alice | cut -d: -f5)"
    assert_exit 1 primer_auth_user_mod alice --shell /bin/nope
    assert_exit 1 primer_auth_user_mod nosuchuser --shell /bin/sh
    # Password
    primer_auth_user_mod alice --password s3cr3t
    assert_match "^\\$" "$(grep "^alice:" /etc/shadow | cut -d: -f2)"
    assert_equal "$root" "$(grep "^root:" /etc/shadow)" "root password untouched"
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

# The busybox path rewrites /etc/passwd: it must refuse to write when the
# group cannot be resolved, and only touch the exact user. Passes now.
test_primer_auth_user_mod_alpine_guards() {
    unit "$IMG_ALPINE" 'adduser -D al; adduser -D alice
        before=$(cat /etc/passwd)
        alice=$(getent passwd alice)
        # Group creation silently does nothing: no gid, no change
        addgroup() { :; }
        assert_exit 1 primer_auth_user_mod al --group ghost
        assert_equal "$before" "$(cat /etc/passwd)" "passwd untouched"
        unset -f addgroup
        # A user named as a prefix of another one
        primer_auth_user_mod al --gecos "Al"
        assert_equal Al "$(getent passwd al | cut -d: -f5)"
        assert_equal "$alice" "$(getent passwd alice)"
        assert_equal "$(printf "%s\n" "$before" | wc -l)" "$(wc -l < /etc/passwd)"'
}

# login.defs without UID_MIN/UID_MAX (they are optional): use the defaults.
# FAILS NOW: the list is empty.
test_primer_auth_user_list_logindefs() {
    unit "$IMG_ALPINE" "$_AUTH_USERS_ALPINE"'
        printf "PASS_MAX_DAYS 99999\n" > /etc/login.defs
        run primer_auth_user_list
        assert_equal "alice
bob" "$RUN_OUT"
        assert_equal "" "$RUN_ERR"'
}
