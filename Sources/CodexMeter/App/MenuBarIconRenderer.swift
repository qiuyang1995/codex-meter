import AppKit
import CodexMeterCore

enum MenuBarIconRenderer {
    static func image(severity: QuotaSeverity, remainingText: String?, showPercent: Bool) -> NSImage {
        let iconSize = NSSize(width: 18, height: 18)
        let mark = drawMark(size: iconSize, severity: severity)

        guard showPercent, let remainingText, remainingText != "—" else {
            mark.isTemplate = severity == .normal || severity == .unknown
            return mark
        }

        let font = NSFont.menuBarFont(ofSize: 12)
        let color: NSColor
        switch severity {
        case .normal, .unknown:
            color = .labelColor
        case .warning:
            color = .systemOrange
        case .severe:
            color = NSColor(red: 0.90, green: 0.42, blue: 0.20, alpha: 1)
        case .danger:
            color = .systemRed
        }

        let text = NSAttributedString(
            string: remainingText,
            attributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
        let textSize = text.size()
        let spacing: CGFloat = 4
        let canvas = NSSize(width: iconSize.width + spacing + ceil(textSize.width), height: 18)
        let composed = NSImage(size: canvas, flipped: false) { _ in
            mark.draw(in: NSRect(x: 0, y: (canvas.height - iconSize.height) / 2, width: iconSize.width, height: iconSize.height))
            text.draw(at: NSPoint(x: iconSize.width + spacing, y: (canvas.height - textSize.height) / 2))
            return true
        }
        composed.isTemplate = severity == .normal || severity == .unknown
        return composed
    }

    static func drawMark(size: NSSize, severity: QuotaSeverity) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 1.2, dy: 1.2)
            let path = NSBezierPath(roundedRect: inset, xRadius: 4, yRadius: 4)
            NSColor.black.setStroke()
            path.lineWidth = 1.2
            path.stroke()

            let glyph = NSAttributedString(
                string: "C",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: NSColor.black
                ]
            )
            let glyphSize = glyph.size()
            glyph.draw(at: NSPoint(
                x: rect.midX - glyphSize.width / 2,
                y: rect.midY - glyphSize.height / 2 - 0.5
            ))
            return true
        }
        image.isTemplate = true
        return image
    }
}
