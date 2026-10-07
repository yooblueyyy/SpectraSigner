import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct SignView: View {
	let app: LibraryApp

	@EnvironmentObject private var library: LibraryStore
	@EnvironmentObject private var certificates: CertificateStore
	@EnvironmentObject private var installer: InstallManager
	@EnvironmentObject private var router: AppRouter
	@Environment(\.dismiss) private var dismiss

	@State private var options = SignOptions.defaults
	@State private var certificateID: UUID?
	@State private var photo: PhotosPickerItem?
	@State private var customIcon: UIImage?
	@State private var dylibs: [URL] = []
	@State private var showDylibPicker = false
	@State private var stage: String?
	@State private var errorMessage: String?

	private var certificate: SigningCertificate? {
		certificates.certificates.first { $0.id == certificateID }
	}

	private var canSign: Bool { stage == nil && (options.adhoc || certificate != nil) }

	var body: some View {
		NavigationStack {
			Form {
				Section {
					HStack(spacing: 16) {
						PhotosPicker(selection: $photo, matching: .images) {
							ZStack(alignment: .bottomTrailing) {
								if let customIcon {
									Image(uiImage: customIcon)
										.resizable()
										.scaledToFill()
										.frame(width: 76, height: 76)
										.clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
								} else {
									AppIconView(url: app.iconURL, size: 76)
								}
								Image(systemName: "pencil.circle.fill")
									.symbolRenderingMode(.multicolor)
									.font(.title3)
									.background(Circle().fill(Color(.systemBackground)))
									.offset(x: 6, y: 6)
							}
						}
						.buttonStyle(.plain)

						VStack(alignment: .leading, spacing: 4) {
							TextField("App Name", text: $options.name)
								.font(.title3.weight(.bold))
							Text("\(app.version) · \(app.bundleID)")
								.font(.caption)
								.foregroundStyle(.secondary)
								.lineLimit(1)
						}
					}
					.padding(.vertical, 4)
					if customIcon != nil {
						Button("Use Original Icon", role: .destructive) {
							customIcon = nil
							photo = nil
						}
					}
				}

				Section("Identity") {
					LabeledField(title: "Bundle ID", text: $options.bundleID, placeholder: app.bundleID)
					LabeledField(title: "Version", text: $options.version, placeholder: app.version)
					LabeledField(title: "Minimum iOS", text: $options.minimumOS, placeholder: app.minimumOS ?? "Unchanged")
				}

				Section {
					Toggle("Ad-hoc Signing", isOn: $options.adhoc)
					if !options.adhoc {
						if certificates.certificates.isEmpty {
							Button("Add a Certificate in Settings") {
								dismiss()
								router.tab = .settings
							}
						} else {
							Picker("Certificate", selection: $certificateID) {
								ForEach(certificates.certificates) { cert in
									Text(cert.displayName).tag(Optional(cert.id))
								}
							}
							if let certificate {
								CertificateSummary(certificate: certificate)
								if !certificate.isWildcard {
									Label("This profile is for a specific App ID. The bundle ID will be changed to match it.", systemImage: "info.circle")
										.font(.caption)
										.foregroundStyle(.secondary)
								}
							}
						}
					}
				} header: {
					Text("Signing")
				} footer: {
					if options.adhoc {
						Text("Ad-hoc signed apps only run on jailbroken devices or with TrollStore.")
					}
				}

				Section("Modify") {
					Toggle("Enable File Sharing", isOn: $options.fileSharing)
					Toggle("Remove Device Restrictions", isOn: $options.removeSupportedDevices)
					Toggle("Remove App Extensions", isOn: $options.removeExtensions)
					Toggle("Remove Watch App", isOn: $options.removeWatchApp)
				}

				Section {
					ForEach(dylibs, id: \.self) { url in
						Label(url.lastPathComponent, systemImage: "puzzlepiece.extension")
					}
					.onDelete { dylibs.remove(atOffsets: $0) }
					Button { showDylibPicker = true } label: {
						Label("Add .dylib", systemImage: "plus")
					}
					if !dylibs.isEmpty {
						Toggle("Weak Load", isOn: $options.weakInject)
					}
				} header: {
					Text("Inject")
				} footer: {
					Text("Tweaks that depend on Cydia Substrate or ElleKit need that framework injected too.")
				}

				Section {
					Toggle("Install After Signing", isOn: $options.installAfterSigning)
					Toggle("Delete Unsigned Copy", isOn: $options.deleteUnsignedAfterSigning)
				}
			}
			.spectraBackground()
			.disabled(stage != nil)
			.safeAreaInset(edge: .bottom) {
				Button {
					sign()
				} label: {
					Label(options.installAfterSigning ? "Sign & Install" : "Sign", systemImage: "signature")
				}
				.buttonStyle(SpectraButtonStyle())
				.disabled(!canSign)
				.opacity(canSign ? 1 : 0.5)
				.padding(.horizontal, 20)
				.padding(.top, 10)
				.padding(.bottom, 6)
				.background(.bar)
			}
			.navigationTitle("Sign")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }.disabled(stage != nil)
				}
			}
			.overlay {
				if let stage {
					SigningOverlay(stage: stage)
				}
			}
			.fileImporter(isPresented: $showDylibPicker, allowedContentTypes: [.dylib, .data], allowsMultipleSelection: true) { result in
				guard case .success(let urls) = result else { return }
				for url in urls where url.pathExtension.lowercased() == "dylib" {
					if let copy = copyToTemp(url) { dylibs.append(copy) }
				}
			}
			.onChange(of: photo) { item in
				Task {
					guard
						let data = try? await item?.loadTransferable(type: Data.self),
						let image = UIImage(data: data)
					else { return }
					customIcon = image.squared(to: 1024)
				}
			}
			.alert("Signing Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
				Button("OK", role: .cancel) {}
			} message: {
				Text(errorMessage ?? "")
			}
			.onAppear {
				if options.name.isEmpty { options.name = app.name }
				if certificateID == nil { certificateID = certificates.selected?.id }
			}
		}
		.interactiveDismissDisabled(stage != nil)
	}

	private func copyToTemp(_ url: URL) -> URL? {
		let scoped = url.startAccessingSecurityScopedResource()
		defer { if scoped { url.stopAccessingSecurityScopedResource() } }
		guard let dir = try? Paths.makeTemp("dylib") else { return nil }
		let dest = dir.appendingPathComponent(url.lastPathComponent)
		return (try? FileManager.default.copyItem(at: url, to: dest)) != nil ? dest : nil
	}

	private func sign() {
		var options = options
		if !options.adhoc, let certificate, !certificate.isWildcard, options.bundleID.isEmpty {
			// A non-wildcard profile only works for its exact App ID.
			let appID = certificate.applicationIdentifier
			if let dot = appID.firstIndex(of: ".") {
				options.bundleID = String(appID[appID.index(after: dot)...])
			}
		}

		let request = SignRequest(
			app: app,
			certificate: options.adhoc ? nil : certificate,
			password: certificate.map(PasswordVault.get(for:)) ?? "",
			options: options,
			icon: customIcon,
			dylibs: dylibs
		)
		stage = "Preparing"

		Task {
			do {
				let signed = try await SigningService.sign(request) { stage = $0 }
				library.add(signed)
				if options.deleteUnsignedAfterSigning { library.delete(app) }
				stage = nil
				dismiss()
				if options.installAfterSigning {
					try? await Task.sleep(nanoseconds: 400_000_000)
					installer.install(signed)
				}
			} catch {
				stage = nil
				errorMessage = error.localizedDescription
			}
		}
	}
}

private struct LabeledField: View {
	var title: String
	@Binding var text: String
	var placeholder: String

	var body: some View {
		HStack {
			Text(title)
			Spacer()
			TextField(placeholder, text: $text)
				.multilineTextAlignment(.trailing)
				.foregroundStyle(.secondary)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
		}
	}
}

struct CertificateSummary: View {
	let certificate: SigningCertificate

	var body: some View {
		VStack(alignment: .leading, spacing: 3) {
			Text(certificate.name).font(.caption).lineLimit(1)
			Text(certificate.expiration.expiryDescription)
				.font(.caption2)
				.foregroundStyle(certificate.expiration.expiryColor)
		}
	}
}

private struct SigningOverlay: View {
	let stage: String

	var body: some View {
		ZStack {
			Color.black.opacity(0.25).ignoresSafeArea()
			VStack(spacing: 14) {
				ProgressView().controlSize(.large)
				Text("\(stage)…").font(.headline)
			}
			.padding(28)
			.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
		}
	}
}
