//
//  CGPoint+Helpers.swift
//  CodeEditTextView
//
//  Created by Khan Winter on 5/11/24.
//

import CoreGraphics

package extension CGPoint {
    static func + (lhs: CGPoint, rhs: (CGFloat, CGFloat)) -> CGPoint {
        return CGPoint(x: lhs.x + rhs.0, y: lhs.y + rhs.1)
    }

    static func - (lhs: CGPoint, rhs: (CGFloat, CGFloat)) -> CGPoint {
        return CGPoint(x: lhs.x - rhs.0, y: lhs.y - rhs.1)
    }
}
