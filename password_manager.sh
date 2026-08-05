#!/bin/bash
#
# Basic Bash Password Manager — v-2.0
# Master-password auth + AES-256 vault via OpenSSL.
# Hardened build: salted master hash, PBKDF2 key derivation,
# guaranteed re-encryption on any exit path, ASCII startup banner.
# Educational project.

set -u
VERSION="2.0"

# ---------- Configuration ----------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VAULT_PLAIN="$SCRIPT_DIR/vault.txt"
readonly VAULT_ENC="$SCRIPT_DIR/vault.enc"
readonly MASTER_HASH="$SCRIPT_DIR/.master.hash"
readonly MAX_TRIES=3
readonly PBKDF2_ITER=200000

# ---------- Utility: portable print ----------
prn() { printf '%s\n' "$*"; }

# ---------- ASCII startup banner ----------
banner() {
    prn ""
    printf '%s\n' \
        '██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗' \
        '██║     ██║████╗  ██║██║   ██║╚██╗██╔╝' \
        '██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝ ' \
        '██║     ██║██║╚██╗██║██║   ██║ ██╔██╗ ' \
        '███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗' \
        '╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝' \
        '                                      ' \
        '██████╗  █████╗ ███████╗███████╗' \
        '██╔══██╗██╔══██╗██╔════╝██╔════╝' \
        '██████╔╝███████║███████╗███████╗' \
        '██╔═══╝ ██╔══██║╚════██║╚════██║' \
        '██║     ██║  ██║███████║███████║' \
        '╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝     2.0' \
        '                                      ' \
        'A simple CLI-based local password manager by ekka.' \
        '                                      ' \
        'For more information visit the page -- https://github.com/ekka-np/bash-password-manager-26/tree/v-2.0'
}

# ---------- "EXITING" banner (plain white) ----------
exiting_banner() {
    prn ""
    printf '%s\n' \
        '███████╗██╗  ██╗██╗████████╗██╗███╗   ██╗ ██████╗ ' \
        '██╔════╝╚██╗██╔╝██║╚══██╔══╝██║████╗  ██║██╔════╝ ' \
        '█████╗   ╚███╔╝ ██║   ██║   ██║██╔██╗ ██║██║  ███╗' \
        '██╔══╝   ██╔██╗ ██║   ██║   ██║██║╚██╗██║██║   ██║' \
        '███████╗██╔╝ ██╗██║   ██║   ██║██║ ╚████║╚██████╔╝' \
        '╚══════╝╚═╝  ╚═╝╚═╝   ╚═╝   ╚═╝╚═╝  ╚═══╝ ╚═════╝ '
}

# ---------- "SETUP COMPLETE" banner (plain white) ----------
setup_complete_banner() {
    prn ""
    printf '%s\n' \
        '███████╗███████╗████████╗██╗   ██╗██████╗                            ' \
        '██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗                           ' \
        '███████╗█████╗     ██║   ██║   ██║██████╔╝                           ' \
        '╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝                           ' \
        '███████║███████╗   ██║   ╚██████╔╝██║                               ' \
        '╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝                               ' \
        '                                                                      ' \
        ' ██████╗ ██████╗ ███╗   ███╗██████╗ ██╗     ███████╗████████╗███████╗' \
        '██╔════╝██╔═══██╗████╗ ████║██╔══██╗██║     ██╔════╝╚══██╔══╝██╔════╝' \
        '██║     ██║   ██║██╔████╔██║██████╔╝██║     █████╗     ██║   █████╗  ' \
        '██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██║     ██╔══╝     ██║   ██╔══╝  ' \
        '╚██████╗╚██████╔╝██║ ╚═╝ ██║██║     ███████╗███████╗   ██║   ███████╗' \
        ' ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚══════╝╚══════╝   ╚═╝   ╚══════╝'
}

# ---------- Dependency check ----------
check_deps() {
    if ! command -v openssl >/dev/null 2>&1; then
        prn "Error: 'openssl' is required but not found."
        prn "Install it (e.g. 'sudo apt install openssl') and retry." >&2
        exit 1
    fi
}

# ---------- Hashing (salted) ----------
# Portable across sha256sum / shasum (macOS) / openssl dgst.
hash_password() {
    local pw="$1" salt="$2" in
    in="$(printf '%s%s' "$pw" "$salt")"
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s\n' "$in" | sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s\n' "$in" | shasum -a 256 | awk '{print $1}'
    else
        printf '%s\n' "$in" | openssl dgst -sha256 | awk '{print $NF}'
    fi
}

# ---------- Encryption helpers ----------
# Password is piped on stdin so it never appears in the process list (ps).
encrypt_vault() {
    if printf '%s\n' "$1" | openssl enc -aes-256-cbc -salt -pbkdf2 -iter "$PBKDF2_ITER" \
        -in "$VAULT_PLAIN" -out "$VAULT_ENC" -pass stdin; then
        rm -f "$VAULT_PLAIN"
        chmod 600 "$VAULT_ENC"
    else
        prn "Error: vault encryption failed. Plaintext left in place." >&2
        return 1
    fi
}

decrypt_vault() {
    printf '%s\n' "$1" | openssl enc -aes-256-cbc -d -pbkdf2 -iter "$PBKDF2_ITER" \
        -in "$VAULT_ENC" -out "$VAULT_PLAIN" -pass stdin
}

