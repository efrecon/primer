#!/bin/sh

# Snippets in single quotes are expanded in the containers, not here.
# shellcheck disable=SC2016

# Tests for the locale step.

test_locale_install_is_idempotent() {
    in_container "$IMG_ALPINE" '
        printf "FOO=bar\n" > /etc/environment
        primer_run -s locale --locale:locale sv_SE.UTF-8 install
        assert_equal 0 "$PRIMER_RC"
        primer_run -s locale --locale:locale sv_SE.UTF-8 install
        assert_equal 0 "$PRIMER_RC"
        assert_equal 1 "$(grep -cx "LC_ALL=sv_SE.UTF-8" /etc/environment)"
        assert_true grep -qx FOO=bar /etc/environment'
}

test_locale_replaces_previous_locale() {
    in_container "$IMG_ALPINE" '
        primer_run -s locale --locale:locale sv_SE.UTF-8 install
        primer_run -s locale --locale:locale en_GB.UTF-8 install
        assert_equal 0 "$PRIMER_RC"
        assert_equal "LC_ALL=en_GB.UTF-8" "$(grep "^LC_ALL=" /etc/environment)"'
}

test_locale_default() {
    primer_in "$IMG_ALPINE" -s locale install -- '
        assert_equal 0 "$PRIMER_RC"
        assert_true grep -qx "LC_ALL=en_US.UTF-8" /etc/environment'
}

test_locale_clean_keeps_other_lines() {
    in_container "$IMG_ALPINE" '
        printf "FOO=bar\n" > /etc/environment
        chmod 0644 /etc/environment
        primer_run -s locale --locale:locale sv_SE.UTF-8 install
        primer_run -s locale --locale:locale sv_SE.UTF-8 clean
        assert_equal 0 "$PRIMER_RC"
        assert_equal FOO=bar "$(cat /etc/environment)"
        assert_equal -rw-r--r-- "$(stat -c %A /etc/environment)"'
}

# Depends on primer_utils_sysfile_clip coping with removing all lines.
test_locale_clean_only_line() {
    in_container "$IMG_ALPINE" '
        rm -f /etc/environment
        primer_run -s locale --locale:locale sv_SE.UTF-8 install
        primer_run -s locale --locale:locale sv_SE.UTF-8 clean
        assert_equal 0 "$PRIMER_RC"
        assert_false grep -q LC_ALL /etc/environment'
}

test_locale_clean_without_environment() {
    in_container "$IMG_ALPINE" '
        rm -f /etc/environment
        primer_run -s locale clean
        assert_equal 0 "$PRIMER_RC"'
}

# On Debian, the locales package is installed and the locale generated.
test_locale_generated_debian() {
    in_container "$IMG_TRIXIE" '
        primer_run -s locale --locale:locale sv_SE.UTF-8 install
        assert_equal 0 "$PRIMER_RC"
        assert_match "^sv_SE\.utf8$" "$(locale -a)"
        assert_true grep -qx "LC_ALL=sv_SE.UTF-8" /etc/environment
        assert_true grep -q "^sv_SE.UTF-8 UTF-8" /etc/locale.gen
        # Only the requested line is enabled, e.g. not sv_SE ISO-8859-1.
        assert_equal "sv_SE.UTF-8 UTF-8" "$(grep -v "^#" /etc/locale.gen | grep -v "^[[:space:]]*$")"'
}

# On Ubuntu, locale-gen takes the locale.
test_locale_generated_ubuntu() {
    in_container "$IMG_UBUNTU" '
        primer_run -s locale --locale:locale sv_SE.UTF-8 install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "sv_SE.utf8" "$(locale -a)"
        assert_true grep -qx "LC_ALL=sv_SE.UTF-8" /etc/environment'
}

# On Fedora, locales come in one package per language.
test_locale_langpack_fedora() {
    in_container "$IMG_FEDORA" '
        assert_not_contains "sv_SE" "$(locale -a)"
        primer_run -s locale --locale:locale sv_SE.UTF-8 install
        assert_equal 0 "$PRIMER_RC"
        assert_true rpm -q glibc-langpack-sv
        assert_contains "sv_SE.utf8" "$(locale -a)"
        assert_not_contains "cannot change locale" "$PRIMER_ERR"
        assert_true grep -qx "LC_ALL=sv_SE.UTF-8" /etc/environment
        primer_run -s locale --locale:locale C.UTF-8 install
        assert_equal 0 "$PRIMER_RC" "built-in locale"'
}

# On Debian, the charset of locales missing from /etc/locale.gen comes from
# the list of supported locales. Built-in locales need no generation, and
# locales with unknown charsets are not generated.
test_locale_charset_debian() {
    in_container "$IMG_TRIXIE" '
        primer_run -s locale --locale:locale C.UTF-8 install
        assert_equal 0 "$PRIMER_RC" "built-in locale"
        assert_false command -v locale-gen
        apt-get update -qq >/dev/null && apt-get install -y -qq locales >/dev/null 2>&1
        sed -i "/sv_SE /d" /etc/locale.gen
        primer_run -s locale --locale:locale sv_SE install
        assert_equal 0 "$PRIMER_RC" "locale without charset"
        assert_true grep -qx "sv_SE ISO-8859-1" /etc/locale.gen
        assert_match "^sv_SE$" "$(locale -a)"
        primer_run -s locale --locale:locale xx_YY install
        assert_equal 0 "$PRIMER_RC" "unknown locale"
        assert_contains "Unknown charset for locale xx_YY" "$PRIMER_ERR"
        assert_false grep -q "^xx_YY" /etc/locale.gen'
}
