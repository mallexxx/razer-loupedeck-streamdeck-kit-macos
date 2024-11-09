//
//  UIImage+Color.swift
//  Created by Roman Schlagowsky on 06.12.23.
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

#if os(iOS)

import UIKit

public extension UIImage {
    static func sdk_colored(_ color: UIColor, size: CGSize = .init(width: 1, height: 1)) -> UIImage {
        return UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.setFillColor(color.cgColor)
            context.cgContext.addRect(CGRect(origin: .zero, size: size))
            context.cgContext.drawPath(using: .fill)
        }
    }
}

#else

import Accelerate
import AppKit

public extension NSImage {

    static func sdk_colored(_ color: NSColor, size: NSSize = .init(width: 1, height: 1)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        color.setFill()
        NSRect(x: 0, y: 0, width: size.width, height: size.height).fill()

        image.unlockFocus()

        return image
    }

    private func argbBitmapData(_ inImage: CGImage, size: NSSize) -> Data {
        let width = Int(size.width)
        let height = Int(size.height)
        let bitmapBytesPerRow = width * 4
        let bitmapByteCount = bitmapBytesPerRow * height

        var bitmapData = Data(count: bitmapByteCount)
        bitmapData.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress,
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bitmapBytesPerRow,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
            let rect = NSRect(origin: .zero, size: size)
            context.draw(inImage, in: rect)
        }

        return bitmapData
    }

    func rgb565data(with size: NSSize) -> Data {
        var rect = NSRect(origin: .zero, size: self.size)
        let cgImage = self.cgImage(forProposedRect: &rect, context: .current, hints: nil)!
        let w = Int(size.width)
        let h = Int(size.height)

        var inData = argbBitmapData(cgImage, size: size)

        var outData = Data(count: (w * 2) * h)
        inData.withUnsafeMutableBytes { inBuffer in
            outData.withUnsafeMutableBytes { outBuffer in
                var src = vImage_Buffer()
                src.data = inBuffer.baseAddress
                src.width = vImagePixelCount(w)
                src.height = vImagePixelCount(h)
                src.rowBytes = w * 4

                var dst = vImage_Buffer()
                dst.data = outBuffer.baseAddress
                dst.width = vImagePixelCount(w)
                dst.height = vImagePixelCount(h)
                dst.rowBytes = w * 2

                vImageConvert_ARGB8888toRGB565(&src, &dst, 0)
            }
        }

        return outData
    }

}

#endif
