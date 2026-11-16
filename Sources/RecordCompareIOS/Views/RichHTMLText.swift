import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

struct RichHTMLText: UIViewRepresentable {
    let html: String
    var fontSize: CGFloat = 14
    var textColor: UIColor = .label
    var alignment: NSTextAlignment = .natural

    static func unitBadgeMarker(for unit: String) -> String {
        let payload = Data(unit.utf8).base64EncodedString()
        return "<span data-rc-unit-badge=\"\(payload)\"></span>"
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.attributedText = Self.attributedContent(
            from: html,
            fontSize: fontSize,
            textColor: textColor,
            alignment: alignment
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    private static func attributedContent(
        from html: String,
        fontSize: CGFloat,
        textColor: UIColor,
        alignment: NSTextAlignment
    ) -> NSAttributedString {
        let normalizedHTML = html
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
        let (htmlWithoutBadges, unitBadges) = Self.extractUnitBadges(from: normalizedHTML)
        let containsMarkup = htmlWithoutBadges.range(
            of: #"</?[A-Za-z][^>]*>"#,
            options: .regularExpression
        ) != nil
        let contentHTML = containsMarkup
            ? htmlWithoutBadges.replacingOccurrences(
                of: #"(?<=[^>])\n(?=[^<])"#,
                with: "<br>",
                options: .regularExpression
            )
            : htmlWithoutBadges.replacingOccurrences(of: "\n", with: "<br>")
        let cleanHTML = contentHTML
            .replacingOccurrences(of: #"(?is)<script\b[^>]*>.*?</script>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<(iframe|object|embed)\b[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<(img|figure)\b[^>]*>.*?</figure>|<img\b[^>]*>"#, with: "", options: .regularExpression)
        let document = """
        <!doctype html><html><body style="font-family:-apple-system; font-size:\(fontSize)px; color:#\(textColor.hexRGB); margin:0;">
        \(cleanHTML)
        </body></html>
        """
        let fallback = cleanHTML
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</(p|div|li|h[1-6])>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
        let parsed = (try? NSAttributedString(
            data: Data(document.utf8),
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )) ?? NSAttributedString(string: fallback)
        let result = NSMutableAttributedString(attributedString: parsed)
        for badge in unitBadges {
            let range = (result.string as NSString).range(of: badge.marker)
            guard range.location != NSNotFound else { continue }
            result.replaceCharacters(in: range, with: NSAttributedString(attachment: Self.unitBadgeAttachment(for: badge.unit)))
        }
        let fullRange = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let oldFont = value as? UIFont
            var traits: UIFontDescriptor.SymbolicTraits = []
            if oldFont?.fontDescriptor.symbolicTraits.contains(.traitBold) == true { traits.insert(.traitBold) }
            if oldFont?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true { traits.insert(.traitItalic) }
            let descriptor = UIFont.systemFont(ofSize: fontSize).fontDescriptor.withSymbolicTraits(traits)
            let font = descriptor.map { UIFont(descriptor: $0, size: fontSize) } ?? UIFont.systemFont(ofSize: fontSize)
            result.addAttribute(.font, value: font, range: range)
            result.addAttribute(.foregroundColor, value: textColor, range: range)
        }
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        result.addAttribute(.paragraphStyle, value: style, range: fullRange)
        return result
    }

    private struct UnitBadgeMarker {
        let marker: String
        let unit: String
    }

    private static func extractUnitBadges(from html: String) -> (String, [UnitBadgeMarker]) {
        let pattern = #"<span\b[^>]*data-rc-unit-badge="([A-Za-z0-9+/=]+)"[^>]*>\s*</span>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return (html, [])
        }
        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        guard !matches.isEmpty else { return (html, []) }

        let mutableHTML = NSMutableString(string: html)
        var badges: [UnitBadgeMarker] = []
        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let payload = Data(base64Encoded: nsHTML.substring(with: match.range(at: 1))),
                  let unit = String(data: payload, encoding: .utf8),
                  !unit.isEmpty else { continue }
            let marker = "RCUNITBADGE_\(UUID().uuidString)_END"
            mutableHTML.replaceCharacters(in: match.range, with: marker)
            badges.append(UnitBadgeMarker(marker: marker, unit: unit))
        }
        return (mutableHTML as String, badges)
    }

    private static func unitBadgeAttachment(for unit: String) -> NSTextAttachment {
        let label = unit.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let font = UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        let textSize = (label as NSString).size(withAttributes: [.font: font])
        let badgeSize = CGSize(width: ceil(textSize.width) + 12, height: ceil(font.lineHeight) + 4)
        let renderer = UIGraphicsImageRenderer(size: badgeSize)
        let image = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: badgeSize).insetBy(dx: 0.5, dy: 0.5)
            let badge = UIBezierPath(roundedRect: rect, cornerRadius: 5)
            UIColor(red: 241.0 / 255.0, green: 245.0 / 255.0, blue: 249.0 / 255.0, alpha: 1).setFill()
            badge.fill()
            UIColor(red: 203.0 / 255.0, green: 213.0 / 255.0, blue: 225.0 / 255.0, alpha: 1).setStroke()
            badge.lineWidth = 1
            badge.stroke()
            let textRect = CGRect(
                x: 6,
                y: (badgeSize.height - font.lineHeight) / 2,
                width: textSize.width,
                height: font.lineHeight
            )
            label.draw(in: textRect, withAttributes: [
                .font: font,
                .foregroundColor: UIColor(red: 51.0 / 255.0, green: 65.0 / 255.0, blue: 85.0 / 255.0, alpha: 1)
            ])
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -3, width: badgeSize.width, height: badgeSize.height)
        return attachment
    }
}

final class LocalMediaSchemeHandler: NSObject, WKURLSchemeHandler {
    private let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL))
            return
        }
        let encodedName = requestURL.path.isEmpty
            ? (requestURL.host ?? "")
            : requestURL.lastPathComponent
        let filename = encodedName.removingPercentEncoding ?? encodedName
        guard !filename.isEmpty, URL(fileURLWithPath: filename).lastPathComponent == filename else {
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL))
            return
        }
        let fileURL = directoryURL.appendingPathComponent(filename).standardizedFileURL
        guard fileURL.deletingLastPathComponent() == directoryURL else {
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorNoPermissionsToReadFile))
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

private extension UIColor {
    var hexRGB: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: nil)
        return String(format: "%02x%02x%02x", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}
