#!/bin/sh

# Snippets in single quotes are expanded in the containers, not here.
# shellcheck disable=SC2016

# Tests for the users step, using the database at test/data/users.db. The GitHub
# API is replaced by files (PRIMER_STEP_USERS_GHAPI=file:///tmp/gh/), so tests
# do not depend on the network, nor on the rate limits of the API: users
# without files under /tmp/gh get no key.

# Verification of the users and groups described in test/data/users.db
_users_db_verify='
    assert_equal 0 "$PRIMER_RC"
    assert_true getent group primer
    assert_true getent group bummer
    assert_true getent passwd emmanuel
    assert_true getent passwd manu
    assert_equal primer "$(id -gn emmanuel)"
    assert_match "(^| )bummer( |$)" "$(id -Gn emmanuel)"
    assert_equal primer "$(id -gn manu)"
    assert_not_contains bummer "$(id -Gn manu)"
    assert_equal /bin/sh "$(getent passwd manu | cut -d: -f7)"
    assert_equal "Leunamme Nocerf,Super Vilain,+46457678," "$(getent passwd manu | cut -d: -f5)"
    assert_match "^Emmanuel Frecon" "$(getent passwd emmanuel | cut -d: -f5)"
    # No shell in the DB: the default login shell of the platform
    case "$(. /etc/os-release && echo "$ID")" in
        debian|ubuntu|fedora) assert_equal /bin/bash "$(getent passwd emmanuel | cut -d: -f7)";;
        *) assert_equal /bin/sh "$(getent passwd emmanuel | cut -d: -f7)";;
    esac
    assert_true [ -d /home/emmanuel ]
'

test_users_db_alpine() {
    primer_in -e PRIMER_STEP_USERS_GHAPI=file:///tmp/gh/ "$IMG_ALPINE" -s users --users:db /primer/test/data/users.db install -- "$_users_db_verify"
}

# Existing users without a shell in the DB keep their shell.
test_users_db_keeps_shell() {
    in_container -e PRIMER_STEP_USERS_GHAPI=file:///tmp/gh/ "$IMG_ALPINE" '
        primer_run -s users --users:db /primer/test/data/users.db install
        assert_equal 0 "$PRIMER_RC" "first install"
        sed -i "s|^\(emmanuel:.*\):[^:]*$|\1:/bin/ash|" /etc/passwd
        assert_equal /bin/ash "$(getent passwd emmanuel | cut -d: -f7)"
        primer_run -s users --users:db /primer/test/data/users.db install
        assert_equal 0 "$PRIMER_RC" "second install"
        assert_equal /bin/ash "$(getent passwd emmanuel | cut -d: -f7)"'
}

test_users_db_debian() {
    primer_in -e PRIMER_STEP_USERS_GHAPI=file:///tmp/gh/ "$IMG_TRIXIE" -s users --users:db /primer/test/data/users.db install -- "$_users_db_verify"
}

test_users_db_ubuntu() {
    primer_in -e PRIMER_STEP_USERS_GHAPI=file:///tmp/gh/ "$IMG_UBUNTU" -s users --users:db /primer/test/data/users.db install -- "$_users_db_verify"
}

# Fedora: shadow tools, and passwords set although cracklib complains.
test_users_db_fedora() {
    primer_in -e PRIMER_STEP_USERS_GHAPI=file:///tmp/gh/ "$IMG_FEDORA" -s users --users:db /primer/test/data/users.db install -- "$_users_db_verify"'
    assert_match "^\\$" "$(getent shadow emmanuel | cut -d: -f2)" "password set"'
}

# Generated passwords are saved next to the database when asked to, the file is
# private, and the password is actually set.
test_users_save_passwords() {
    in_container -e PRIMER_STEP_USERS_GHAPI=file:///tmp/gh/ "$IMG_TRIXIE" '
        primer_run -s users --users:db /primer/test/data/users.db --users:save 1 install
        assert_equal 0 "$PRIMER_RC"
        assert_true [ -f /primer/test/data/users.pwd ]
        assert_equal -rw------- "$(stat -c %A /primer/test/data/users.pwd)"
        assert_equal 2 "$(wc -l < /primer/test/data/users.pwd | tr -d " ")"
        pw=$(grep "^emmanuel:" /primer/test/data/users.pwd | cut -d: -f2)
        assert_match "^.{12}$" "$pw"
        hash=$(getent shadow emmanuel | cut -d: -f2)
        assert_match "^\\$" "$hash" "password hash set"'
}

