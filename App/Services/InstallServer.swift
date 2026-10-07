import Foundation
import Network
import Security

/// A tiny HTTPS server on the device that serves an install manifest and the signed .ipa,
/// so iOS can install it through an `itms-services://` link.
///
/// iOS only accepts manifests over HTTPS with a trusted certificate, so the build bundles a
/// publicly trusted certificate for a domain that resolves to 127.0.0.1 (see scripts/fetch-server-cert.sh).
final class InstallServer {
	struct Payload {
		let ipaURL: URL
		let iconURL: URL?
		let bundleID: String
		let version: String
		let title: String
	}

	enum Failure: LocalizedError {
		case missingCertificate, badCertificate, couldNotStart(String)

		var errorDescription: String? {
			switch self {
			case .missingCertificate:
				return "This build is missing the local install-server certificate. Rebuild with scripts/fetch-server-cert.sh, or use Share to install with another tool."
			case .badCertificate:
				return "The local install-server certificate couldn't be loaded."
			case .couldNotStart(let reason):
				return "The local install server couldn't start: \(reason)"
			}
		}
	}

	private let payload: Payload
	private let identity: SecIdentity
	/// The leaf certificate followed by its intermediates, sent during the TLS handshake.
	private let chain: [SecCertificate]
	let host: String
	private let token = UUID().uuidString.lowercased()
	private var listener: NWListener?
	private let queue = DispatchQueue(label: "dev.spectra.install-server")
	private var didReportReady = false

	/// Bytes of the .ipa sent so far, and its total size.
	var onProgress: ((Int64, Int64) -> Void)?
	/// Called once the whole .ipa has been delivered to iOS.
	var onTransferComplete: (() -> Void)?
	/// Human-readable events (connections, TLS errors, requests) for troubleshooting.
	var onEvent: ((String) -> Void)?

	init(payload: Payload) throws {
		let loaded = try Self.loadIdentity()
		self.payload = payload
		self.identity = loaded.identity
		self.chain = loaded.chain
		self.host = loaded.host
	}

	private(set) var port: UInt16 = 0
	private var baseURL: String { "https://\(host):\(port)/\(token)" }
	var manifestURL: URL { URL(string: "\(baseURL)/manifest.plist")! }

	/// The link that asks iOS to install the app. The manifest URL goes in unencoded, as Feather does;
	/// percent-encoding every character of it can stop iOS from showing the prompt.
	var installURL: URL {
		URL(string: "itms-services://?action=download-manifest&url=\(manifestURL.absoluteString)")!
	}

	static var isAvailable: Bool { Bundle.main.url(forResource: "server", withExtension: "p12") != nil }

	private static func loadIdentity() throws -> (identity: SecIdentity, chain: [SecCertificate], host: String) {
		guard
			let p12URL = Bundle.main.url(forResource: "server", withExtension: "p12"),
			let data = try? Data(contentsOf: p12URL)
		else { throw Failure.missingCertificate }

		var items: CFArray?
		let options = [kSecImportExportPassphrase as String: "spectra"] as CFDictionary
		guard
			SecPKCS12Import(data as CFData, options, &items) == errSecSuccess,
			let first = (items as? [[String: Any]])?.first,
			let identityRef = first[kSecImportItemIdentity as String]
		else { throw Failure.badCertificate }

		var host = "local.backloop.dev"
		if
			let url = Bundle.main.url(forResource: "commonName", withExtension: "txt"),
			let name = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
			!name.isEmpty
		{
			host = name.hasPrefix("*.") ? "local" + name.dropFirst(1) : name
		}
		let identity = identityRef as! SecIdentity
		var leaf: SecCertificate?
		SecIdentityCopyCertificate(identity, &leaf)
		guard let leaf else { throw Failure.badCertificate }

		// The intermediates are bundled as chain1.der, chain2.der, … (scripts/fetch-server-cert.sh).
		// They're loaded explicitly: the chain SecPKCS12Import builds can leave out the
		// cross-signed root that iOS needs, and then every TLS handshake fails.
		var chain = [leaf]
		for index in 1... {
			guard
				let url = Bundle.main.url(forResource: "chain\(index)", withExtension: "der"),
				let der = try? Data(contentsOf: url),
				let certificate = SecCertificateCreateWithData(nil, der as CFData)
			else { break }
			chain.append(certificate)
		}
		return (identity, chain, host)
	}

