import Foundation
import Network

/// A tiny HTTP server on the device that serves the signed .ipa, so iOS can install it
/// through an `itms-services://` link.
///
/// iOS only accepts the install manifest over HTTPS with a publicly trusted certificate, which
/// a server on the phone can't have (a shared certificate for localhost gets revoked as soon as
/// its key is published). So the manifest comes from a small web service (spectra-manifest/),
/// and only the .ipa, which iOS will fetch over plain HTTP, is served from here on 127.0.0.1.
final class InstallServer {
	struct Payload {
		let ipaURL: URL
		let iconURL: URL?
		let bundleID: String
		let version: String
		let title: String
	}

	enum Failure: LocalizedError {
		case badManifestService, couldNotStart(String)

		var errorDescription: String? {
			switch self {
			case .badManifestService:
				return "The manifest service address in Settings → Installation isn't a valid https:// URL."
			case .couldNotStart(let reason):
				return "The local install server couldn't start: \(reason)"
			}
		}
	}

	/// Where install manifests come from unless changed in Settings → Installation.
	static let defaultManifestService = "https://spectra-manifest.vercel.app"

	static var manifestService: String {
		let custom = UserDefaults.standard.string(forKey: Prefs.manifestService)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		return custom.isEmpty ? defaultManifestService : custom
	}

	private let payload: Payload
	private let service: URL
	let host = "127.0.0.1"
	private let token = UUID().uuidString.lowercased()
	private var listener: NWListener?
	private let queue = DispatchQueue(label: "dev.spectra.install-server")
	private var didReportReady = false

	/// Bytes of the .ipa sent so far, and its total size.
	var onProgress: ((Int64, Int64) -> Void)?
	/// Called once the whole .ipa has been delivered to iOS.
	var onTransferComplete: (() -> Void)?
	/// Human-readable events (connections, requests) for troubleshooting.
	var onEvent: ((String) -> Void)?

	init(payload: Payload) throws {
		var base = Self.manifestService
		while base.hasSuffix("/") { base.removeLast() }
		guard let service = URL(string: base), service.scheme == "https", service.host != nil else {
			throw Failure.badManifestService
		}
		self.payload = payload
		self.service = service
	}

	private(set) var port: UInt16 = 0
	private var baseURL: String { "http://\(host):\(port)/\(token)" }
	var ipaURL: URL { URL(string: "\(baseURL)/app.ipa")! }

	var manifestURL: URL {
		var components = URLComponents(url: service.appendingPathComponent("api/manifest"), resolvingAgainstBaseURL: false)!
		var items = [
			URLQueryItem(name: "ipa", value: ipaURL.absoluteString),
			URLQueryItem(name: "bundle", value: payload.bundleID),
			URLQueryItem(name: "version", value: payload.version),
			URLQueryItem(name: "title", value: payload.title),
		]
		if payload.iconURL != nil {
			items.append(URLQueryItem(name: "icon", value: "\(baseURL)/icon.png"))
		}
		components.queryItems = items
		// URLQueryItem leaves "+" alone, which servers read as a space.
		components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
		return components.url!
	}

	/// The link that asks iOS to install the app. The manifest URL has its own query string, so it's
	/// encoded as a single parameter value.
	var installURL: URL {
		var unreserved = CharacterSet.alphanumerics
		unreserved.insert(charactersIn: "-._~")
		let encoded = manifestURL.absoluteString.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
		return URL(string: "itms-services://?action=download-manifest&url=\(encoded)")!
	}

	func start(ready: @escaping (Result<Void, Error>) -> Void) {
		let params = NWParameters.tcp
		params.allowLocalEndpointReuse = true
		// Only reachable from this device, not from the rest of the network.
		params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)

		let listener: NWListener
		do {
			listener = try NWListener(using: params)
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
		connection.stateUpdateHandler = { [weak self] state in
			if case .failed(let error) = state {
				self?.onEvent?("Connection failed: \(error.localizedDescription)")
				connection.cancel()
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
