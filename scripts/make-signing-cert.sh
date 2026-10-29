#!/bin/bash
# Creates a self-signed code-signing certificate, "gaze-switch local", in your login keychain.
# Run it once. build-app.sh then signs with it, so macOS keeps gaze-switch's camera and
# Accessibility permissions across rebuilds instead of treating each build as a new app.
# The certificate is only for signing builds on this Mac; it isn't trusted for anything else.
set -euo pipefail

name="gaze-switch local"
keychain="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if security find-certificate -c "$name" "$keychain" >/dev/null 2>&1; then
    echo "\"$name\" is already set up."
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# macOS's own LibreSSL writes a .p12 that the security tool can import.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$name" \
    -out "$tmp/identity.p12" -passout pass:gaze-switch
security import "$tmp/identity.p12" -k "$keychain" -P gaze-switch -T /usr/bin/codesign >/dev/null

echo "Created \"$name\". Rebuild with ./scripts/build-app.sh --install."
echo "The first build may ask to let codesign use the key; choose Always Allow."
