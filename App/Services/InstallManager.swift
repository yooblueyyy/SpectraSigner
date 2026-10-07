import AVFoundation
import Foundation
import UIKit

/// Runs an install: starts the local server, hands iOS the itms-services link and tracks the transfer.
@MainActor
final class InstallManager: ObservableObject {
	enum State: Equatable {
		case idle
		case starting
		case waitingForPrompt
		case transferring(Double)
		case installing
		case failed(String)
	}

	@Published private(set) var state: State = .idle
	@Published private(set) var app: LibraryApp?
	@Published var isPresented = false
	/// What happened during the current install, shown in the sheet to troubleshoot a missing prompt.
	@Published private(set) var log: [String] = []

	private var server: InstallServer?
	private var stopWork: DispatchWorkItem?

	var isBusy: Bool {
		switch state {
		case .starting, .waitingForPrompt, .transferring: return true
		default: return false
		}
	}

	func install(_ app: LibraryApp) {
		guard app.kind == .signed else { return }
		cleanup()
		self.app = app
		log = []
		state = .starting
		isPresented = true

		let fm = FileManager.default
		let payload = InstallServer.Payload(
			ipaURL: app.ipaURL,
			iconURL: fm.fileExists(atPath: app.iconURL.path) ? app.iconURL : nil,
			bundleID: app.bundleID,
			version: app.version,
			title: app.name
		)

		let server: InstallServer
		do {
			server = try InstallServer(payload: payload)
		} catch {
			state = .failed(error.localizedDescription)
			return
		}
		self.server = server

		server.onProgress = { [weak self] sent, total in
			Task { @MainActor in
				guard let self, total > 0 else { return }
				self.state = .transferring(Double(sent) / Double(total))
			}
		}
		server.onTransferComplete = { [weak self] in
			Task { @MainActor in self?.transferFinished() }
		}
		server.onEvent = { [weak self] event in
			Task { @MainActor in self?.note(event) }
		}

		KeepAlive.shared.begin()
		server.start { [weak self] result in
			guard let self else { return }
			switch result {
			case .success:
				self.state = .waitingForPrompt
				self.note("Server ready at \(server.host):\(server.port)")
				self.openInstallLink(server.installURL)
			case .failure(let error):
				self.state = .failed(error.localizedDescription)
				self.cleanup()
			}
		}
	}

	/// Re-sends the install prompt, e.g. after the user dismissed it.
	func retryPrompt() {
		guard let server, state == .waitingForPrompt else {
			if let app { install(app) }
			return
		}
		openInstallLink(server.installURL)
	}

	private func openInstallLink(_ url: URL) {
		UIApplication.shared.open(url) { [weak self] opened in
			Task { @MainActor in self?.note(opened ? "Asked iOS to install" : "iOS refused the install link") }
		}
	}

	private func note(_ event: String) {
		log.append(event)
		if log.count > 30 { log.removeFirst(log.count - 30) }
	}

	func dismiss() {
		isPresented = false
		if !isBusy {
			cleanup()
			state = .idle
		}
	}

	func cancel() {
		cleanup()
		state = .idle
		isPresented = false
	}

	private func transferFinished() {
		state = .installing
		// iOS sometimes re-requests the file; keep serving briefly before shutting down.
		let work = DispatchWorkItem { [weak self] in self?.cleanup() }
		stopWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
	}

	private func cleanup() {
		stopWork?.cancel()
		stopWork = nil
		server?.stop()
		server = nil
		KeepAlive.shared.end()
	}
}

/// Keeps the app running in the background while iOS pulls the .ipa from the local server.
@MainActor
final class KeepAlive {
	static let shared = KeepAlive()

	private var task: UIBackgroundTaskIdentifier = .invalid
	private var engine: AVAudioEngine?
	private var player: AVAudioPlayerNode?

	func begin() {
		if task == .invalid {
			task = UIApplication.shared.beginBackgroundTask(withName: "Install") { [weak self] in
				Task { @MainActor in self?.endTask() }
			}
		}
		if UserDefaults.standard.object(forKey: Prefs.keepAliveAudio) as? Bool ?? true {
			startSilentAudio()
		}
	}

	func end() {
		endTask()
		player?.stop()
		engine?.stop()
		player = nil
		engine = nil
		try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
	}

	private func endTask() {
		guard task != .invalid else { return }
		UIApplication.shared.endBackgroundTask(task)
		task = .invalid
	}

	/// A looping silent buffer: iOS keeps apps with active audio alive in the background.
	private func startSilentAudio() {
		guard engine == nil else { return }
		do {
			let session = AVAudioSession.sharedInstance()
			try session.setCategory(.playback, options: [.mixWithOthers])
			try session.setActive(true)

			let engine = AVAudioEngine()
			let player = AVAudioPlayerNode()
			guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2),
				  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)
			else { return }
			buffer.frameLength = buffer.frameCapacity
			if let channels = buffer.floatChannelData {
				for c in 0..<Int(format.channelCount) {
					channels[c].update(repeating: 0, count: Int(buffer.frameLength))
				}
			}
			engine.attach(player)
			engine.connect(player, to: engine.mainMixerNode, format: format)
			engine.mainMixerNode.outputVolume = 0
			try engine.start()
			player.scheduleBuffer(buffer, at: nil, options: .loops)
			player.play()
			self.engine = engine
			self.player = player
		} catch {
			// Not fatal: the background task still gives ~30 seconds.
		}
	}
}
