import SwiftUI
import UniformTypeIdentifiers

struct CertificatesView: View {
	@EnvironmentObject private var certificates: CertificateStore
	@EnvironmentObject private var router: AppRouter

	@State private var adding: AppRouter.PendingCertificate?

	var body: some View {
		List {
			Section {
				ForEach(certificates.certificates) { cert in
					HStack(spacing: 12) {
						Button {
							certificates.selectedID = cert.id
						} label: {
							Image(systemName: certificates.selected?.id == cert.id ? "checkmark.circle.fill" : "circle")
								.font(.title3)
								.foregroundStyle(certificates.selected?.id == cert.id ? Color.accentColor : .secondary)
						}
						.buttonStyle(.plain)

						NavigationLink {
							CertificateDetailView(certificate: cert)
						} label: {
							CertificateRow(certificate: cert)
						}
					}
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
	@State private var picking: PickTarget?
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
					fileRow(title: "Certificate", detail: p12?.lastPathComponent, icon: "key.fill") { picking = .p12 }
					fileRow(title: "Provisioning Profile", detail: profile?.lastPathComponent, icon: "doc.badge.gearshape.fill") { picking = .profile }
				} header: {
					Text("Files")
				} footer: {
					Text("A .p12 (or .pfx) certificate with its private key, and the .mobileprovision made for it.")
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
			.fileImporter(
				isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
				allowedContentTypes: picking == .profile ? [.mobileProvision, .data] : [.pkcs12, .data]
			) { result in
				guard case .success(let url) = result else { return }
				let target = picking
				picking = nil
				if target == .profile { profile = url } else { p12 = url }
			}
		}
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