# ---------- Guaranteed cleanup on ANY exit ----------
# Only re-encrypts when the session opened the vault successfully; otherwise it
# just removes the (possibly partial) plaintext and leaves vault.enc untouched.
cleanup() {
    if [ -f "$VAULT_PLAIN" ]; then
        if [ -n "${MASTER_PASS:-}" ] && [ "${DECRYPTED:-0}" -eq 1 ]; then
            encrypt_vault "$MASTER_PASS" >/dev/null 2>&1
        else
            rm -f "$VAULT_PLAIN"
        fi
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# ---------- CLI flags ----------
case "${1:-}" in
    --version|-v)
        prn "password_manager v$VERSION"
        exit 0;;
    --help|-h)
        prn "Usage: $0 [--help] [--version]"
        prn "  --help, -h    show this help"
        prn "  --version,-v  print version"
        exit 0;;
esac

check_deps
banner

# ---------- First-time master password setup ----------
# Triggers when the master hash OR the encrypted vault is missing, so a
# deleted vault.enc means a fresh start (new master password), not reuse.
if [ ! -f "$MASTER_HASH" ] || [ ! -f "$VAULT_ENC" ]; then
    prn ""
    prn "First-time setup"
    prn ""
    IFS= read -r -s -p "Create master password: " MP1; prn ""
    IFS= read -r -s -p "Confirm master password: " MP2; prn ""

    if [ "$MP1" != "$MP2" ]; then
        prn "Passwords do not match"; exit 1
    fi
    if [ -z "$MP1" ]; then
        prn "Password cannot be empty"; exit 1
    fi

    SALT="$(openssl rand -hex 16)"
    printf '%s:%s\n' "$SALT" "$(hash_password "$MP1" "$SALT")" > "$MASTER_HASH"
    chmod 600 "$MASTER_HASH"
    prn "Master password created."
    setup_complete_banner
    MASTER_PASS="$MP1"
fi

# ---------- Login with limited attempts (skipped right after first-time setup) ----------
if [ -z "${MASTER_PASS:-}" ]; then
    read -r SALT_HASH < "$MASTER_HASH"     # full 'salt:hash' line
    SALT="${SALT_HASH%%:*}"               # salt is the field before ':'

    TRIES=0
    while [ "$TRIES" -lt "$MAX_TRIES" ]; do
        IFS= read -r -s -p "Enter master password: " INPUT; prn ""
        if [ "$(hash_password "$INPUT" "$SALT")" = "$(cut -d: -f2 < "$MASTER_HASH")" ]; then
            MASTER_PASS="$INPUT"
            break
        else
            prn "Incorrect password"
            TRIES=$((TRIES + 1))
        fi
    done

    if [ "$TRIES" -eq "$MAX_TRIES" ]; then
        prn "Invalid attempts. Access denied."
        exit 1
    fi
fi

# ---------- Decrypt or create vault ----------
if [ -f "$VAULT_ENC" ]; then
    if ! decrypt_vault "$MASTER_PASS"; then
        prn "Error: vault decryption failed (wrong key or corrupt file)."
        prn "Your vault.enc was left untouched."
        rm -f "$VAULT_PLAIN"
        exit 1
    fi
    DECRYPTED=1
else
    : > "$VAULT_PLAIN"
    chmod 600 "$VAULT_PLAIN"
    DECRYPTED=1
fi

# ---------- Menu ----------
while :; do
    prn ""
    prn "1. Add password"
    prn "2. View passwords"
    prn "3. Change master password"
    prn "4. Exit"
    if ! IFS= read -r -p "Select option: " CHOICE; then
        prn ""
        prn "Input closed — encrypting vault and exiting."
        exiting_banner
        break
    fi

    case $CHOICE in
        1)
            IFS= read -r -p "Service: " SERVICE
            IFS= read -r -p "Username: " USERNAME
            IFS= read -r -s -p "Password: " PASSWORD; prn ""
            printf '%s\t%s\t%s\n' "$SERVICE" "$USERNAME" "$PASSWORD" >> "$VAULT_PLAIN"
            ;;
        2)
            prn ""
            cat "$VAULT_PLAIN"
            ;;
        3)
            IFS= read -r -s -p "Enter current master password: " OLD; prn ""
            if [ "$(hash_password "$OLD" "$SALT")" != "$(cut -d: -f2 < "$MASTER_HASH")" ]; then
                prn "Incorrect current password"
            else
                IFS= read -r -s -p "Enter new master password: " NEW1; prn ""
                IFS= read -r -s -p "Confirm new master password: " NEW2; prn ""
                if [ "$NEW1" != "$NEW2" ]; then
                    prn "Passwords do not match"
                elif [ -z "$NEW1" ]; then
                    prn "Password cannot be empty"
                else
                    NEW_SALT="$(openssl rand -hex 16)"
                    printf '%s:%s\n' "$NEW_SALT" "$(hash_password "$NEW1" "$NEW_SALT")" > "$MASTER_HASH"
                    chmod 600 "$MASTER_HASH"
                    SALT="$NEW_SALT"
                    MASTER_PASS="$NEW1"
                    prn "Master password updated (vault will re-encrypt on exit)."
                fi
            fi
            ;;
        4)
            prn "Encrypting vault and exiting..."
            exiting_banner
            exit 0
            ;;
        *)
            prn "Invalid option";;
    esac
done