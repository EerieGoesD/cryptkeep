import SwiftUI

/// The picker shown when filling a login. Colours match the app's dark theme
/// (see lib/screens/autofill/autofill_screen.dart, which is the Android
/// equivalent of this screen).
struct CredentialListView: View {
    let entries: [VaultEntry]
    let host: String?
    let accountEmail: String?
    let onPick: (VaultEntry) -> Void
    let onCancel: () -> Void

    @State private var query = ""

    private var matching: [VaultEntry] {
        guard let host else { return [] }
        return filtered.filter { $0.matches(host: host) }
    }

    private var others: [VaultEntry] {
        guard let host else { return filtered }
        return filtered.filter { !$0.matches(host: host) }
    }

    /// Passkeys are left out: this list fills a username and password, and a
    /// passkey has neither. iOS offers passkeys through its own sheet.
    private var filtered: [VaultEntry] {
        let usable = entries.filter { !$0.isPasskey }
        guard !query.isEmpty else { return usable }
        let needle = query.lowercased()
        return usable.filter {
            $0.title.lowercased().contains(needle)
                || $0.username.lowercased().contains(needle)
                || $0.url.lowercased().contains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !matching.isEmpty {
                    Section("For this site") {
                        ForEach(matching, id: \.id) { row($0) }
                    }
                }
                if !others.isEmpty {
                    Section(matching.isEmpty ? "All entries" : "Everything else") {
                        ForEach(others, id: \.id) { row($0) }
                    }
                }
                if matching.isEmpty && others.isEmpty {
                    Text("Nothing matches that.")
                        .foregroundStyle(.secondary)
                }
            }
            .searchable(text: $query, prompt: "Search vault")
            .navigationTitle("CryptKeep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                if let accountEmail {
                    ToolbarItem(placement: .status) {
                        Text(accountEmail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Color(red: 0.545, green: 0.361, blue: 0.965))  // 0xFF8B5CF6
    }

    private func row(_ entry: VaultEntry) -> some View {
        Button {
            onPick(entry)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? "(no title)" : entry.title)
                    .fontWeight(.semibold)
                if !entry.username.isEmpty {
                    Text(entry.username)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Shown when there is nothing to offer, with the reason. Better than an empty
/// list the user cannot explain.
struct MessageView: View {
    let message: String
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("CryptKeep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onCancel)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
