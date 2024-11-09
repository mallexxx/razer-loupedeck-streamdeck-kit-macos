//
//  mac-defines.swift
//  StreamDeckKit
//
//  Created by Alexey Martemyanov on 09.11.2024.
//

#if canImport(AppKit)
import AppKit
import SwiftUI

typealias UIImage = NSImage
typealias UIColor = NSColor
typealias UIWindow = NSWindow
typealias UIView = NSView
typealias UIEvent = NSEvent
typealias UIHostingController = NSHostingController

extension NSImage {

    convenience init?(systemName name: String) {
        self.init(named: name)
    }

}

extension NSWindow {
    var isHidden: Bool {
        get {
            !isVisible
        }
        set {
            if newValue {
                orderOut(nil)
            } else {
                makeKeyAndOrderFront(nil)
                DispatchQueue.main.async {
                    var size = self.contentView!.frame.size
                    size.height = 400
                    self.setContentSize(size)
                }
            }
        }
    }
    var rootViewController: NSViewController? {
        get {
            contentViewController
        }
        set {
            contentViewController = newValue
        }
    }
}

extension NSView {
    var center: CGPoint {
        get {
            CGPoint(x: frame.midX, y: frame.midY)
        }
        set {
            frame.origin = CGPoint(x: newValue.x - frame.width / 2, y: newValue.y - frame.height / 2)
        }
    }
    var backgroundColor: NSColor? {
        get {
            layer.flatMap { $0.backgroundColor.flatMap { NSColor(cgColor: $0) } }
        }
        set {
            wantsLayer = true
            layer?.backgroundColor = newValue?.cgColor
        }
    }
}
#endif

extension SwiftUI.Image {
    init(_ image: UIImage) {
#if canImport(UIKit)
        self.init(uiImage: image)
#else
        self.init(nsImage: image)
#endif
    }
}