# The password store is private from the start: an abort (here, an invalid
# shell) does not leave passwords readable by others.
test_users_save_passwords_private() {
    in_container -e PRIMER_STEP_USERS_GHAPI=file:///tmp/gh/ "$IMG_ALPINE" '
        umask 022
        printf "anna:x:::\nbert:x:::/bin/nope\n" > /tmp/u.db
        primer_run -s users --users:db /tmp/u.db --users:save 1 install
        assert_false [ "$PRIMER_RC" = 0 ]
        assert_true grep -q "^anna:" /tmp/u.pwd
        assert_equal -rw------- "$(stat -c %A /tmp/u.pwd)"'
}

# Lines with empty fields, explicit or empty passwords work, also when run
# again: empty fields keep the current settings of existing users.
test_users_empty_fields() {
    in_container -e PRIMER_STEP_USERS_GHAPI=file:///tmp/gh/ "$IMG_ALPINE" '
        printf "carol:x:::\ndave:pass1234:staff:Dave:\nerin::::\n" > /tmp/u.db
        primer_run -s users --users:db /tmp/u.db install
        assert_equal 0 "$PRIMER_RC" "first install"
        assert_contains "Creating user dave with password from /tmp/u.db" "$PRIMER_ERR"
        assert_contains "Creating user erin without password" "$PRIMER_ERR"
        assert_equal staff "$(id -gn dave)"
        assert_equal Dave "$(getent passwd dave | cut -d: -f5)"
        sed -i "s|^carol:\([^:]*:[^:]*:[^:]*:\)[^:]*:|carol:\1Carol C:|" /etc/passwd
        primer_run -s users --users:db /tmp/u.db install
        assert_equal 0 "$PRIMER_RC" "second install"
        assert_equal carol "$(id -gn carol)"
        assert_equal "Carol C" "$(getent passwd carol | cut -d: -f5)" "GECOS kept"'
}

test_users_extra_groups() {
    in_container -e PRIMER_STEP_USERS_GHAPI=file:///tmp/gh/ "$IMG_ALPINE" '
        primer_run -s users --users:db /primer/test/data/users.db --users:groups "extra1,extra2" install
        assert_equal 0 "$PRIMER_RC"
        assert_match "(^| )extra1( |$)" "$(id -Gn manu)"
        assert_match "(^| )extra2( |$)" "$(id -Gn emmanuel)"
        assert_match "(^| )extra1( |$)" "$(id -Gn root)"'
}

# A second run modifies existing users rather than failing.
test_users_rerun() {
    in_container -e PRIMER_STEP_USERS_GHAPI=file:///tmp/gh/ "$IMG_TRIXIE" '
        primer_run -s users --users:db /primer/test/data/users.db install
        assert_equal 0 "$PRIMER_RC"
        primer_run -s users --users:db /primer/test/data/users.db install
        assert_equal 0 "$PRIMER_RC"
        assert_equal 1 "$(getent passwd | grep -c "^manu:")"'
}

test_users_clean_alpine() {
    in_container -e PRIMER_STEP_USERS_GHAPI=file:///tmp/gh/ "$IMG_ALPINE" '
        primer_run -s users --users:db /primer/test/data/users.db install
        primer_run -s users --users:db /primer/test/data/users.db clean
        assert_equal 0 "$PRIMER_RC"
        assert_false getent passwd emmanuel
        assert_false getent passwd manu'
}

test_users_clean_debian() {
    in_container -e PRIMER_STEP_USERS_GHAPI=file:///tmp/gh/ "$IMG_TRIXIE" '
        primer_run -s users --users:db /primer/test/data/users.db install
        primer_run -s users --users:db /primer/test/data/users.db clean
        assert_equal 0 "$PRIMER_RC"
        assert_false getent passwd emmanuel
        assert_false getent passwd manu'
}

test_users_no_db() {
    primer_in -e PRIMER_STEP_USERS_GHAPI=file:///tmp/gh/ "$IMG_ALPINE" -v warn -s users install -- '
        assert_equal 0 "$PRIMER_RC"
        assert_contains "No user database provided" "$PRIMER_ERR"'
}

# Clean never removes the calling user, even when listed.
test_users_clean_keeps_calling_user() {
    in_container -e PRIMER_STEP_USERS_GHAPI=file:///tmp/gh/ "$IMG_ALPINE" '
        printf "root::::\nanna::::\n" > /tmp/u.db
        primer_run -s users --users:db /tmp/u.db install
        assert_equal 0 "$PRIMER_RC" "install"
        primer_run -s users --users:db /tmp/u.db clean
        assert_equal 0 "$PRIMER_RC" "clean"
        assert_true getent passwd root
        assert_false getent passwd anna'
}

