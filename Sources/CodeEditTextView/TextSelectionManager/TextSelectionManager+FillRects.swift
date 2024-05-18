//
//  TextSelectionManager+FillRects.swift
//  CodeEditTextView
//
//  Created by Khan Winter on 10/22/23.
//

import Foundation
import AppKit

extension TextSelectionManager {
    /// Calculate a set of rects for a text selection suitable for highlighting the selection.
    /// - Parameters:
    ///   - rect: The bounding rect of available draw space.
    ///   - textSelection: The selection to use.
    /// - Returns: An array of rects that the selection overlaps.
    func getFillRects(in rect: NSRect, for textSelection: TextSelection) -> [CGRect] {
        guard let layoutManager else { return [] }
        let range = textSelection.range

        var fillRects: [CGRect] = []
        guard let firstLinePosition = layoutManager.lineStorage.getLine(atOffset: range.location),
              let lastLinePosition = range.max == layoutManager.lineStorage.length
                ? layoutManager.lineStorage.last
                : layoutManager.lineStorage.getLine(atOffset: range.max) else {
            return []
        }

        // Calculate the first line and any rects selected
        // If the last line position is not the same as the first, calculate any rects from that line.
        // If there's > 0 space between the first and last positions, add a rect between them to cover any
        // intermediate lines.

        fillRects.append(contentsOf: getFillRects(in: rect, selectionRange: range, forPosition: firstLinePosition))

        if lastLinePosition.range != firstLinePosition.range {
            fillRects.append(contentsOf: getFillRects(in: rect, selectionRange: range, forPosition: lastLinePosition))
        }

        if firstLinePosition.yPos + firstLinePosition.height < lastLinePosition.yPos {
            let fillRect = CGRect(
                x: rect.minX,
                y: firstLinePosition.yPos + firstLinePosition.height,
                width: rect.width,
                height: lastLinePosition.yPos - (firstLinePosition.yPos + firstLinePosition.height)
            ).pixelAligned
            fillRects.append(fillRect)
        }

        return fillRects
    }

    /// Find fill rects for a specific line position.
    /// - Parameters:
    ///   - rect: The bounding rect of the overall view.
    ///   - range: The selected range to create fill rects for.
    ///   - linePosition: The line position to use.
    /// - Returns: An array of rects that the selection overlaps.
    private func getFillRects(
        in rect: NSRect,
        selectionRange range: NSRange,
        forPosition linePosition: TextLineStorage<TextLine>.TextLinePosition
    ) -> [CGRect] {
        guard let layoutManager else { return [] }
        var fillRects: [CGRect] = []

        // The selected range contains some portion of the line
        for fragmentPosition in linePosition.data.lineFragments {
            guard let fragmentRange = fragmentPosition
                .range
                .shifted(by: linePosition.range.location),
                  let intersectionRange = fragmentRange.intersection(range),
                  let minRect = layoutManager.rectForOffset(intersectionRange.location) else {
                continue
            }

            let maxRect: CGRect
            // If the selection is at the end of the line, or contains the end of the fragment, and is not the end
            // of the document, we select the entire line to the right of the selection point.
            if (fragmentRange.max <= range.max || range.contains(fragmentRange.max))
                && intersectionRange.max != layoutManager.lineStorage.length {
                maxRect = CGRect(
                    x: rect.maxX,
                    y: fragmentPosition.yPos + linePosition.yPos,
                    width: 0,
                    height: fragmentPosition.height
                ).pixelAligned
            } else if let maxFragmentRect = layoutManager.rectForOffset(intersectionRange.max) {
                maxRect = maxFragmentRect
            } else {
                continue
            }

            let fillRect = CGRect(
                x: minRect.origin.x,
                y: minRect.origin.y,
                width: maxRect.minX - minRect.minX,
                height: max(minRect.height, maxRect.height)
            ).pixelAligned

            fillRects.append(fillRect)
        }

        return fillRects
    }
    
    /// Creates a drawable path for a text selection for drawing.
    /// - Parameters:
    ///   - rect: The available drawing space.
    ///   - textSelection: The text selection to create the path for.
    /// - Returns: An array of points going clockwise from the top-right corner of the shape. The last point and
    ///            first point should have a line added between them to complete the shape.
    func getSelectionDrawPath(in rect: NSRect, for textSelection: TextSelection) -> NSBezierPath {
        var path: [CGPoint] = []

        // Right-hand side of the text
        var line = layoutManager?.textLineForOffset(textSelection.range.location)
        while let lineUnwrapped = line {
            for fragment in lineUnwrapped.data.lineFragments {
                path.append(CGPoint(x: fragment.data.width, y: fragment.yPos + lineUnwrapped.yPos))
                path.append(CGPoint(x: fragment.data.width, y: fragment.yPos + lineUnwrapped.yPos + fragment.height))
            }

            if let nextLine = layoutManager?.textLineForIndex(lineUnwrapped.index + 1), nextLine.yPos < rect.maxY {
                line = nextLine
            } else {
                line = nil
            }
        }

        // Go back up left side
        while let lineUnwrapped = line {
            for fragment in lineUnwrapped.data.lineFragments {
                path.append(CGPoint(x: 0, y: fragment.yPos + lineUnwrapped.yPos + fragment.height))
                path.append(CGPoint(x: 0, y: fragment.yPos + lineUnwrapped.yPos))
            }

            if let nextLine = layoutManager?.textLineForIndex(lineUnwrapped.index - 1), nextLine.yPos > rect.minY {
                line = nextLine
            } else {
                line = nil
            }
        }

        return makeRoundedPath(from: path)
    }

    private func makeRoundedPath(from points: [CGPoint]) -> NSBezierPath {
        var path = NSBezierPath()
        
        for (idx, point) in points.dropLast().enumerated() {

        }

        return path
    }
}
