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
        let points = makeSelectionPathPoints(in: rect, for: textSelection)
        return makeRoundedPath(from: points, radius: 10)
    }

    private func makeSelectionPathPoints(in rect: NSRect, for textSelection: TextSelection) -> [NSPoint] {
        var path: [NSPoint] = []

        // Right-hand side of the text
        var line = layoutManager?.textLineForOffset(textSelection.range.location)

        // Top-left corner
        if let line {
            path.append(NSPoint(x: rect.minX, y: line.yPos).pixelAligned)
        }

        while let lineUnwrapped = line {
            for fragment in lineUnwrapped.data.lineFragments {
                let topCorner = NSPoint(x: fragment.data.width, y: fragment.yPos + lineUnwrapped.yPos).pixelAligned
                let bottomCorner = NSPoint(
                    x: fragment.data.width,
                    y: fragment.yPos + lineUnwrapped.yPos + fragment.height
                ).pixelAligned
                
                path.append(topCorner)
                path.append(bottomCorner)
            }

            if let nextLine = layoutManager?.textLineForIndex(lineUnwrapped.index + 1),
                textSelection.range.intersection(nextLine.range) != nil,
                nextLine.yPos < rect.maxY {
                line = nextLine
            } else {
                // Bottom left corner, use the last line
                if let line {
                    path.append(NSPoint(x: rect.minX, y: line.yPos + line.height).pixelAligned)
                }
                line = nil
            }
        }

        return path
    }

    private func makeRoundedPath(from points: [NSPoint], radius: CGFloat) -> NSBezierPath {
        guard !points.isEmpty else { return NSBezierPath() }

        let controlPointRadius = radius * 0.55

        var path = NSBezierPath()

        // Assumption: The first and last points are going to be on the same y-value.
        // Control points are 55% of the way from the outer edge of the radius
        // to the corner point.


        for (idx, point) in points.dropLast().enumerated() {
            let nextPoint = points[idx + 1]
            let direction = pointDirection(point, nextPoint)

            // Find destination around corner. If none, connect to first point.
            let destination: NSPoint
            if points.count > idx + 2 {
                destination = points[idx + 2]
            } else {
                destination = points.first! // Safe, due to isEmpty check
            }
            let destinationDir = pointDirection(nextPoint, destination)

            switch direction {
            case .down:
                path.move(to: NSPoint(x: point.x, y: point.y - radius))
                path.line(to: NSPoint(x: point.x, y: nextPoint.y + radius))
                let cpOne = NSPoint(x: point.x, y: nextPoint.y + controlPointRadius)
                let cpTwo: NSPoint
                let destinationCoord: NSPoint
                if direction == .forward { // only need to handle horizontal cases
                    cpTwo = NSPoint(x: nextPoint.x + controlPointRadius, y: nextPoint.y)
                    destinationCoord = NSPoint(x: nextPoint.x + radius, y: nextPoint.y)
                } else { // backward
                    cpTwo = NSPoint(x: nextPoint.x - controlPointRadius, y: nextPoint.y)
                    destinationCoord = NSPoint(x: nextPoint.x - radius, y: nextPoint.y)
                }
                path.curve(to: destinationCoord, controlPoint1: cpOne, controlPoint2: cpTwo)
            case .up:
                path.move(to: NSPoint(x: point.x, y: point.y + radius))
                path.line(to: NSPoint(x: point.x, y: nextPoint.y - radius))
                let cpOne = NSPoint(x: point.x, y: nextPoint.y - controlPointRadius)
                let cpTwo: NSPoint
                let destinationCoord: NSPoint
                if direction == .forward { // only need to handle horizontal cases
                    cpTwo = NSPoint(x: nextPoint.x + controlPointRadius, y: nextPoint.y)
                    destinationCoord = NSPoint(x: nextPoint.x + radius, y: nextPoint.y)
                } else { // backward
                    cpTwo = NSPoint(x: nextPoint.x - controlPointRadius, y: nextPoint.y)
                    destinationCoord = NSPoint(x: nextPoint.x - radius, y: nextPoint.y)
                }
                path.curve(to: destinationCoord, controlPoint1: cpOne, controlPoint2: cpTwo)
            case .forward:
                path.move(to: NSPoint(x: point.x + radius, y: point.y))
                path.line(to: NSPoint(x: point.x - radius, y: nextPoint.y))
                let cpOne = NSPoint(x: point.x - controlPointRadius, y: nextPoint.y)
                let cpTwo: NSPoint
                let destinationCoord: NSPoint
                if direction == .up { // only need to handle vertical cases
                    cpTwo = NSPoint(x: nextPoint.x, y: nextPoint.y + controlPointRadius)
                    destinationCoord = NSPoint(x: nextPoint.x, y: nextPoint.y + radius)
                } else { // down
                    cpTwo = NSPoint(x: nextPoint.x, y: nextPoint.y - controlPointRadius)
                    destinationCoord = NSPoint(x: nextPoint.x, y: nextPoint.y - radius)
                }
                path.curve(to: destinationCoord, controlPoint1: cpOne, controlPoint2: cpTwo)
            case .backward:
                path.move(to: NSPoint(x: point.x - radius, y: point.y))
                path.line(to: NSPoint(x: point.x + radius, y: nextPoint.y))
                let cpOne = NSPoint(x: point.x + controlPointRadius, y: nextPoint.y)
                let cpTwo: NSPoint
                let destinationCoord: NSPoint
                if direction == .up { // only need to handle vertical cases
                    cpTwo = NSPoint(x: nextPoint.x, y: nextPoint.y + controlPointRadius)
                    destinationCoord = NSPoint(x: nextPoint.x, y: nextPoint.y + radius)
                } else { // down
                    cpTwo = NSPoint(x: nextPoint.x, y: nextPoint.y - controlPointRadius)
                    destinationCoord = NSPoint(x: nextPoint.x, y: nextPoint.y - radius)
                }
                path.curve(to: destinationCoord, controlPoint1: cpOne, controlPoint2: cpTwo)
            }
        }

        return path
    }

    private func pointDirection(_ from: NSPoint, _ toPoint: NSPoint) -> Direction {
        if from.x == toPoint.x {
            if from.y < toPoint.y {
                return .down
            } else {
                return .up
            }
        } else {
            if from.x < toPoint.x {
                return .forward
            } else {
                return .backward
            }
        }

    }
}
