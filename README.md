# bash_password_manager_26 — v-2.0

A beginner-friendly password manager written in Bash.
Master-password authentication, AES-256 encryption, up to 3 login attempts.
Designed for learning Bash scripting, file handling, and basic encryption.

> **v-2.0** is a hardening + quality pass over the original build (`v-1.0`).
> It fixes the bugs found in a code audit, improves robustness, and gets a
> lightweight ASCII startup banner. It remains a **single, dependency-light
> Bash script** — everything below stays in the spirit of a lean tool.

---

## What the v-1.0 audit found (and the bugs)

Reviewing `v-1.0/password_manager.sh` surfaced several issues. Each is
listed with the fix that landed in v-2.0 and *why it matters*.

### Bug 1 — Plaintext vault is leaked on Ctrl+C (data loss + exposure)
**Bug:** The vault is only encrypted when the user picks option `4` (`Exit`).
If the script is interrupted (Ctrl+C, SSH drop, `kill`), `vault.txt` is left
on disk **in cleartext** — your credentials sit unencrypted, and worse, an
unexpected kill mid-session discards your changes.

**Fix (v-2.0):** a `trap` on `EXIT INT TERM HUP` calls a cleanup function that
re-encrypts the vault (if a master password is known) and removes the
plaintext file. Encryption is now guaranteed on *any* exit path, not just the
clean menu exit.

*Why:* a password manager's whole job is protecting data *at rest*; leaving a
decrypted copy behind negates it. This was the most serious finding.

### Bug 2 — Unsalted, fast SHA-256 master hash (brute-force friendly)
**Bug:** `echo -n "$1" | sha256sum` stores a *plain unsalted* SHA-256. Because
SHA-256 is extremely fast, an attacker with the `.master.hash` file can
dictionary/brute-force the master password at billions of guesses/sec.

**Fix (v-2.0):** the master password is now stored as a **salted** hash. A
random salt is generated with `openssl rand -hex` on setup and combined with
the password before hashing; the salt is stored alongside the hash.

*Why:* salting defeats precomputed rainbow tables and forces per-file
attacks. It stays lightweight — just one extra `openssl rand` call and a
`printf` — no new dependency.

### Bug 3 — Vault encrypted with the *raw* master password (weak key derivation)
**Bug:** `openssl enc -aes-256-cbc ... -pass pass:"$MASTER_PASS"` uses the
cleartext master password directly as the encryption key material. Low-entropy
passwords map to weak keys, and the same password is reused for hashing.

**Fix (v-2.0):** the vault now uses OpenSSL's **PBKDF2** key derivation with an
explicit iteration count (`-iter 200000`) and a random salt (`-salt`).
`-pbkdf2` was already present but used no iteration count; the default is far
too low.

*Why:* PBKDF2 stretches a weak password into a strong key and slows offline
guessing. For an educational tool this is a cheap, high-value hardening win.

### Bug 4 — Non-portable / fragile shell constructs
- **Bug:** `echo -n` is not portable across shells/`sh`; behaves
  inconsistently.
  **Fix:** switched to `printf` for hashing and all output.
- **Bug:** `read` without `-r` mangles backslashes in input.
  **Fix:** added `read -r`.
- **Bug:** whitespace in the master password was silently stripped.
  **Fix:** use `IFS=`/`read -r` so every character is honored honestly.
- **Bug:** no dependency check — if `openssl` is missing the script fails
  with a cryptic error.
  **Fix:** a startup check prints a clear, friendly message and exits.

*Why:* portability and predictable input handling make the tool behave the
same on Ubuntu, Debian, Fedora, Arch, and MacOS; a friendly dependency check
turns silent failures into actionable messages.

---

## Aesthetic update

**ASCII startup banner.** Like many Linux/CLI tools, the script now prints a
small ASCII-art wordmark on launch. It is:
- **Pure Bash** — raw `printf` art, no `figlet`/`toilet` dependency.
- **Fast & unobtrusive** — printed once, milliseconds, with a version line.
- **Optional** — respect `NO_COLOR`, and it never interferes with
  piped/scripted use.

This gives the tool a sense of character without adding a byte of runtime
weight.

---

## Features
- Master password authentication (salted SHA-256 hash)
- Maximum of **3 login attempts**
- Password storage using **AES-256-CBC** via OpenSSL
- **PBKDF2** key derivation (200,000 iterations) for the vault
- Guaranteed re-encryption on clean exit **or** Ctrl+C (trap handler)
- Random selection of the hashing salt
- ASCII startup banner with version
- Clear error messages; OpenSSL presence check

## Tools Used
- Bash scripting
- OpenSSL (AES-256-CBC, PBKDF2, `rand`)
- SHA-256 (salted)
- Linux (Ubuntu, Debian, Fedora, Arch, Manjaro, Kali, macOS)

## How It Works
1. On first run, a **salted** master hash is created and stored.
2. Login (max 3 attempts) verifies against the salted hash.
3. The vault is decrypted into a plaintext scratch file.
4. Add / view / change-master-password interactively.
5. Any exit path — menu `Exit`, Ctrl+C, or signal — re-encrypts the vault and
   deletes the plaintext file.
6. The `.vault.enc` salt/iteration metadata stays alongside the ciphertext.

## Installation

```bash
git clone https://github.com/ekka-np/bash_password_manager_26.git
cd bash_password_manager_26/v-2.0
chmod +x password_manager.sh
./password_manager.sh
```

## Disclaimer
This project is **for educational purposes only**. It teaches Bash scripting,
file handling, and basic encryption patterns. Do not rely on it as a
production-grade credential store.