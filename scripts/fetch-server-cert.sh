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

# pack.json only has the leaf certificate. iOS doesn't fetch missing intermediates when it
# downloads the manifest, so without them the install prompt never appears. Follow the
# issuer links (including cross-signs, e.g. Root YR -> ISRG Root X1) and bundle them too.
: > "$tmp/chain.pem"
cert="$tmp/server.crt"
i=0
while [ $i -lt 4 ]; do
	issuer=$(openssl x509 -in "$cert" -noout -text | sed -n 's/.*CA Issuers - URI:\(.*\)$/\1/p' | head -1)
	[ -n "$issuer" ] || break
	i=$((i + 1))
	curl -fsSL "$issuer" -o "$tmp/issuer$i.der"
	openssl x509 -inform DER -in "$tmp/issuer$i.der" -out "$tmp/issuer$i.pem" 2>/dev/null \
		|| openssl x509 -in "$tmp/issuer$i.der" -out "$tmp/issuer$i.pem"
	# Roots are already in the device's trust store.
	[ "$(openssl x509 -in "$tmp/issuer$i.pem" -noout -subject | sed 's/^subject=//')" != \
		"$(openssl x509 -in "$tmp/issuer$i.pem" -noout -issuer | sed 's/^issuer=//')" ] || break
	cat "$tmp/issuer$i.pem" >> "$tmp/chain.pem"
	cert="$tmp/issuer$i.pem"
done
[ $i -gt 0 ] || { echo "Couldn't find the server certificate's issuer" >&2; exit 1; }

# 3DES/SHA1 keeps the PKCS#12 readable by SecPKCS12Import on every supported iOS version.
openssl pkcs12 -export \
	-inkey "$tmp/server.key" -in "$tmp/server.crt" -certfile "$tmp/chain.pem" \
	-out Resources/server.p12 -passout pass:spectra \
	-certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1

echo "Install-server certificate ready for $(cat Resources/commonName.txt)"
