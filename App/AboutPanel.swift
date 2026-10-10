import AppKit

@MainActor
enum AboutPanel {
    static func show() {
        NSApp.activate()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = String(localized: "Pause iCloud Drive sync on a schedule.\nNot affiliated with Apple. iCloud is a trademark of Apple Inc.")
            + "\nGPL-3.0-or-later · github.com/ekremus/shycloud"
        let credits = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
