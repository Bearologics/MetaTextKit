//
//  MetaText.swift
//
//
//  Created by MainasuK Cirno on 2021-6-7.
//

import UIKit
import Meta
import AVFoundation
public protocol MetaTextDelegate: AnyObject {
    func metaText(_ metaText: MetaText, processEditing textStorage: MetaTextStorage) -> MetaContent?
}

public class MetaText: NSObject {

    public weak var delegate: MetaTextDelegate?

    public let layoutManager: MetaLayoutManager
    public let textStorage: MetaTextStorage
    public let textView: MetaTextView

    static var fontSize: CGFloat = 17

    public var paragraphStyle: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        style.paragraphSpacing = 8
        return style
    }()

    public var textAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: MetaText.fontSize, weight: .regular)),
        .foregroundColor: UIColor.label,
    ]

    public var linkAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: MetaText.fontSize, weight: .semibold)),
        .foregroundColor: UIColor.link,
    ]
    
    public override init() {
        let textStorage = MetaTextStorage()
        self.textStorage = textStorage

        let layoutManager = MetaLayoutManager()
        self.layoutManager = layoutManager
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: .zero)
        layoutManager.addTextContainer(textContainer)

        textView = MetaTextView(frame: .zero, textContainer: textContainer)
        layoutManager.hostView = textView

        super.init()

        textStorage.processDelegate = self
        layoutManager.delegate = self
    }
    
}

extension MetaText {

    public var backedString: String {
        let string = textStorage.string
        let nsString = NSMutableString(string: string)
        textStorage.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: textStorage.length),
            options: [.reverse])
        { value, range, _ in
            guard let attachment = value as? MetaAttachment else { return }
            nsString.replaceCharacters(in: range, with: attachment.string)
        }
        return nsString as String
    }

}

extension MetaText {

    public func configure(content: MetaContent) {
        let attributedString = NSMutableAttributedString(string: content.string)

        MetaText.setAttributes(
            for: attributedString,
            textAttributes: textAttributes,
            linkAttributes: linkAttributes,
            paragraphStyle: paragraphStyle,
            content: content
        )

        textView.linkTextAttributes = linkAttributes
        textView.attributedText = attributedString
    }

    public func reset() {
        let attributedString = NSAttributedString(string: "")
        textView.attributedText = attributedString
    }

}

// MARK: - MetaTextStorageDelegate
extension MetaText: MetaTextStorageDelegate {
    public func processEditing(_ textStorage: MetaTextStorage) -> MetaContent? {
        // note: check the attachment content view needs remove or not
        // "Select All" then delete text not call the `drawGlyphs` methold
        if textStorage.length == 0 {
            for view in textView.subviews where view.tag == MetaLayoutManager.displayAttachmentContentViewTag {
                view.removeFromSuperview()
            }
        }

        guard let content = delegate?.metaText(self, processEditing: textStorage) else { return nil }

        // configure meta
        textStorage.beginEditing()
        MetaText.setAttributes(
            for: textStorage,
            textAttributes: textAttributes,
            linkAttributes: linkAttributes,
            paragraphStyle: paragraphStyle,
            content: content
        )
        textStorage.endEditing()

        return content
    }
}

extension MetaText {

    @discardableResult
    public static func setAttributes(
        for attributedString: NSMutableAttributedString,
        textAttributes: [NSAttributedString.Key: Any],
        linkAttributes: [NSAttributedString.Key: Any],
        paragraphStyle: NSMutableParagraphStyle,
        content: MetaContent
    ) -> [MetaAttachment] {

        // clean up
        var allRange = NSRange(location: 0, length: attributedString.length)
        for key in textAttributes.keys {
            attributedString.removeAttribute(key, range: allRange)
        }
        for key in linkAttributes.keys {
            attributedString.removeAttribute(key, range: allRange)
        }
        attributedString.removeAttribute(.meta, range: allRange)
        attributedString.removeAttribute(.paragraphStyle, range: allRange)

        // text
        attributedString.addAttributes(
            textAttributes,
            range: NSRange(location: 0, length: attributedString.length)
        )

        // meta
        let stringRange = NSRange(location: 0, length: attributedString.length)
        for entity in content.entities {
            switch entity.meta {
            case .style(_, let styles, _):
                let traits: UIFontDescriptor.SymbolicTraits = {
                    var traits: UIFontDescriptor.SymbolicTraits = []
                    if styles.contains(.bold) {
                        traits.insert(.traitBold)
                    }
                    if styles.contains(.italic) {
                        traits.insert(.traitItalic)
                    }
                    return traits
                }()
                let font: UIFont = {
                    let fontSize: CGFloat = {
                        guard let fontAttribute = textAttributes.first(where: { $0.key == .font }) ?? linkAttributes.first(where: { $0.key == .font }),
                              let font = fontAttribute.value as? UIFont
                        else { return 14.0 }
                        return font.pointSize
                    }()
                    let font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
                    let fontDescriptor = font.fontDescriptor
                    guard let newFontDescriptor = fontDescriptor.withSymbolicTraits(traits) else {
                        return font
                    }
                    let newFont = UIFont(descriptor: newFontDescriptor, size: fontSize)
                    return UIFontMetrics(forTextStyle: .body).scaledFont(for: newFont)
                }()
                let range = NSIntersectionRange(stringRange, entity.range)
                attributedString.addAttribute(.font, value: font, range: range)
            default:
                var linkAttributes = linkAttributes
                linkAttributes[.meta] = entity.meta
                // FIXME: the emoji make cause wrong entity range out of bounds
                // workaround: use intersection range temporary
                let range = NSIntersectionRange(stringRange, entity.range)
                attributedString.addAttributes(linkAttributes, range: range)
            }
        }

        // attachment
        var replacedAttachments: [MetaAttachment] = []
        for entity in content.entities.reversed() {
            guard let attachment = content.metaAttachment(for: entity) else { continue }
            replacedAttachments.append(attachment)

            let font = attributedString.attribute(.font, at: entity.range.location, effectiveRange: nil) as? UIFont
            let fontSize = font?.pointSize ?? MetaText.fontSize
            if #available(iOS 16, *) {
                attachment.contentFrame = CGRect(
                    origin: .zero,
                    size: CGSize(width: fontSize, height: fontSize)
                )
            } else {
                attachment.bounds = CGRect(
                    origin: .zero,
                    size: CGSize(width: fontSize, height: fontSize)
                )
            }
            attributedString.replaceCharacters(in: entity.range, with: NSAttributedString(attachment: attachment))
        }
        allRange = NSRange(location: 0, length: attributedString.length)
        
        // paragraph
        attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: allRange)

        return replacedAttachments
    }

}
