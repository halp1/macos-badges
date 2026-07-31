#!/bin/bash
# Creates a self-signed code-signing identity in the login keychain.
#
# Why: an ad-hoc signature (`codesign -s -`) makes TCC bind the Accessibility grant to the
# binary's cdhash, so every rebuild silently voids it. Signing with a stable certificate
# makes the designated requirement "identifier + this leaf certificate" instead, which
# survives rebuilds — grant Accessibility once and it stays.
#
# Undo with:  security delete-identity -c "Badgeify Local Signing"
set -euo pipefail

NAME=${1:-Badgeify Local Signing}
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "==> identity \"$NAME\" already exists"
  security find-identity -p codesigning | grep "$NAME" || true
  exit 0
fi

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

echo "==> generating a self-signed code-signing certificate"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$DIR/key.pem" -out "$DIR/cert.pem" \
  -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# macOS's Security framework can't read OpenSSL 3's default PKCS#12 encryption, and an
# empty export password fails its MAC check — hence the legacy ciphers and a throwaway one.
PASS=badgeify-import
openssl pkcs12 -export -out "$DIR/identity.p12" \
  -inkey "$DIR/key.pem" -in "$DIR/cert.pem" \
  -passout "pass:$PASS" -macalg sha1 \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES 2>/dev/null

echo "==> importing into the login keychain"
# -A lets codesign use the key without a per-signature keychain prompt.
security import "$DIR/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign -A >/dev/null

echo "==> installed:"
security find-identity -p codesigning | grep "$NAME" || {
  echo "    (not listed as valid — the certificate is self-signed, which is expected;"
  echo "     build.sh will still use it if codesign accepts it)"
}
echo
echo "Next: ./build.sh   then grant Accessibility once — it will persist across rebuilds."
