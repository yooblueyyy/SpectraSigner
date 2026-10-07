import SwiftUI
import UniformTypeIdentifiers

struct CertificatesView: View {
	@EnvironmentObject private var certificates: CertificateStore
	@EnvironmentObject private var router: AppRouter

	@State private var adding: AppRouter.PendingCertificate?
	@State private var inspecting: SigningCertificate?

	var body: some View {
		List {
			Section {
				ForEach(certificates.certificates) { cert in
					let isSelected = certificates.selected?.id == cert.id
					// Tapping the row makes it the default; the ⓘ button opens details.
					Button {
						certificates.selectedID = cert.id
						UISelectionFeedbackGenerator().selectionChanged()
					} label: {
						HStack(spacing: 12) {
							Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
								.font(.title3)
								.foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
							CertificateRow(certificate: cert)
							Spacer(minLength: 0)
							Button {
								inspecting = cert
							} label: {
								Image(systemName: "info.circle")
									.font(.title3)
									.foregroundStyle(Color.accentColor)
							}
							.buttonStyle(.borderless)
						}
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					.cardRow()
				}
				.onDelete { offsets in
					offsets.map { certificates.certificates[$0] }.forEach(certificates.delete)
				}
			} footer: {
				if !certificates.certificates.isEmpty {
					Text("The checked certificate is used by default when signing.")
				}
			}
		}
		.overlay {
			if certificates.certificates.isEmpty {
				EmptyStateView(
					title: "No Certificates",
					systemImage: "checkmark.seal",
					message: "Import a .p12 certificate and its .mobileprovision profile to sign apps."
				)
			}
		}
		.spectraBackground()
		.navigationTitle("Certificates")
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button { adding = .init() } label: { Image(systemName: "plus") }
			}
		}
		.sheet(item: $adding) { pending in
			AddCertificateView(p12: pending.p12, profile: pending.profile)
		}
		.sheet(item: $inspecting) { cert in
			NavigationStack {
				CertificateDetailView(certificate: cert)
					.toolbar {
						ToolbarItem(placement: .confirmationAction) {
							Button("Done") { inspecting = nil }
						}
					}
			}
		}
		.onAppear(perform: consumePending)
		.onChange(of: router.pendingCertificate?.id) { _ in consumePending() }
	}

	private func consumePending() {
		guard let pending = router.pendingCertificate else { return }
		router.pendingCertificate = nil
		adding = pending
	}
}

private struct CertificateRow: View {
	let certificate: SigningCertificate

	var body: some View {
		VStack(alignment: .leading, spacing: 3) {
			HStack(spacing: 6) {
				Text(certificate.displayName).font(.body.weight(.semibold)).lineLimit(1)
				if certificate.isEnterprise { Pill(text: "Enterprise", color: .blue) }
			}
			Text(certificate.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
			Text(certificate.expiration.expiryDescription)
				.font(.caption2)
				.foregroundStyle(certificate.expiration.expiryColor)
		}
		.padding(.vertical, 2)
	}
}

struct AddCertificateView: View {
	@EnvironmentObject private var certificates: CertificateStore
	@Environment(\.dismiss) private var dismiss

	@State private var p12: URL?
	@State private var profile: URL?
	@State private var password = ""
	@State private var nickname = ""
	@State private var showPicker = false
	@State private var pickTarget: PickTarget = .p12
	@State private var working = false
	@State private var error: String?

	private enum PickTarget { case p12, profile }

	init(p12: URL? = nil, profile: URL? = nil) {
		_p12 = State(initialValue: p12)
		_profile = State(initialValue: profile)
	}

