#!/bin/sh
# Snippets are single-quoted on purpose: they are expanded in containers.
# shellcheck disable=SC2016

# Unit tests for libexec/version.sh.

test_primer_version_current() {
    unit "$IMG_ALPINE" '
        stub_bin tool-word "echo \"tool-word version 1.2.3 (build 45, 2.0 compatible)\""
        stub_bin tool-plain "echo \"tool-plain 4.5\""
        stub_bin tool-multi "printf \"Copyright 2020-2024\nVersion: 7.8.9\n\""
        stub_bin tool-upper "echo \"TOOL VERSION v10.0\""
        assert_equal 1.2.3 "$(primer_version_current tool-word)"
        assert_equal 4.5 "$(primer_version_current tool-plain)"
        assert_equal 7.8.9 "$(primer_version_current tool-multi)"
        assert_equal 10.0 "$(primer_version_current tool-upper)"
        # Missing commands give no version, and no error
        run primer_version_current no-such-tool
        assert_equal 0 "$RUN_RC"
        assert_equal "" "$RUN_OUT"'
}
