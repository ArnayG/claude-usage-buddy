#!/bin/bash
#
# Removes the self-signed code signing identity created by
# scripts/create-signing-identity.sh, including its trust setting.
#
# After running this, builds fall back to ad-hoc signing and macOS will prompt for
# keychain access again after every rebuild.

set -euo pipefail

NAME="Claude Usage Buddy Dev"

if ! security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "No certificate named '$NAME' found — nothing to remove."
    exit 0
fi

echo "==> Removing trust setting"
security remove-trusted-cert -d <(security find-certificate -c "$NAME" -p) 2>/dev/null || \
    echo "    (no admin trust entry; continuing)"

echo "==> Deleting certificate and private key"
# Repeat: a keychain can hold more than one generation of the identity.
while security find-certificate -c "$NAME" >/dev/null 2>&1; do
    security delete-identity -c "$NAME" >/dev/null 2>&1 || \
      security delete-certificate -c "$NAME" >/dev/null 2>&1 || break
done

echo "Done. Builds will use ad-hoc signing again."
