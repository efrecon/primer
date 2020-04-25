#!/usr/bin/env sh

# This a module dummy variable.
TEST_VARIABLE=${TEST_VARIABLE:-}

# Name of test to perform at installation
TEST_TEST=${TEST_TEST:-}

test() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    --variable)
                        TEST_VARIABLE=$2; shift 2;;
                    --test)
                        TEST_TEST=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !";;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            case "$TEST_TEST" in
                variable)
                    echo "$TEST_VARIABLE";;
                sudo)
                    echo "$PRIMER_OS_SUDO";;
                platform | distribution)
                    "primer_$TEST_TEST";;
                locate)
                    primer_utils_locate "test";;
                *)
                    yush_warn "$TEST_TEST is an unknown test";;
            esac
            ;;
        "clean")
            ;;
    esac
}
