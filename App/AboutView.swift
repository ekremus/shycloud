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
            Image("Logo")
                .resizable()
                .frame(width: 134, height: 100)
                .accessibilityHidden(true)

            Text(verbatim: "shyCloud")
                .font(.custom("Jaro", size: 30, relativeTo: .title2))
                // The logo image keeps transparent room below for its shadow, so pull the name up into it.
                .padding(.top, -6)

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

            VStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.open(Self.repoURL)
                } label: {
                    Label("Star on GitHub", systemImage: "star.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CallToActionButtonStyle())
                .keyboardShortcut(.defaultAction)

                if let noticesURL = Self.noticesURL {
                    Button {
                        NSWorkspace.shared.open(noticesURL)
                    } label: {
                        Text("Third-Party Licenses")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .frame(width: 210)
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

/// Filled brand-blue capsule. Unlike `.borderedProminent` it stays blue when the window is inactive,
/// so the star request always reads as the main action.
private struct CallToActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 7)
            .background(
                LinearGradient(colors: [Color(red: 0.12, green: 0.65, blue: 1), Color(red: 0, green: 0.4, blue: 1)],
                               startPoint: .top, endPoint: .bottom),
                in: Capsule()
            )
            .shadow(color: Color(red: 0, green: 0.3, blue: 0.8).opacity(0.25), radius: 3, y: 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}