	var body: some View {
		NavigationStack {
			Form {
				Section {
					fileRow(title: "Certificate", detail: p12?.lastPathComponent, icon: "key.fill") { pick(.p12) }
					fileRow(title: "Provisioning Profile", detail: profile?.lastPathComponent, icon: "doc.badge.gearshape.fill") { pick(.profile) }
				} header: {
					Text("Files")
				} footer: {
					Text("A .p12 (or .pfx) certificate with its private key, and the .mobileprovision made for it. You can select both files at once.")
				}

				Section("Password") {
					SecureField("Certificate password", text: $password)
				}

				Section {
					TextField("Optional", text: $nickname)
				} header: {
					Text("Nickname")
				}

				if let error {
					Section {
						Label(error, systemImage: "exclamationmark.triangle.fill")
							.foregroundStyle(.red)
							.font(.footnote)
					}
				}
			}
			.spectraBackground()
			.disabled(working)
			.navigationTitle("Add Certificate")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					if working {
						ProgressView()
					} else {
						Button("Import") { save() }
							.fontWeight(.semibold)
							.disabled(p12 == nil || profile == nil)
					}
				}
			}
			.sheet(isPresented: $showPicker) {
				DocumentPicker(types: Self.certificateTypes) { urls in
					showPicker = false
					receive(urls)
				}
				.ignoresSafeArea()
			}
		}
	}

	/// .p12/.pfx and .mobileprovision, including whatever type iOS resolves those extensions to,
	/// so they're selectable even when no other app has declared them.
	private static let certificateTypes: [UTType] = {
		var types: [UTType] = [.pkcs12, .mobileProvision]
		for ext in ["p12", "pfx", "mobileprovision"] {
			if let type = UTType(filenameExtension: ext), !types.contains(type) { types.append(type) }
		}
		return types
	}()

	private func pick(_ target: PickTarget) {
		pickTarget = target
		showPicker = true
	}

	/// Copies picked files into the app right away (while access is granted) and slots them
	/// by extension, so the certificate and profile can be chosen together.
	private func receive(_ urls: [URL]) {
		error = nil
		for url in urls {
			let ext = url.pathExtension.lowercased()
			guard ["p12", "pfx", "mobileprovision"].contains(ext) else {
				error = "\(url.lastPathComponent) isn't a certificate (.p12) or provisioning profile (.mobileprovision)."
				continue
			}
			guard let local = copyToTemp(url) else {
				error = "Couldn't read \(url.lastPathComponent)."
				continue
			}
			if ext == "mobileprovision" { profile = local } else { p12 = local }
		}
	}

	private func copyToTemp(_ url: URL) -> URL? {
		let scoped = url.startAccessingSecurityScopedResource()
		defer { if scoped { url.stopAccessingSecurityScopedResource() } }
		guard let dir = try? Paths.makeTemp("cert") else { return nil }
		let dest = dir.appendingPathComponent(url.lastPathComponent)
		if (try? FileManager.default.copyItem(at: url, to: dest)) != nil { return dest }

		// Cloud-backed providers (iCloud Drive, Google Drive…) may need a coordinated read.
		var coordinatorError: NSError?
		var copied: URL?
		NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatorError) { readable in
			if (try? FileManager.default.copyItem(at: readable, to: dest)) != nil { copied = dest }
		}
		return copied
	}

	private func fileRow(title: String, detail: String?, icon: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			HStack {
				Label(title, systemImage: icon).foregroundStyle(.primary)
				Spacer()
				Text(detail ?? "Choose…")
					.foregroundStyle(detail == nil ? Color.accentColor : .secondary)
					.lineLimit(1)
					.truncationMode(.middle)
			}
		}
	}

	private func save() {
		guard let p12, let profile else { return }
		working = true
		error = nil
		Task {
			do {
				try await certificates.add(p12: p12, profile: profile, password: password, nickname: nickname.isEmpty ? nil : nickname)
				dismiss()
			} catch {
				self.error = error.localizedDescription
			}
			working = false
		}
	}
}

struct CertificateDetailView: View {
	let certificate: SigningCertificate

	@EnvironmentObject private var certificates: CertificateStore
	@Environment(\.dismiss) private var dismiss

	@State private var nickname = ""
	@State private var confirmDelete = false

	var body: some View {
		List {
			Section("Nickname") {
				TextField(certificate.teamName, text: $nickname)
					.onSubmit { certificates.rename(certificate, to: nickname) }
			}

			Section("Certificate") {
				LabeledContent("Name", value: certificate.name)
				LabeledContent("Team", value: certificate.teamName)
				LabeledContent("Team ID", value: certificate.teamID)
				LabeledContent("Type", value: certificate.isEnterprise ? "Enterprise" : "Development / Ad Hoc")
				LabeledContent("Expires") {
					Text(certificate.expiration.formatted(date: .abbreviated, time: .shortened))
						.foregroundStyle(certificate.expiration.expiryColor)
				}
			}

			Section("Provisioning Profile") {
				LabeledContent("Name", value: certificate.profileName)
				LabeledContent("App ID", value: certificate.applicationIdentifier)
				if !certificate.appIDName.isEmpty { LabeledContent("App ID Name", value: certificate.appIDName) }
				LabeledContent("Created", value: certificate.created.formatted(date: .abbreviated, time: .omitted))
				if !certificate.isEnterprise { LabeledContent("Devices", value: "\(certificate.deviceCount)") }
			}

			if !certificate.entitlementKeys.isEmpty {
				Section("Entitlements") {
					ForEach(certificate.entitlementKeys, id: \.self) { key in
						Text(key).font(.caption.monospaced())
					}
				}
			}

			Section {
				Button("Use by Default") { certificates.selectedID = certificate.id }
					.disabled(certificates.selected?.id == certificate.id)
				Button("Delete Certificate", role: .destructive) { confirmDelete = true }
			}
		}
		.spectraBackground()
		.navigationTitle(certificate.displayName)
		.navigationBarTitleDisplayMode(.inline)
		.onAppear { nickname = certificate.nickname ?? "" }
		.onDisappear {
			if nickname != (certificate.nickname ?? "") { certificates.rename(certificate, to: nickname) }
		}
		.confirmationDialog("Delete this certificate?", isPresented: $confirmDelete, titleVisibility: .visible) {
			Button("Delete", role: .destructive) {
				certificates.delete(certificate)
				dismiss()
			}
		}
	}
}
