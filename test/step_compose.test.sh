#!/bin/sh

# Snippets in single quotes are expanded in the containers, not here.
# shellcheck disable=SC2016

# Tests for the deprecated compose step: it only prints a notice.

test_compose_notice() {
    primer_in "$IMG_ALPINE" -s compose install -- '
        assert_equal 0 "$PRIMER_RC"
        assert_contains "Docker compose is now a Docker CLI plugin" "$PRIMER_ERR"
        assert_false command -v docker
        assert_false command -v docker-compose
        primer_run -s compose clean
        assert_equal 0 "$PRIMER_RC"
        assert_contains "Docker compose is now a Docker CLI plugin" "$PRIMER_ERR"'
}

test_compose_ignores_old_options() {
    primer_in "$IMG_ALPINE" -s compose --compose:version=1.29.2 --compose:sha256=abc --compose:python never install -- '
        assert_equal 0 "$PRIMER_RC"
        assert_contains "option --version ignored" "$PRIMER_ERR"
        assert_contains "option --sha256 ignored" "$PRIMER_ERR"
        assert_contains "option --python ignored" "$PRIMER_ERR"
        assert_false command -v docker-compose'
}

test_compose_has_no_options() {
    primer_in "$IMG_ALPINE" -s compose info -- '
        assert_equal 0 "$PRIMER_RC"
        assert_match "^compose: *$" "$PRIMER_OUT"'
}
