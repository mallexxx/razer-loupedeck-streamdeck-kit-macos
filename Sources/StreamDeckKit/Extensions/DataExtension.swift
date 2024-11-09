//
//  DataExtension.swift
//  StreamDeckKit
//
//  Created by Alexey Martemyanov on 06.11.2024.
//

import Foundation

extension Data {

    func hexEncoded() -> String {
        map { String(format: "%02hhx", $0) }.joined(separator: " ")
    }

}
