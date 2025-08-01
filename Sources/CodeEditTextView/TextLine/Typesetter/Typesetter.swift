//
//  Typesetter.swift
//  CodeEditTextView
//
//  Created by Khan Winter on 6/21/23.
//

import AppKit
import CoreText

/// The `Typesetter` is responsible for producing text fragments from a document range. It transforms a text line
/// and attachments into a sequence of `LineFragment`s, which reflect the visual structure of the text line.
///
/// This class has one primary method: ``typeset(_:documentRange:displayData:markedRanges:attachments:)``, which
/// performs the typesetting algorithm and breaks content into runs using attachments.
///
/// To retrieve the line fragments generated by this class, access the ``lineFragments`` property.
final public class Typesetter {
    struct ContentRun {
        let range: NSRange
        let type: RunType

        enum RunType {
            case attachment(AnyTextAttachment)
            case string(CTTypesetter)
        }
    }

    public var documentRange: NSRange?
    public var lineFragments = TextLineStorage<LineFragment>()

    // MARK: - Init & Prepare

    public init() { }

    public func typeset(
        _ string: NSAttributedString,
        documentRange: NSRange,
        displayData: TextLine.DisplayData,
        markedRanges: MarkedRanges?,
        attachments: [AnyTextAttachment] = []
    ) {
        let string = makeString(string: string, markedRanges: markedRanges)
        lineFragments.removeAll()

        // Fast path
        if string.length == 0 || displayData.maxWidth <= 0 {
            typesetEmptyLine(displayData: displayData, string: string)
            return
        }
        let (lines, maxHeight) = typesetLineFragments(
            string: string,
            documentRange: documentRange,
            displayData: displayData,
            attachments: attachments
        )
        lineFragments.build(from: lines, estimatedLineHeight: maxHeight)
    }

    private func makeString(string: NSAttributedString, markedRanges: MarkedRanges?) -> NSAttributedString {
        if let markedRanges {
            let mutableString = NSMutableAttributedString(attributedString: string)
            for markedRange in markedRanges.ranges {
                mutableString.addAttributes(markedRanges.attributes, range: markedRange)
            }
            return mutableString
        }

        return string
    }

    // MARK: - Create Content Lines

    /// Breaks up the string into a series of 'runs' making up the visual content of this text line.
    /// - Parameters:
    ///   - string: The string reference to use.
    ///   - documentRange: The range in the string reference.
    ///   - attachments: Any text attachments overlapping the string reference.
    /// - Returns: A series of content runs making up this line.
    func createContentRuns(
        string: NSAttributedString,
        documentRange: NSRange,
        attachments: [AnyTextAttachment]
    ) -> [ContentRun] {
        var attachments = attachments
        var currentPosition = 0
        let maxPosition = documentRange.length
        var runs: [ContentRun] = []

        while currentPosition < maxPosition {
            guard let nextAttachment = attachments.first else {
                // No attachments, use the remaining length
                if maxPosition > currentPosition {
                    let range = NSRange(location: currentPosition, length: maxPosition - currentPosition)
                    let substring = string.attributedSubstring(from: range)
                    runs.append(
                        ContentRun(
                            range: range,
                            type: .string(CTTypesetterCreateWithAttributedString(substring))
                        )
                    )
                }
                break
            }
            attachments.removeFirst()
            // adjust the range to be relative to the line
            let attachmentRange = NSRange(
                location: nextAttachment.range.location - documentRange.location,
                length: nextAttachment.range.length
            )

            // Use the space before the attachment
            if nextAttachment.range.location > currentPosition {
                let range = NSRange(start: currentPosition, end: attachmentRange.location)
                let substring = string.attributedSubstring(from: range)
                runs.append(
                    ContentRun(range: range, type: .string(CTTypesetterCreateWithAttributedString(substring)))
                )
            }

            runs.append(ContentRun(range: attachmentRange, type: .attachment(nextAttachment)))
            currentPosition = attachmentRange.max
        }

        return runs
    }

    // MARK: - Typeset Content Runs

