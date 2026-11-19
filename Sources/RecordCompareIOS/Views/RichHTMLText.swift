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
        view.delegate = context.coordinator
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

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    static func plainText(from html: String) -> String {
        attributedContent(from: html, fontSize: 14, textColor: .label, alignment: .natural).string
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
            .replacingOccurrences(of: #"(?is)<style\b[^>]*>.*?</style>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<(iframe|object|embed)\b[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<(img|figure)\b[^>]*>.*?</figure>|<img\b[^>]*>"#, with: "", options: .regularExpression)
        let parsed = Self.parseMarkup(cleanHTML, fontSize: fontSize, textColor: textColor)
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

    private struct MarkupFrame {
        let name: String
        let link: URL?
    }

    private static func parseMarkup(_ html: String, fontSize: CGFloat, textColor: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let tokenPattern = #"(?s)<[^>]*>|[^<]+"#
        guard let tokenRegex = try? NSRegularExpression(pattern: tokenPattern) else {
            return NSAttributedString(string: html)
        }
        let source = html as NSString
        let tokens = tokenRegex.matches(in: html, range: NSRange(location: 0, length: source.length))
        var frames: [MarkupFrame] = []
        let blockTags: Set<String> = ["p", "div", "li", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote"]

        func appendNewlineIfNeeded() {
            guard result.length > 0,
                  (result.string as NSString).substring(from: result.length - 1) != "\n" else { return }
            result.append(NSAttributedString(string: "\n"))
        }

        for token in tokens {
            let value = source.substring(with: token.range)
            guard value.hasPrefix("<"), value.hasSuffix(">") else {
                let decoded = decodeHTMLEntities(value)
                guard !decoded.isEmpty else { continue }
                var traits: UIFontDescriptor.SymbolicTraits = []
                if frames.contains(where: { ["b", "strong"].contains($0.name) }) { traits.insert(.traitBold) }
                if frames.contains(where: { ["i", "em"].contains($0.name) }) { traits.insert(.traitItalic) }
                let descriptor = UIFont.systemFont(ofSize: fontSize).fontDescriptor.withSymbolicTraits(traits)
                let font = descriptor.map { UIFont(descriptor: $0, size: fontSize) } ?? UIFont.systemFont(ofSize: fontSize)
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: textColor
                ]
                if frames.contains(where: { $0.name == "u" || $0.name == "ins" }) {
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                if frames.contains(where: { $0.name == "s" || $0.name == "strike" || $0.name == "del" }) {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
                if let url = frames.reversed().compactMap(\.link).first {
                    attributes[.link] = url
                }
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .natural
                result.append(NSAttributedString(string: decoded, attributes: attributes.merging([.paragraphStyle: paragraph]) { current, _ in current }))
                continue
            }

            let tagBody = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            if tagBody.isEmpty || tagBody.hasPrefix("!") || tagBody.hasPrefix("?") { continue }
            let closing = tagBody.hasPrefix("/")
            let selfClosing = tagBody.hasSuffix("/")
            let body = tagBody.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            let name = body.prefix { $0.isLetter || $0.isNumber }.lowercased()
            guard !name.isEmpty else { continue }

            if closing {
                if blockTags.contains(name) { appendNewlineIfNeeded() }
                if let index = frames.lastIndex(where: { $0.name == name }) {
                    frames.removeSubrange(index...)
                }
                continue
            }

            if name == "br" {
                result.append(NSAttributedString(string: "\n"))
                continue
            }
            if blockTags.contains(name) { appendNewlineIfNeeded() }
            if name == "li" {
                result.append(NSAttributedString(string: "• ", attributes: [
                    .font: UIFont.systemFont(ofSize: fontSize),
                    .foregroundColor: textColor
                ]))
            }
            let link = name == "a" ? safeLink(in: body) : nil
            if !selfClosing && !["img", "hr", "meta", "link", "input"].contains(name) {
                frames.append(MarkupFrame(name: name, link: link))
            }
        }
        return result
    }

    private static func safeLink(in tag: String) -> URL? {
        let pattern = #"(?i)\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let match = firstMatch(pattern, in: tag) else { return nil }
        let target = (1...3).compactMap { capture(match, group: $0, in: tag) }.first ?? ""
        guard let url = URL(string: decodeHTMLEntities(target)),
              ExternalLinkOpener.isSupported(url) else { return nil }
        return url
    }

    static func decodeHTMLEntities(_ value: String) -> String {
        let pattern = #"(?i)&(amp|lt|gt|quot|apos|nbsp|copy|reg|mdash|ndash|hellip|bull|trade|#39|#\d+|#x[0-9a-f]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let source = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return value }
        let result = NSMutableString(string: value)
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let entity = source.substring(with: match.range(at: 1))
            let replacement: String
            switch entity.lowercased() {
            case "amp": replacement = "&"
            case "lt": replacement = "<"
            case "gt": replacement = ">"
            case "quot": replacement = "\""
            case "apos", "#39": replacement = "'"
            case "nbsp": replacement = "\u{00a0}"
            case "copy": replacement = "©"
            case "reg": replacement = "®"
            case "mdash": replacement = "—"
            case "ndash": replacement = "–"
            case "hellip": replacement = "…"
            case "bull": replacement = "•"
            case "trade": replacement = "™"
            default:
                let scalar: UInt32?
                if entity.lowercased().hasPrefix("#x") {
                    scalar = UInt32(entity.dropFirst(2), radix: 16)
                } else {
                    scalar = UInt32(entity.dropFirst())
                }
                guard let scalar, let unicode = UnicodeScalar(scalar) else { continue }
                replacement = String(unicode)
            }
            result.replaceCharacters(in: match.range, with: replacement)
        }
        return result as String
    }

    private static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func capture(_ match: NSTextCheckingResult, group: Int, in text: String) -> String? {
        guard match.range(at: group).location != NSNotFound,
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
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

    final class Coordinator: NSObject, UITextViewDelegate {
        @available(iOS 17.0, *)
        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            guard case let .link(url) = textItem.content else { return defaultAction }
            return UIAction(title: defaultAction.title) { _ in
                ExternalLinkOpener.open(url)
            }
        }
    }
}

enum ExternalLinkOpener {
    private static let supportedAppSchemes: Set<String> = [
        "upnote", "obsidian", "notion", "craftdocs", "bear", "things",
        "onenote", "goodnotes", "notability", "logseq",
        "applenotes", "notes", "mobilenotes"
    ]

    static func open(_ url: URL) {
        guard isSupported(url) else {
            Task { @MainActor in showFailure("This link type isn’t supported.") }
            return
        }
        Task { @MainActor in
            UIApplication.shared.open(url, options: [:]) { success in
                guard !success else { return }
                showFailure("No app is available to open \(url.host ?? url.scheme ?? "this link").")
            }
        }
    }

    static func isSupported(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case "http", "https":
            return url.host != nil
        case "mailto", "tel":
            return !url.path.isEmpty
        default:
            if supportedAppSchemes.contains(scheme) { return true }
            guard scheme.hasPrefix("marginnote") else { return false }
            return scheme.dropFirst("marginnote".count)
                .allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        }
    }

    @MainActor
    private static func showFailure(_ message: String) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootViewController = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return
        }
        var presenter = rootViewController
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        guard !(presenter is UIAlertController) else { return }
        let alert = UIAlertController(
            title: "Unable to Open Link",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
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
