#!/usr/bin/env sh

# Type of keys to generate and install.
SSH_KEYS_TYPE=${SSH_KEYS_TYPE:-ed25519}

SSH_KEYS_RSA_LEN=${SSH_KEYS_RSA_LEN:-4096}
SSH_KEYS_ECDSA_LEN=${SSH_KEYS_ECDSA_LEN:-521}; # This IS 521!

ssh_keys() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    --type)
                        SSH_KEYS_TYPE=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !";;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            primer_dependency "" openssh
            yush_info "Creating password-less SSH $SSH_KEYS_TYPE key pairs"
            if ! [ -f "$HOME/.ssh/id_$SSH_KEYS_TYPE" ]; then
                case "$SSH_KEYS_TYPE" in
                    rsa)
                        ssh-keygen -N "" -t "$SSH_KEYS_TYPE" -b "$SSH_KEYS_RSA_LEN" -q -f "$HOME/.ssh/id_$SSH_KEYS_TYPE";;
                    ecdsa)
                        ssh-keygen -N "" -t "$SSH_KEYS_TYPE" -b "$SSH_KEYS_ECDSA_LEN" -q -f "$HOME/.ssh/id_$SSH_KEYS_TYPE";;
                    *)
                        ssh-keygen -N "" -t "$SSH_KEYS_TYPE" -q -f "$HOME/.ssh/id_$SSH_KEYS_TYPE";;
                esac
            fi
            ;;
        "clean")
            if [ -f "$HOME/.ssh/id_$SSH_KEYS_TYPE" ]; then
                yush_info "Removing ssh key pairs from $HOME/.ssh/id_$SSH_KEYS_TYPE"
                rm -f "$HOME/.ssh/id_$SSH_KEYS_TYPE"
                if [ -f "$HOME/.ssh/id_${SSH_KEYS_TYPE}.pub" ]; then
                    rm -f "$HOME/.ssh/id_${SSH_KEYS_TYPE}.pub"
                fi
            fi
            ;;
    esac
}