    func typesetLineFragments(
        string: NSAttributedString,
        documentRange: NSRange,
        displayData: TextLine.DisplayData,
        attachments: [AnyTextAttachment]
    ) -> (lines: [TextLineStorage<LineFragment>.BuildItem], maxHeight: CGFloat) {
        let contentRuns = createContentRuns(string: string, documentRange: documentRange, attachments: attachments)
        var context = TypesetContext(documentRange: documentRange, displayData: displayData)

        for run in contentRuns {
            switch run.type {
            case .attachment(let attachment):
                context.appendAttachment(attachment)
            case .string(let typesetter):
                layoutTextUntilLineBreak(
                    context: &context,
                    string: string,
                    range: run.range,
                    typesetter: typesetter,
                    displayData: displayData
                )
            }
        }

        if !context.fragmentContext.contents.isEmpty {
            context.popCurrentData()
        }

        return (context.lines, context.maxHeight)
    }

    // MARK: - Layout Text Fragments

    func layoutTextUntilLineBreak(
        context: inout TypesetContext,
        string: NSAttributedString,
        range: NSRange,
        typesetter: CTTypesetter,
        displayData: TextLine.DisplayData
    ) {
        let substring = string.attributedSubstring(from: range)

        // Layout as many fragments as possible in this content run
        while context.currentPosition < range.max {
            // The line break indicates the distance from the range we’re typesetting on that should be broken at.
            // It's relative to the range being typeset, not the line
            let lineBreak = typesetter.suggestLineBreak(
                using: substring,
                strategy: displayData.breakStrategy,
                subrange: NSRange(start: context.currentPosition - range.location, end: range.length),
                constrainingWidth: displayData.maxWidth - context.fragmentContext.width
            )

            // Indicates the subrange on the range that the typesetter knows about. This may not be the entire line
            let typesetSubrange = NSRange(location: context.currentPosition - range.location, length: lineBreak)
            let typesetData = typesetLine(typesetter: typesetter, range: typesetSubrange)

            // The typesetter won't tell us if 0 characters can fit in the constrained space. This checks to
            // make sure we can fit something. If not, we pop and continue
            if lineBreak == 1 && context.fragmentContext.width + typesetData.width > displayData.maxWidth {
                context.popCurrentData()
                continue
            }

            // Amend the current line data to include this line, popping the current line afterwards
            context.appendText(typesettingRange: range, lineBreak: lineBreak, typesetData: typesetData)

            // If this isn't the end of the line, we should break so we pop the context and start a new fragment.
            if context.currentPosition != range.max {
                context.popCurrentData()
            }
        }
    }

    // MARK: - Typeset CTLines

    /// Typeset a new fragment.
    /// - Parameters:
    ///   - range: The range of the fragment.
    ///   - lineHeightMultiplier: The multiplier to apply to the line's height.
    /// - Returns: A new line fragment.
    private func typesetLine(typesetter: CTTypesetter, range: NSRange) -> CTLineTypesetData {
        let ctLine = CTTypesetterCreateLine(typesetter, CFRangeMake(range.location, range.length))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading))
        let height = ascent + descent + leading
        return CTLineTypesetData(
            ctLine: ctLine,
            descent: descent,
            width: width,
            height: height
        )
    }

    /// Typesets a single, 0-length line fragment.
    /// - Parameter displayData: Relevant information for layout estimation.
    private func typesetEmptyLine(displayData: TextLine.DisplayData, string: NSAttributedString) {
        let typesetter = CTTypesetterCreateWithAttributedString(string)
        // Insert an empty fragment
        let ctLine = CTTypesetterCreateLine(typesetter, CFRangeMake(0, 0))
        let fragment = LineFragment(
            contents: [.init(data: .text(line: ctLine), width: 0.0)],
            width: 0,
            height: displayData.estimatedLineHeight / displayData.lineHeightMultiplier,
            descent: 0,
            lineHeightMultiplier: displayData.lineHeightMultiplier
        )
        lineFragments.build(
            from: [.init(data: fragment, length: 0, height: fragment.scaledHeight)],
            estimatedLineHeight: 0
        )
    }

    deinit {
        lineFragments.removeAll()
    }
}
