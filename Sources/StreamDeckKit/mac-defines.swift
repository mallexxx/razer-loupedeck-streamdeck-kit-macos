//
//  mac-defines.swift
//  StreamDeckKit
//
//  Created by admin on 05.11.2024.
//

#if canImport(AppKit)
import AppKit

typealias UIImage = NSImage
typealias UIColor = NSColor

extension NSImage {

    var cgImage: CGImage? {
        self.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    var imageOrientation: Void { () }

    convenience init(cgImage: CGImage, scale: CGFloat, orientation: Void = ()) {
        self.init(size: NSSize(width: cgImage.width, height: cgImage.height))

        // Create a bitmap representation from the CGImage
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)

        // Set the scale factor
        bitmapRep.size = NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)

        // Add the bitmap representation to the NSImage
        self.addRepresentation(bitmapRep)
    }

    public convenience init?(data: Data, scale: CGFloat) {
        guard scale != 1 else {
            self.init(data: data)
            return
        }
        guard let image = NSImage(data: data) else { return nil }

        // Initialize self with the size of the image
        self.init(size: image.size)

        // Add the original image's representations to the new image
        for representation in image.representations {
            if let bitmapRep = representation as? NSBitmapImageRep {
                // Create a new bitmap representation with the specified scale
                let scaledBitmapRep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                       pixelsWide: Int(image.size.width * scale),
                                                       pixelsHigh: Int(image.size.height * scale),
                                                       bitsPerSample: 8,
                                                       samplesPerPixel: 4,
                                                       hasAlpha: true,
                                                       isPlanar: false,
                                                       colorSpaceName: NSColorSpaceName.deviceRGB,
                                                       bytesPerRow: 0,
                                                       bitsPerPixel: 0)

                // Set the size and scale of the new bitmap representation
                scaledBitmapRep?.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)

                // Add the scaled bitmap representation to the NSImage
                if let scaledBitmapRep = scaledBitmapRep {
                    self.addRepresentation(scaledBitmapRep)
                }
            }
        }
    }

}
#endif
