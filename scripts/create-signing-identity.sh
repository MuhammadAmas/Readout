#!/usr/bin/env bash
set -euo pipefail

name="Readout Local Signing"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -q "\"$name\""; then
    echo "\"$name\" already exists in your login keychain"
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
umask 077

cat > "$work/cert.cnf" <<EOF
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
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$work/key.pem" -out "$work/cert.pem" -config "$work/cert.cnf" 2>/dev/null
password="$(openssl rand -hex 16)"
openssl pkcs12 -export -name "$name" -inkey "$work/key.pem" -in "$work/cert.pem" \
    -out "$work/identity.p12" -passout "pass:$password" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
security import "$work/identity.p12" -k "$keychain" -P "$password" -T /usr/bin/codesign

echo "Created \"$name\". make app now signs with it, so Accessibility access survives rebuilds."
