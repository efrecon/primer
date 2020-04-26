#!/usr/bin/env sh

# Type of keys to generate and install.
PRIMER_STEP_SSHKEYS_TYPE=${PRIMER_STEP_SSHKEYS_TYPE:-ed25519}

PRIMER_STEP_SSHKEYS_RSA_LEN=${PRIMER_STEP_SSHKEYS_RSA_LEN:-4096}
PRIMER_STEP_SSHKEYS_ECDSA_LEN=${PRIMER_STEP_SSHKEYS_ECDSA_LEN:-521}; # This IS 521!
primer_step_sshkeys() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    --type)
                        PRIMER_STEP_SSHKEYS_TYPE=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            primer_os_dependency "" openssh
            yush_info "Creating password-less SSH $PRIMER_STEP_SSHKEYS_TYPE key pairs"
            if ! [ -f "$HOME/.ssh/id_$PRIMER_STEP_SSHKEYS_TYPE" ]; then
                case "$PRIMER_STEP_SSHKEYS_TYPE" in
                    rsa)
                        ssh-keygen -N "" -t "$PRIMER_STEP_SSHKEYS_TYPE" -b "$PRIMER_STEP_SSHKEYS_RSA_LEN" -q -f "$HOME/.ssh/id_$PRIMER_STEP_SSHKEYS_TYPE";;
                    ecdsa)
                        ssh-keygen -N "" -t "$PRIMER_STEP_SSHKEYS_TYPE" -b "$PRIMER_STEP_SSHKEYS_ECDSA_LEN" -q -f "$HOME/.ssh/id_$PRIMER_STEP_SSHKEYS_TYPE";;
                    *)
                        ssh-keygen -N "" -t "$PRIMER_STEP_SSHKEYS_TYPE" -q -f "$HOME/.ssh/id_$PRIMER_STEP_SSHKEYS_TYPE";;
                esac
            fi
            ;;
        "clean")
            if [ -f "$HOME/.ssh/id_$PRIMER_STEP_SSHKEYS_TYPE" ]; then
                yush_info "Removing ssh key pairs from $HOME/.ssh/id_$PRIMER_STEP_SSHKEYS_TYPE"
                rm -f "$HOME/.ssh/id_$PRIMER_STEP_SSHKEYS_TYPE"
                if [ -f "$HOME/.ssh/id_${PRIMER_STEP_SSHKEYS_TYPE}.pub" ]; then
                    rm -f "$HOME/.ssh/id_${PRIMER_STEP_SSHKEYS_TYPE}.pub"
                fi
            fi
            ;;
    esac
}
