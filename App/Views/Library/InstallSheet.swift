import SwiftUI

struct InstallSheet: View {
	@EnvironmentObject private var installer: InstallManager

	private var progress: Double? {
		switch installer.state {
		case .transferring(let fraction): return fraction
		case .installing: return 1
		default: return nil
		}
	}

	private var isFailed: Bool {
		if case .failed = installer.state { return true }
		return false
	}

	var body: some View {
		VStack(spacing: 18) {
			ZStack {
				if isFailed {
					Circle().stroke(Color.orange.opacity(0.3), lineWidth: 8).frame(width: 120, height: 120)
				} else {
					SpectraRing(progress: progress, size: 120, lineWidth: 8) { EmptyView() }
				}
				AppIconView(url: installer.app?.iconURL, size: 80)
				if case .installing = installer.state {
					Image(systemName: "checkmark.circle.fill")
						.font(.system(size: 30))
						.foregroundStyle(.white, .green)
						.offset(x: 42, y: 42)
						.transition(.scale.combined(with: .opacity))
				}
			}
			.animation(.spring(response: 0.4), value: installer.state)

			VStack(spacing: 6) {
				Text(installer.app?.name ?? "Install").font(.title3.weight(.bold))
				status
			}

			Spacer(minLength: 0)

			buttons
		}
		.padding(24)
		.frame(maxWidth: .infinity)
		.background(AuroraBackground())
	}

	@ViewBuilder
	private var status: some View {
		switch installer.state {
		case .idle, .starting:
			Text("Starting install server…").font(.subheadline).foregroundStyle(.secondary)
		case .waitingForPrompt:
			Text("Tap **Install** on the prompt to continue.").font(.subheadline).foregroundStyle(.secondary)
		case .transferring(let fraction):
			Text("Sending to iOS · \(Int(fraction * 100))%").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
		case .installing:
			Text("Installing — check your Home Screen.").font(.subheadline).foregroundStyle(.secondary)
		case .failed(let message):
			Text(message)
				.font(.footnote)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
		}
	}

	@ViewBuilder
	private var buttons: some View {
		switch installer.state {
		case .waitingForPrompt:
			VStack(spacing: 10) {
				Button("Show Prompt Again") { installer.retryPrompt() }
					.buttonStyle(SpectraButtonStyle())
				Button("Cancel", role: .cancel) { installer.cancel() }
					.font(.subheadline.weight(.semibold))
			}
		case .failed:
			VStack(spacing: 10) {
				if let app = installer.app {
					ShareLink(item: app.ipaURL, preview: SharePreview(app.shareFileName)) {
						Text("Share IPA Instead")
					}
					.buttonStyle(SpectraButtonStyle(tint: .orange))
				}
				Button("Close") { installer.cancel() }
					.font(.subheadline.weight(.semibold))
			}
		case .installing:
			Button("Done") { installer.dismiss() }
				.buttonStyle(SpectraButtonStyle(tint: .green))
		default:
			Button("Cancel", role: .cancel) { installer.cancel() }
				.font(.subheadline.weight(.semibold))
		}
	}
}
