import AppKit
import SwiftUI

/// About window content (spec §3.4). Fixed size; uses the default window background.
struct AboutView: View {
    private static let repoURL = URL(string: "https://github.com/ekremus/shycloud")!
    private static let noticesURL = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt")

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            Text(verbatim: "ShyCloud")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 12)

            Text("Version \(version) (build \(build))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)

            Text("Pause iCloud Drive sync on a schedule.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 16)

            HStack(spacing: 16) {
                Button(String(localized: "GitHub")) {
                    NSWorkspace.shared.open(Self.repoURL)
                }
                if let noticesURL = Self.noticesURL {
                    Button(String(localized: "Third-Party Licenses")) {
                        NSWorkspace.shared.open(noticesURL)
                    }
                }
            }
            .buttonStyle(.link)
            .padding(.top, 20)

            Text("Free and open source · GPL-3.0")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 20)
        }
        .padding(.horizontal, 24)
        // Fixed size, equal to the window's content size: never let content and window size each other.
        .frame(width: 300, height: 360)
    }
}
