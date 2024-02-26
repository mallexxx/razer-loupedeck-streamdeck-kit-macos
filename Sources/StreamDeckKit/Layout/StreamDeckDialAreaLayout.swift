//
//  StreamDeckDialAreaLayout.swift
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

import SwiftUI

/// A View that draws the layout of a Stream Deck dial window area (The display above the ).
///
/// Use this to render the window area of a Stream Deck Plus and handle its events.
///
/// The layout depends on the device from the current ``StreamDeckViewContext`` environment.
public struct StreamDeckDialAreaLayout<Dial: View>: View {
    /// A handler for rotation events on a rotary encoder(dial).
    ///
    /// The first parameter is the index of the dial. The second one is the rotation value. Negative values indicate a rotation to the left.
    public typealias DialRotationHandler = @MainActor (Int, Int) -> Void

    /// A handler for press events on a rotary encoder(dial).
    ///
    /// The first parameter is the index of the dial. The second one indicates if the dial is down or not.
    public typealias DialPressHandler = @MainActor (Int, Bool) -> Void
    public typealias TouchHandler = @MainActor (CGPoint) -> Void
    public typealias FlingHandler = @MainActor (CGPoint, CGPoint, InputEvent.Direction) -> Void

    @Environment(\.streamDeckViewContext) private var context

    private let rotate: DialRotationHandler?
    private let press: DialPressHandler?
    private let touch: TouchHandler?
    private let fling: FlingHandler?
    @ViewBuilder private let dial: @MainActor (StreamDeckViewContext) -> Dial

    public init(
        rotate: DialRotationHandler? = nil,
        press: DialPressHandler? = nil,
        touch: TouchHandler? = nil,
        fling: FlingHandler? = nil,
        @ViewBuilder dial: @escaping @MainActor (StreamDeckViewContext) -> Dial
    ) {
        self.rotate = rotate
        self.press = press
        self.touch = touch
        self.fling = fling
        self.dial = dial
    }

    public init(
        rotate: DialRotationHandler? = nil,
        press: @escaping @MainActor (Int) -> Void,
        touch: TouchHandler? = nil,
        fling: FlingHandler? = nil,
        @ViewBuilder dial: @escaping @MainActor (StreamDeckViewContext) -> Dial
    ) {
        self.init(
            rotate: rotate,
            press: { if $1 { press($0) } },
            touch: touch,
            fling: fling,
            dial: dial
        )
    }

    public var body: some View {
        let caps = context.device.capabilities

        HStack(spacing: 0) {
            ForEach(0 ..< caps.dialCount, id: \.self) { section in
                let rect = caps.getDialAreaSectionRect(section)

                let dialContext = context.with(
                    dirtyMarker: .windowArea(rect),
                    size: rect.size,
                    index: section
                )

                dial(dialContext)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .environment(\.streamDeckViewContext, dialContext)
            }
        }
        .onReceive(context.device.inputEventsPublisher) { event in
            switch event {
            case let .rotaryEncoderRotation(index, steps):
                rotate?(index, steps)
            case let .rotaryEncoderPress(index, pressed):
                press?(index, pressed)
            case let .touch(point):
                touch?(point)
            case let .fling(start, end):
                fling?(start, end, event.direction)
            default: break
            }
        }
    }
}