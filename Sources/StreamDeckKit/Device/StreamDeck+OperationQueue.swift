//
//  StreamDeck+OperationQueue.swift
//  Created by Alexander Jentz on 28.11.23.
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

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension StreamDeck {

    enum Operation {
        case setInputEventHandler(InputEventHandler)
        case setBrightness(Int)
        case setKeyImage(image: UIImage, key: Int, scaleAspectFit: Bool)
        case setScreenImage(image: UIImage, scaleAspectFit: Bool)
        case setWindowImage(image: UIImage, scaleAspectFit: Bool)
        case setWindowImageAt(image: UIImage, at: CGRect, scaleAspectFit: Bool)
        case fillScreen(color: UIColor)
        case fillKey(color: UIColor, key: Int)
        case showLogo
        case task(() async -> Void)
        case close

        var isDrawingOperation: Bool {
            switch self {
            case .setKeyImage, .setScreenImage, .setWindowImage,
                 .setWindowImageAt, .fillScreen, .fillKey:
                return true
            default: return false
            }
        }
    }

    func startOperationTask() {
        guard operationsTask == nil else { return }

        operationsTask = .detached {
            for await operation in self.operationsQueue {
                await self.run(operation)
            }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func enqueueOperation(_ operation: Operation) {
        guard !isClosed else { return }

        var wasReplaced = false

        switch operation {
        case .setInputEventHandler, .setBrightness, .showLogo, .task:
            break

        case let .setKeyImage(_, key, _):
            wasReplaced = operationsQueue.replaceFirst { pending in
                if case let .setKeyImage(_, pendingKey, _) = pending, key == pendingKey {
                    return operation
                } else if case let .fillKey(_, pendingKey) = pending, key == pendingKey {
                    return operation
                } else {
                    return nil
                }
            }

        case .setScreenImage, .fillScreen:
            operationsQueue.removeAll(where: \.isDrawingOperation)

        case .setWindowImage:
            wasReplaced = operationsQueue.replaceFirst { pending in
                switch pending {
                case .setWindowImage, .setWindowImageAt: return operation
                default: return nil
                }
            }

        case let .setWindowImageAt(_, rect, _):
            wasReplaced = operationsQueue.replaceFirst { pending in
                if case let .setWindowImageAt(_, pendingRect, _) = pending, rect.contains(pendingRect) {
                    return operation
                } else {
                    return nil
                }
            }

        case let .fillKey(_, key):
            wasReplaced = operationsQueue.replaceFirst { pending in
                if case let .fillKey(_, pendingKey) = pending, key == pendingKey {
                    return operation
                } else if case let .setKeyImage(_, pendingKey, _) = pending, key == pendingKey {
                    return operation
                } else {
                    return nil
                }
            }

        case .close:
            operationsQueue.removeAll()
        }

        if !wasReplaced {
            operationsQueue.enqueue(operation)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func run(_ operation: Operation) async {
        switch operation {
        case let .setInputEventHandler(handler):
            guard !didSetInputEventHandler else { return }

            await MainActor.run {
                client.setInputEventHandler(handler)
                didSetInputEventHandler = true
            }

        case let .setBrightness(brightness):
            guard supports(.setBrightness) else { return }
            client.setBrightness(min(max(brightness, 0), 100))

        case let .setKeyImage(image, key, scaleAspectFit):
            guard supports(.setKeyImage),
                  let keySize = capabilities.keySize,
                  let data = transform(image, size: keySize, scaleAspectFit: scaleAspectFit)
            else { return }

            client.setKeyImage(data, at: key)

        case let .setScreenImage(image, scaleAspectFit):
            guard let displaySize = capabilities.screenSize else { return }

            if supports(.setScreenImage) {
                guard let data = transform(image, size: displaySize, scaleAspectFit: scaleAspectFit)
                else { return }

                client.setScreenImage(data)
            } else {
                fakeSetScreenImage(image, scaleAspectFit: scaleAspectFit)
            }

        case let .setWindowImage(image, scaleAspectFit):
            guard supports(.setWindowImage),
                  let size = capabilities.windowRect?.size,
                  let data = transform(image, size: size, scaleAspectFit: scaleAspectFit)
            else { return }

            client.setWindowImage(data)

        case let .setWindowImageAt(image, rect, scaleAspectFit):
            guard supports(.setWindowImageAtXY),
                  let data = transform(image, size: rect.size, scaleAspectFit: scaleAspectFit)
            else { return }

            client.setWindowImage(data, at: rect)

        case .fillScreen(var color):
            if supports(.fillScreen) {
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0

#if os(macOS)
                color = color.usingColorSpace(.sRGB) ?? color
#endif
                color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

                client.fillScreen(
                    red: UInt8(min(255 * red, 255)),
                    green: UInt8(min(255 * green, 255)),
                    blue: UInt8(min(255 * blue, 255))
                )
            } else {
                fakeFillScreen(color)
            }

        case .fillKey(var color, let index):
            if supports(.fillKey) {
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0

#if os(macOS)
                color = color.usingColorSpace(.sRGB) ?? color
#endif
                color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

                client.fillKey(
                    red: UInt8(min(255 * red, 255)),
                    green: UInt8(min(255 * green, 255)),
                    blue: UInt8(min(255 * blue, 255)),
                    at: index
                )
            } else {
                fakeFillKey(color, at: index)
            }

        case .showLogo:
            guard supports(.showLogo) else { return }
            client.showLogo()

        case let .task(task):
            await task()

        case .close:
            for handler in closeHandlers {
                await handler()
            }

            client.close()
            isClosed = true

            operationsQueue.removeAll()
            operationsTask?.cancel()
        }
    }

}

// MARK: Emulated Stream Deck hardware functions
private extension StreamDeck {

    func fakeSetScreenImage(_ image: UIImage, scaleAspectFit: Bool = true) {
        guard supports(.setKeyImage),
              let screenSize = capabilities.screenSize,
              let keySize = capabilities.keySize
        else { return }

        let newImage: UIImage
        if image.size == screenSize {
            newImage = image
        } else {
            let renderer = renderer(size: screenSize)
            let drawingAction = Self.transformDrawingAction(
                image: image,
                size: screenSize,
                transform: .identity,
                scaleAspectFit: scaleAspectFit
            )
            newImage = renderer.image(actions: drawingAction)
        }

        guard let cgImage = newImage.cgImage else { return }

        for index in 0 ..< capabilities.keyCount {
            let rect = capabilities.getKeyRect(index)

            guard let cropped = cgImage.cropping(to: rect) else { return }

            let keyImage = UIImage(
                cgImage: cropped,
                scale: capabilities.displayScale,
                orientation: newImage.imageOrientation
            )

            guard let data = transform(keyImage, size: keySize, scaleAspectFit: false)
            else { return }

            client.setKeyImage(data, at: index)
        }
    }

    func fakeFillScreen(_ color: UIColor) {
        guard supports(.setKeyImage),
              let keySize = capabilities.keySize
        else { return }

        let image = renderer(size: keySize).image { context in
            color.setFill()
            context.cgContext.fill([CGRect(origin: .zero, size: keySize)])
        }
        guard let data = transform(image, size: keySize, scaleAspectFit: false)
        else { return }

        for index in 0 ..< capabilities.keyCount {
            client.setKeyImage(data, at: index)
        }
    }

    func fakeFillKey(_ color: UIColor, at index: Int) {
        guard supports(.setKeyImage),
              let keySize = capabilities.keySize,
              let data = transform(.sdk_colored(color, size: keySize), size: keySize, scaleAspectFit: false)
        else { return }

        for index in 0 ..< capabilities.keyCount {
            client.setKeyImage(data, at: index)
        }
    }

}
