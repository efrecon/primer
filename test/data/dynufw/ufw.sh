#!/bin/sh

# Sourced inside test containers (with test/lib.sh) to replace ufw by a
# function that logs its calls to $MOCK_LOG and keeps the added rules in
# $UFW_ADDED, in the format of "ufw show added". Like ufw, adding a rule that
# exists (whatever its action) does not duplicate it: an identical rule is
# skipped, a comment replaces the existing one, another action (e.g. allow
# instead of limit) replaces the rule. Rules for a source are listed with the
# protocol last, as ufw does.

UFW_ADDED=${UFW_ADDED:-/tmp/ufw.added}

ufw() {
    mock_log ufw "$@"
    case "$1" in
        show)
            echo "Added user rules (see 'ufw status' for running firewall):"
            if [ -f "$UFW_ADDED" ]; then
                grep '^ufw ' "$UFW_ADDED" || true
            fi
            ;;
        allow|limit|deny|reject)
            _ufw_action=$1
            shift
            _ufw_rule=$*
            _ufw_comment=
            case "$_ufw_rule" in
                *" comment "*)
                    _ufw_comment=${_ufw_rule#* comment }
                    _ufw_rule=${_ufw_rule%% comment *}
                    ;;
            esac
            # Listed like ufw does: the protocol comes last.
            case "$_ufw_rule" in
                "proto "*" from "*)
                    _ufw_proto=${_ufw_rule#proto }
                    _ufw_proto=${_ufw_proto%% *}
                    _ufw_rule="${_ufw_rule#proto "$_ufw_proto" } proto $_ufw_proto"
                    ;;
            esac
            touch "$UFW_ADDED"
            awk -v a="$_ufw_action" -v r="$_ufw_rule" -v c="$_ufw_comment" '
                BEGIN { q = sprintf("%c", 39) }
                /^ufw / {
                    rule = $0
                    sub(/ comment .*/, "", rule)
                    tuple = rule
                    sub(/^ufw [a-z]+ /, "", tuple)
                    if (tuple == r) {
                        found = 1
                        # Identical rule, no new comment: skipped
                        if (rule == "ufw " a " " r && c == "") { print; next }
                        $0 = "ufw " a " " r (c != "" ? " comment " q c q : "")
                    }
                }
                { print }
                END { if (!found) print "ufw " a " " r (c != "" ? " comment " q c q : "") }
            ' "$UFW_ADDED" > "$UFW_ADDED.new"
            mv "$UFW_ADDED.new" "$UFW_ADDED"
            ;;
    esac
    return 0
}
