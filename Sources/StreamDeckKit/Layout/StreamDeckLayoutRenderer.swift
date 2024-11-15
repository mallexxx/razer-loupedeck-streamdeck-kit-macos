//
//  StreamDeckLayoutRenderer.swift
//  Created by Alexander Jentz on 27.11.23.
//
//  MIT License
//
//  Copyright (c) 2023 Corsair Memory Inc.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Combine
import Foundation
import OSLog
import SwiftUI

final class StreamDeckLayoutRenderer {

    private var cancellable: AnyCancellable?

    private var dirtyViews = [DirtyMarker]()

    init() {}

    @MainActor
    func render<Content: View>(_ content: Content, on device: StreamDeck) {
        cancellable?.cancel()
        dirtyViews = [.screen]

        let context = StreamDeckViewContext(
            device: device,
            dirtyMarker: .screen,
            size: device.capabilities.screenSize ?? .zero
        )

        let view = content
            .environment(\.streamDeckViewContext, context)

        let renderer = ImageRenderer(content: view)
        renderer.scale = device.capabilities.displayScale

        cancellable = renderer
            .objectWillChange.prepend(())
            .receive(on: RunLoop.main) // Run on next loop so "will change" becomes "did change".
            .compactMap { _ in
#if os(iOS)
                renderer.uiImage
#else
                renderer.nsImage
#endif
            }
            .sink { [weak self] image in
                self?.updateLayout(image, on: device)
            }
    }

    func stop() {
        cancellable?.cancel()
    }

    @MainActor
    func updateRequired(_ dirty: DirtyMarker) {
        Logger.sdRender.debug("Dirty \(dirty.debugDescription)")
        dirtyViews.append(dirty)
    }

    private func updateLayout(_ image: UIImage, on device: StreamDeck) {
        Logger.sdRender.debug("Layout did change")
        let caps = device.capabilities

        guard !dirtyViews.isEmpty else {
            Logger.sdRender.debug("no dirty views")
            return
        }

        defer { dirtyViews.removeAll(keepingCapacity: true) }

        Logger.sdRender.debug("requires updates of \(self.dirtyViews.debugDescription)")

        guard !dirtyViews.contains(.screen) else {
            Logger.sdRender.debug("complete screen required")
            device.setScreenImage(image, scaleAspectFit: false)
            return
        }

        for dirtyView in dirtyViews {
            if case let .key(location) = dirtyView {
                Logger.sdRender.debug("\(dirtyView.debugDescription) required")
                let rect = caps.getKeyRect(location)
                device.setKeyImage(image.cropping(to: rect), at: location, scaleAspectFit: false)
            }
        }

        guard let windowRect = caps.windowRect else { return }

        guard !dirtyViews.contains(.window) else {
            Logger.sdRender.debug("complete window required")
            device.setWindowImage(image.cropping(to: windowRect), scaleAspectFit: false)
            return
        }

        for dirtyView in dirtyViews {
            if case let .windowArea(rect) = dirtyView {
                guard device.supports(.setWindowImageAtXY), let windowRect = caps.windowRect else {
                    Logger.sdRender.debug("\(dirtyView.debugDescription) required but no setWindowImage(:at:) support")
                    device.setWindowImage(image.cropping(to: windowRect), scaleAspectFit: false)
                    return
                }

                Logger.sdRender.debug("\(dirtyView.debugDescription) required")
                device.setWindowImage(
                    image.cropping(to: rect),
                    at: .init(
                        x: rect.origin.x - windowRect.origin.x,
                        y: rect.origin.y - windowRect.origin.y,
                        width: rect.width,
                        height: rect.height
                    ),
                    scaleAspectFit: false
                )
            }
        }
    }

}

extension UIImage {
#if os(iOS)
    func cropping(to rect: CGRect) -> UIImage {
        var rect = rect

        if scale != 1 {
            rect = rect.applying(CGAffineTransform(scaleX: scale, y: scale))
        }

        guard let cgImage = cgImage,
              let cropped = cgImage.cropping(to: rect)
        else { return self }

        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }
#else
    func cropping(to rect: CGRect) -> UIImage {
        // Get the first representation (assuming it's a bitmap representation)
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let croppedCGImage = cgImage.cropping(to: rect) else { return self }

        // Create a new NSImage from the cropped CGImage
        let croppedImage = NSImage(cgImage: croppedCGImage, size: NSSize(width: rect.width, height: rect.height))

        return croppedImage
    }

#endif
}
