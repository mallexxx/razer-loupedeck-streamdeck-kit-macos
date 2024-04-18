//
//  StatelessStreamDeckLayout.swift
//  Example App
//
//  Created by Christiane Göhring on 20.02.24.
//

import StreamDeckKit
import SwiftUI

@StreamDeckView
struct StatelessStreamDeckLayout {

    var streamDeckBody: some View {
        StreamDeckLayout {
            // Define key area
            // Use StreamDeckKeyAreaLayout for rendering separate keys
            StreamDeckKeyAreaLayout { keyIndex in
                // Define content for each key.
                // StreamDeckKeyAreaLayout provides an index for each available key,
                // and StreamDeckKeyView provides a callback for the key action
                // Example:
                StreamDeckKeyView { pressed in
                    print("pressed \(pressed) at index \(keyIndex)")
                } content: {
                    Text("\(keyIndex)")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.teal)
                }
            }.background(.purple)
        } windowArea: {
            // Define window area
            if streamDeck.info.product == .plus {
                // Use StreamDeckDialAreaLayout for Stream Deck +
                StreamDeckDialAreaLayout { dialIndex in
                    // Define content for each dial
                    // StreamDeckDialAreaLayout provides an index for each available dial,
                    // and StreamDeckDialView provides callbacks for the dial actions
                    // Example:
                    StreamDeckDialView { rotations in
                        print("dial rotated \(rotations)")
                    } press: { pressed in
                        print("pressed \(pressed)")
                    } touch: { location in
                        print("touched at \(location)")
                    } content: {
                        Text("\(dialIndex)")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(white: Double(dialIndex) / 5 + 0.5))
                    }
                }
            } else if streamDeck.info.product == .neo {
                // Use StreamDeckNeoPanelLayout for Stream Deck Neo
                StreamDeckNeoPanelLayout { touched in
                    print("left key touched \(touched)")
                } rightTouch: { touched in
                    print("right key touched \(touched)")
                } panel: {
                    Text("Info Panel")
                }
                .background(.yellow)
            }
        }.background(.indigo)
    }

}

#if DEBUG

import StreamDeckSimulator

#Preview("Stream Deck +") {
    StreamDeckSimulator.PreviewView(streamDeck: .plus) { device in
        device.render(StatelessStreamDeckLayout())
    }
}

#Preview("Stream Deck Classic") {
    StreamDeckSimulator.PreviewView(streamDeck: .regular) { device in
        device.render(StatelessStreamDeckLayout())
    }
}

#Preview("Stream Deck Neo") {
    StreamDeckSimulator.PreviewView(streamDeck: .neo) { device in
        device.render(StatelessStreamDeckLayout())
    }
}

#endif
