// Builds the install manifest that iOS fetches for an itms-services:// link.
//
// iOS only accepts a manifest served over HTTPS with a publicly trusted certificate, but it
// will download the .ipa itself over plain HTTP. So Spectra Signer serves the .ipa from a
// local server on the phone and points iOS here for the manifest.
//
// GET /api/manifest?ipa=http://127.0.0.1:PORT/…/app.ipa&bundle=ID&version=V&title=NAME[&icon=URL]
//
// Only .ipa and icon URLs on the device itself (loopback or a private network address) are
// accepted, so this can't be used to build install links for apps hosted elsewhere.

const BUNDLE_ID = /^[A-Za-z0-9.-]{1,255}$/;

function isLocalHost(hostname) {
	const host = hostname.replace(/^\[|\]$/g, "").toLowerCase();
	if (host === "localhost" || host === "::1") return true;
	const parts = host.split(".").map(Number);
	if (parts.length !== 4 || parts.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) return false;
	const [a, b] = parts;
	return a === 127 || a === 10 || (a === 192 && b === 168) || (a === 172 && b >= 16 && b <= 31) || (a === 169 && b === 254);
}

function localURL(value) {
	if (!value || value.length > 2048) return null;
	let url;
	try {
		url = new URL(value);
	} catch {
		return null;
	}
	if (url.protocol !== "http:" && url.protocol !== "https:") return null;
	return isLocalHost(url.hostname) ? url.href : null;
}

function text(value, max) {
	if (typeof value !== "string") return null;
	const trimmed = value.trim();
	return trimmed && trimmed.length <= max ? trimmed : null;
}

function xml(value) {
	return value
		.replace(/&/g, "&amp;")
		.replace(/</g, "&lt;")
		.replace(/>/g, "&gt;")
		.replace(/"/g, "&quot;")
		.replace(/'/g, "&apos;");
}

module.exports = (req, res) => {
	res.setHeader("Cache-Control", "no-store");

	const q = req.query || {};
	const ipa = localURL(q.ipa);
	const icon = q.icon ? localURL(q.icon) : null;
	const bundle = text(q.bundle, 255);
	const version = text(q.version, 64) || "1.0";
	const title = text(q.title, 200) || bundle;

	if (!ipa || !bundle || !BUNDLE_ID.test(bundle) || (q.icon && !icon)) {
		res.statusCode = 400;
		res.setHeader("Content-Type", "text/plain; charset=utf-8");
		res.end("Expected ipa (a URL on the device), bundle, and optionally version, title and icon.\n");
		return;
	}

	const assets = [`<dict><key>kind</key><string>software-package</string><key>url</key><string>${xml(ipa)}</string></dict>`];
	if (icon) {
		for (const kind of ["display-image", "full-size-image"]) {
			assets.push(`<dict><key>kind</key><string>${kind}</string><key>url</key><string>${xml(icon)}</string></dict>`);
		}
	}

	const body = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>items</key>
	<array>
		<dict>
			<key>assets</key>
			<array>${assets.join("")}</array>
			<key>metadata</key>
			<dict>
				<key>bundle-identifier</key><string>${xml(bundle)}</string>
				<key>bundle-version</key><string>${xml(version)}</string>
				<key>kind</key><string>software</string>
				<key>title</key><string>${xml(title)}</string>
			</dict>
		</dict>
	</array>
</dict>
</plist>
`;

	res.statusCode = 200;
	res.setHeader("Content-Type", "text/xml; charset=utf-8");
	res.end(body);
};
