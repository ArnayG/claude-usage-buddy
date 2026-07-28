#!/bin/bash
#
# Creates a stable self-signed code signing identity in the login keychain.
#
# Why: an ad-hoc signature (`codesign -s -`) is derived from the binary hash, so it
# changes on every build. The keychain ACL that "Always Allow" writes is bound to the
# app's designated requirement, which is derived from that signature — so every
# rebuild invalidates it and macOS prompts again for the OAuth token. Signing with a
# fixed certificate makes the designated requirement stable, and the grant sticks.
#
# Safe to re-run: it exits early if the identity already exists.
# To undo, see `scripts/remove-signing-identity.sh`.

set -euo pipefail

NAME="Claude Usage Buddy Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "Identity '$NAME' already exists — nothing to do."
    security find-identity -v -p codesigning | grep "$NAME"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/ext.cnf" <<'EOF'
[req]
distinguished_name=dn
prompt=no
x509_extensions=v3
[dn]
CN=Claude Usage Buddy Dev
[v3]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
EOF

echo "==> Generating certificate (valid 10 years)"
# /usr/bin/openssl is LibreSSL. Homebrew's OpenSSL 3 defaults to PKCS#12 algorithms
# that macOS cannot read ("MAC verification failed" on import), so pin to the
# system one rather than whatever is first on PATH.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/ext.cnf" 2>/dev/null

# `security import` rejects PKCS#12 bundles with an empty passphrase, so use a
# throwaway one. The bundle is deleted on exit; only the keychain entry persists.
PASS="cub-$RANDOM"
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/ident.p12" -passout "pass:$PASS" -name "$NAME" 2>/dev/null

echo "==> Importing into the login keychain"
security import "$WORK/ident.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign -A >/dev/null

echo "==> Trusting it for code signing"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo
if security find-identity -v -p codesigning | grep -q "$NAME"; then
    security find-identity -v -p codesigning | grep "$NAME"
    echo
    echo "Done. Rebuild with 'make install'."
    echo "macOS will prompt once more for keychain access — click Always Allow."
    echo "That grant now survives future rebuilds."
else
    echo "Identity was created but is not showing as valid. Check Keychain Access." >&2
    exit 1
fi
