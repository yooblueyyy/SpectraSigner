import SwiftUI

struct InstallSheet: View {
	@EnvironmentObject private var installer: InstallManager

	var body: some View {
		VStack(spacing: 18) {
			if let app = installer.app {
				AppIconView(url: app.iconURL, size: 72)
				Text(app.name).font(.title3.weight(.semibold))
			}

			status

			Spacer(minLength: 0)

			buttons
		}
		.padding(24)
		.frame(maxWidth: .infinity)
	}

	@ViewBuilder
	private var status: some View {
		switch installer.state {
		case .idle, .starting:
			ProgressView("Starting install server…")
		case .waitingForPrompt:
			VStack(spacing: 6) {
				ProgressView()
				Text("Tap **Install** on the prompt to continue.")
					.font(.subheadline)
					.multilineTextAlignment(.center)
			}
		case .transferring(let fraction):
			VStack(spacing: 8) {
				ProgressView(value: fraction)
				Text("Sending to iOS… \(Int(fraction * 100))%")
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
		case .installing:
			VStack(spacing: 6) {
				Image(systemName: "checkmark.circle.fill")
					.font(.system(size: 36))
					.foregroundStyle(.green)
				Text("Installing — check your Home Screen.")
					.font(.subheadline)
					.multilineTextAlignment(.center)
			}
		case .failed(let message):
			VStack(spacing: 6) {
				Image(systemName: "exclamationmark.triangle.fill")
					.font(.system(size: 32))
					.foregroundStyle(.orange)
				Text(message)
					.font(.footnote)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
			}
		}
	}

	@ViewBuilder
	private var buttons: some View {
		switch installer.state {
		case .waitingForPrompt:
			HStack {
				Button("Cancel", role: .cancel) { installer.cancel() }
					.buttonStyle(.bordered)
				Button("Show Prompt Again") { installer.retryPrompt() }
					.buttonStyle(.borderedProminent)
			}
		case .failed:
			HStack {
				Button("Close") { installer.cancel() }
					.buttonStyle(.bordered)
				if let app = installer.app {
					ShareLink(item: app.ipaURL, preview: SharePreview(app.shareFileName)) {
						Text("Share IPA")
					}
					.buttonStyle(.borderedProminent)
				}
			}
		case .installing:
			Button("Done") { installer.dismiss() }
				.buttonStyle(.borderedProminent)
		default:
			Button("Cancel", role: .cancel) { installer.cancel() }
				.buttonStyle(.bordered)
		}
	}
}
