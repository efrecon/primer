#!/bin/sh

# Snippets in single quotes are expanded in the containers, not here.
# shellcheck disable=SC2016

# Tests for the users step, using the database at test/data/users.db. The import
# of SSH keys from GitHub is not checked: it depends on the network and on the
# GitHub API rate limits.

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
    # No shell in the DB: the shell of the caller (root)
    assert_equal "$(getent passwd root | cut -d: -f7)" "$(getent passwd emmanuel | cut -d: -f7)"
    assert_true [ -d /home/emmanuel ]
'

test_users_db_alpine() {
    primer_in "$IMG_ALPINE" -s users --users:db /primer/test/data/users.db install -- "$_users_db_verify"
}

test_users_db_debian() {
    primer_in "$IMG_TRIXIE" -s users --users:db /primer/test/data/users.db install -- "$_users_db_verify"
}

# Generated passwords are saved next to the database when asked to, the file is
# private, and the password is actually set.
test_users_save_passwords() {
    in_container "$IMG_TRIXIE" '
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

test_users_extra_groups() {
    in_container "$IMG_ALPINE" '
        primer_run -s users --users:db /primer/test/data/users.db --users:groups "extra1,extra2" install
        assert_equal 0 "$PRIMER_RC"
        assert_match "(^| )extra1( |$)" "$(id -Gn manu)"
        assert_match "(^| )extra2( |$)" "$(id -Gn emmanuel)"
        assert_match "(^| )extra1( |$)" "$(id -Gn root)"'
}

# A second run modifies existing users rather than failing.
test_users_rerun() {
    in_container "$IMG_TRIXIE" '
        primer_run -s users --users:db /primer/test/data/users.db install
        assert_equal 0 "$PRIMER_RC"
        primer_run -s users --users:db /primer/test/data/users.db install
        assert_equal 0 "$PRIMER_RC"
        assert_equal 1 "$(getent passwd | grep -c "^manu:")"'
}

test_users_clean_alpine() {
    in_container "$IMG_ALPINE" '
        primer_run -s users --users:db /primer/test/data/users.db install
        primer_run -s users --users:db /primer/test/data/users.db clean
        assert_equal 0 "$PRIMER_RC"
        assert_false getent passwd emmanuel
        assert_false getent passwd manu'
}

test_users_clean_debian() {
    in_container "$IMG_TRIXIE" '
        primer_run -s users --users:db /primer/test/data/users.db install
        primer_run -s users --users:db /primer/test/data/users.db clean
        assert_equal 0 "$PRIMER_RC"
        assert_false getent passwd emmanuel
        assert_false getent passwd manu'
}

test_users_no_db() {
    primer_in "$IMG_ALPINE" -v warn -s users install -- '
        assert_equal 0 "$PRIMER_RC"
        assert_contains "No user database provided" "$PRIMER_ERR"'
}
