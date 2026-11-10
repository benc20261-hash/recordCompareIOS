import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

struct RichHTMLText: UIViewRepresentable {
    let html: String
    var fontSize: CGFloat = 14
    var textColor: UIColor = .label
    var alignment: NSTextAlignment = .natural

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
        let cleanHTML = html
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
