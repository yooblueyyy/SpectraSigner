#!/bin/sh
# Fetches the certificate for the on-device install server.
#
# iOS only installs apps from an HTTPS manifest with a publicly trusted certificate.
# backloop.dev publishes a trusted certificate for *.backloop.dev, a domain that resolves
# to 127.0.0.1, specifically so local servers can use HTTPS. The build bundles it as
# Resources/server.p12 (password "spectra") plus the domain name in Resources/commonName.txt.
#
# Requires curl, jq and openssl.
set -eu
cd "$(dirname "$0")/.."

mkdir -p Resources
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL https://backloop.dev/pack.json -o "$tmp/pack.json"
jq -r '.cert' "$tmp/pack.json" > "$tmp/server.crt"
jq -r '.key1, .key2' "$tmp/pack.json" > "$tmp/server.key"
jq -r '.info.domains.commonName' "$tmp/pack.json" > Resources/commonName.txt

# 3DES/SHA1 keeps the PKCS#12 readable by SecPKCS12Import on every supported iOS version.
openssl pkcs12 -export \
	-inkey "$tmp/server.key" -in "$tmp/server.crt" \
	-out Resources/server.p12 -passout pass:spectra \
	-certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1

echo "Install-server certificate ready for $(cat Resources/commonName.txt)"
