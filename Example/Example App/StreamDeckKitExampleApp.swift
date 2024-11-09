//
//  StreamDeckKitExampleApp.swift
//  StreamDeckKit Example
//
//  Created by Roman Schlagowsky on 28.12.23.
//

import OSLog
import StreamDeckKit
import SwiftUI

extension Logger {
    static let `default` = Logger(subsystem: "", category: "")
    static let session = Logger(subsystem: "Session", category: "")
}

@main
struct StreamDeckKitExampleApp: App {

    init() {
        StreamDeckSession.setUp(
            stateHandler: { Logger.session.info("Stream Deck session state: \(String(describing: $0.debugDescription))") },
            newDeviceHandler: { $0.render(BaseStreamDeckView()) }
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
