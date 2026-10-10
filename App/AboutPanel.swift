import AppKit

@MainActor
enum AboutPanel {
    private static let repoURL = URL(string: "https://github.com/ekremus/shycloud")!

    static func show() {
        NSApp.activate()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString(
            string: String(localized: "Pause iCloud Drive sync on a schedule.")
                + "\nGPL-3.0-or-later · ",
            attributes: attributes
        )
        var linkAttributes = attributes
        linkAttributes[.link] = repoURL
        credits.append(NSAttributedString(string: "github.com/ekremus/shycloud", attributes: linkAttributes))
        if let noticesURL = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt") {
            var noticeAttributes = attributes
            noticeAttributes[.link] = noticesURL
            credits.append(NSAttributedString(string: "\n", attributes: attributes))
            credits.append(NSAttributedString(string: String(localized: "Third-Party Licenses"), attributes: noticeAttributes))
        }
        credits.append(NSAttributedString(string: "\n" + String(localized: "Includes Sparkle (MIT license)."), attributes: attributes))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