# $1 user, $2 cleartext password: does the shadow hash match? (busybox cryptpw)
_users_pw_matches='
_pw_matches() {
    _h=$(getent shadow "$1" | cut -d: -f2)
    _s=$(printf %s "$_h" | cut -d"\$" -f3)
    [ "$_h" = "$(cryptpw -m sha512 -S "$_s" "$2")" ]
}
'

# Generated and database passwords really work, passwords of existing users
# never change, and the store is stable.
test_users_passwords_are_set() {
    in_container -e PRIMER_STEP_USERS_GHAPI=file:///tmp/gh/ "$IMG_ALPINE" "$_users_pw_matches"'
        printf "anna:x:::\ndave:pass1234:::\n" > /tmp/u.db
        primer_run -s users --users:db /tmp/u.db --users:save 1 install
        assert_equal 0 "$PRIMER_RC"
        pw=$(grep "^anna:" /tmp/u.pwd | cut -d: -f2)
        assert_true _pw_matches anna "$pw"
        assert_true _pw_matches dave pass1234
        before=$(getent shadow anna dave | cut -d: -f1,2)
        printf "anna:x:::\ndave:changed99:::\n" > /tmp/u.db
        primer_run -s users --users:db /tmp/u.db --users:save 1 install
        assert_equal 0 "$PRIMER_RC" "second install"
        assert_equal "$before" "$(getent shadow anna dave | cut -d: -f1,2)" "passwords of existing users unchanged"
        assert_equal "$pw" "$(grep "^anna:" /tmp/u.pwd | cut -d: -f2)" "store kept"
        assert_equal 1 "$(grep -c "^anna:" /tmp/u.pwd)"'
}

# The password store sits next to the database, even when a directory has a
# dot and the database no extension.
test_users_password_store_location() {
    in_container -e PRIMER_STEP_USERS_GHAPI=file:///tmp/gh/ "$IMG_ALPINE" '
        mkdir -p /etc/primer.d
        printf "anna:x:::\n" > /etc/primer.d/users
        echo keep > /etc/primer.pwd
        primer_run -s users --users:db /etc/primer.d/users --users:save 1 install
        assert_equal 0 "$PRIMER_RC"
        assert_true grep -q "^anna:" /etc/primer.d/users.pwd
        assert_equal keep "$(cat /etc/primer.pwd)" "unrelated file untouched"
        primer_run -s users --users:db /etc/primer.d/users --users:save 1 clean
        assert_false [ -e /etc/primer.d/users.pwd ]
        assert_equal keep "$(cat /etc/primer.pwd)" "unrelated file not removed"'
}

# SSH keys from GitHub, without network (curl accepts file:// URLs).
test_users_github_keys() {
    in_container -e PRIMER_STEP_USERS_GHAPI=file:///tmp/gh/ "$IMG_ALPINE" '
        mkdir -p /tmp/gh/users/octo
        printf "[\n  {\n    \"id\": 1234,\n    \"key\": \"ssh-ed25519 AAAAkeyone\"\n  },\n  {\n    \"id\": 5678,\n    \"key\": \"ssh-rsa AAAAkeytwo\"\n  }\n]\n" > /tmp/gh/users/octo/keys
        printf "gina:x:staff::/bin/sh:octo\n" > /tmp/u.db
        primer_run -s users --users:db /tmp/u.db install
        assert_equal 0 "$PRIMER_RC"
        ak=/home/gina/.ssh/authorized_keys
        assert_equal "ssh-ed25519 AAAAkeyone octo@github/1234
ssh-rsa AAAAkeytwo octo@github/5678" "$(cat "$ak")"
        assert_equal "drwx------ gina:staff" "$(stat -c "%A %U:%G" /home/gina/.ssh | sed "s/S/-/")"
        assert_equal "-rw------- gina:staff" "$(stat -c "%A %U:%G" "$ak")"
        echo "ssh-ed25519 AAAAmine me@laptop" >> "$ak"
        primer_run -s users --users:db /tmp/u.db install
        assert_equal 0 "$PRIMER_RC"
        assert_equal 3 "$(wc -l < "$ak" | tr -d " ")" "no duplicates, own key kept"
        assert_true grep -qx "ssh-ed25519 AAAAmine me@laptop" "$ak"'
}