	/// The certificates the server presents, for the install log.
	var chainSummary: String {
		chain.map { SecCertificateCopySubjectSummary($0) as String? ?? "?" }.joined(separator: " → ")
	}

	func start(ready: @escaping (Result<Void, Error>) -> Void) {
		let tls = NWProtocolTLS.Options()
		// Without the intermediates iOS can't verify the manifest's certificate and never shows the install prompt.
		guard let secIdentity = sec_identity_create_with_certificates(identity, chain as CFArray) ?? sec_identity_create(identity) else {
			ready(.failure(Failure.badCertificate))
			return
		}
		sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
		sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)

		let params = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
		params.allowLocalEndpointReuse = true

		let listener: NWListener
		do {
			listener = try NWListener(using: params, on: .any)
		} catch {
			ready(.failure(Failure.couldNotStart(error.localizedDescription)))
			return
		}
		self.listener = listener

		listener.newConnectionHandler = { [weak self] connection in
			self?.accept(connection)
		}
		listener.stateUpdateHandler = { [weak self] state in
			guard let self, !self.didReportReady else { return }
			switch state {
			case .ready:
				self.didReportReady = true
				self.port = listener.port?.rawValue ?? 0
				DispatchQueue.main.async { ready(.success(())) }
			case .failed(let error):
				self.didReportReady = true
				DispatchQueue.main.async { ready(.failure(Failure.couldNotStart(error.localizedDescription))) }
			default:
				break
			}
		}
		listener.start(queue: queue)
	}

	func stop() {
		listener?.cancel()
		listener = nil
	}

	// MARK: - HTTP

	private func accept(_ connection: NWConnection) {
		onEvent?("Incoming connection from \(connection.endpoint)")
		connection.stateUpdateHandler = { [weak self] state in
			switch state {
			case .ready:
				self?.onEvent?("TLS handshake OK")
			case .failed(let error):
				self?.onEvent?("Connection failed: \(error.localizedDescription)")
				connection.cancel()
			case .waiting(let error):
				self?.onEvent?("Connection waiting: \(error.localizedDescription)")
			default:
				break
			}
		}
		connection.start(queue: queue)
		receiveRequest(on: connection, buffer: Data())
	}

	private func receiveRequest(on connection: NWConnection, buffer: Data) {
		connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
			guard let self else { connection.cancel(); return }
			var buffer = buffer
			if let data { buffer.append(data) }

			if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
				self.respond(to: String(decoding: buffer[..<end.lowerBound], as: UTF8.self), on: connection)
			} else if isComplete || error != nil || buffer.count > 65_536 {
				connection.cancel()
			} else {
				self.receiveRequest(on: connection, buffer: buffer)
			}
		}
	}

	private func respond(to head: String, on connection: NWConnection) {
		let lines = head.components(separatedBy: "\r\n")
		let parts = (lines.first ?? "").split(separator: " ")
		guard parts.count >= 2 else { return sendStatus(400, on: connection) }

		let method = String(parts[0])
		let path = String(parts[1].split(separator: "?").first ?? "")
		let headOnly = method == "HEAD"
		var headers: [String: String] = [:]
		for line in lines.dropFirst() {
			if let colon = line.firstIndex(of: ":") {
				headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
			}
		}

		onEvent?("\(method) \(path.hasPrefix("/\(token)/") ? String(path.dropFirst(token.count + 1)) : path)")
		guard path.hasPrefix("/\(token)/") else { return sendStatus(404, on: connection) }

		switch path.dropFirst(token.count + 2) {
		case "manifest.plist":
			sendData(manifest(), type: "text/xml", headOnly: headOnly, on: connection)
		case "app.ipa":
			sendFile(payload.ipaURL, type: "application/octet-stream", range: headers["range"], headOnly: headOnly, track: true, on: connection)
		case "icon.png":
			if let icon = payload.iconURL {
				sendFile(icon, type: "image/png", range: nil, headOnly: headOnly, track: false, on: connection)
			} else {
				sendStatus(404, on: connection)
			}
		default:
			sendStatus(404, on: connection)
		}
	}

	private func manifest() -> Data {
		var assets: [[String: String]] = [["kind": "software-package", "url": "\(baseURL)/app.ipa"]]
		if payload.iconURL != nil {
			assets.append(["kind": "display-image", "url": "\(baseURL)/icon.png"])
			assets.append(["kind": "full-size-image", "url": "\(baseURL)/icon.png"])
		}
		let plist: [String: Any] = [
			"items": [[
				"assets": assets,
				"metadata": [
					"bundle-identifier": payload.bundleID,
					"bundle-version": payload.version,
					"kind": "software",
					"title": payload.title,
				],
			]],
		]
		return (try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)) ?? Data()
	}

	private static func reason(_ status: Int) -> String {
		switch status {
		case 200: return "OK"
		case 206: return "Partial Content"
		case 400: return "Bad Request"
		case 416: return "Range Not Satisfiable"
		default: return "Not Found"
		}
	}

	private func header(status: Int, type: String, length: UInt64, extra: [String] = []) -> Data {
		var lines = [
			"HTTP/1.1 \(status) \(Self.reason(status))",
			"Content-Type: \(type)",
			"Content-Length: \(length)",
			"Accept-Ranges: bytes",
			"Cache-Control: no-store",
			"Connection: close",
		]
		lines += extra
		return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
	}

	private func close(_ connection: NWConnection) {
		connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
			connection.cancel()
		})
	}

	private func sendStatus(_ status: Int, on connection: NWConnection) {
		connection.send(content: header(status: status, type: "text/plain", length: 0), completion: .contentProcessed { _ in })
		close(connection)
	}

	private func sendData(_ data: Data, type: String, headOnly: Bool, on connection: NWConnection) {
		var out = header(status: 200, type: type, length: UInt64(data.count))
		if !headOnly { out.append(data) }
		connection.send(content: out, completion: .contentProcessed { _ in })
		close(connection)
	}

	private func sendFile(_ url: URL, type: String, range: String?, headOnly: Bool, track: Bool, on connection: NWConnection) {
		guard
			let handle = try? FileHandle(forReadingFrom: url),
			let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value,
			size > 0
		else { return sendStatus(404, on: connection) }

		var start: UInt64 = 0
		var end: UInt64 = size - 1
		var status = 200
		if let range, range.hasPrefix("bytes=") {
			let bounds = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
			if bounds.count == 2 {
				if let s = UInt64(bounds[0]) {
					start = s
					if let e = UInt64(bounds[1]) { end = min(e, size - 1) }
				} else if let suffix = UInt64(bounds[1]) {
					start = size - min(suffix, size)
				}
				guard start <= end else {
					try? handle.close()
					return sendStatus(416, on: connection)
				}
				status = 206
			}
		}

		let length = end - start + 1
		var extra: [String] = []
		if status == 206 { extra.append("Content-Range: bytes \(start)-\(end)/\(size)") }
		connection.send(content: header(status: status, type: type, length: length, extra: extra), completion: .contentProcessed { _ in })

		guard !headOnly else {
			try? handle.close()
			return close(connection)
		}

		try? handle.seek(toOffset: start)
		var remaining = length
		let chunkSize: UInt64 = 1 << 20

		func pump() {
			guard remaining > 0 else {
				try? handle.close()
				if track && end == size - 1 { onTransferComplete?() }
				close(connection)
				return
			}
			let chunk = handle.readData(ofLength: Int(min(remaining, chunkSize)))
			guard !chunk.isEmpty else {
				try? handle.close()
				connection.cancel()
				return
			}
			remaining -= UInt64(chunk.count)
			connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
				guard error == nil else {
					try? handle.close()
					connection.cancel()
					return
				}
				if track { self?.onProgress?(Int64(end + 1 - remaining), Int64(size)) }
				pump()
			})
		}
		pump()
	}
}
