//
//   LoupedeckDevice.swift
//  StreamDeckKit
//
//  Created by admin on 07.11.2024.
//

import CoreGraphics
import Foundation

public enum  LoupedeckDevice {

    case loupedeckLive
    case loupedeckCT
    case loupedeckLiveS
    case razerStreamController
    case razerStreamControllerX

    enum Vendor: Int {
        case loupedeck = 0x2ec2
        case razer = 0x1532

        var name: String {
            switch self {
            case .loupedeck: return " Loupedeck"
            case .razer: return "Razer"
            }
        }
    }

    enum LoupedeckDevice: Int {
        case loupedeckLive = 0x0004
        case loupedeckCT = 0x0003
        case loupedeckLiveS = 0x0006
    }
    enum RazerDevice: Int {
        case razerStreamController = 0x0d06
        case razerStreamControllerX = 0x0d09
    }

    var vendor: Vendor {
        switch self {
        case .loupedeckLive, .loupedeckCT, .loupedeckLiveS: return Vendor.loupedeck
        case .razerStreamController, .razerStreamControllerX: return Vendor.razer
        }
    }

    var vendorId: Int {
        vendor.rawValue
    }

    var manufacturer: String {
        vendor.name
    }

    var productId: Int {
        switch self {
        case .loupedeckLive: return  LoupedeckDevice.loupedeckLive.rawValue
        case .loupedeckCT: return  LoupedeckDevice.loupedeckCT.rawValue
        case .loupedeckLiveS: return  LoupedeckDevice.loupedeckLiveS.rawValue
        case .razerStreamController: return RazerDevice.razerStreamController.rawValue
        case .razerStreamControllerX: return RazerDevice.razerStreamControllerX.rawValue
        }
    }

    var productName: String {
        switch self {
        case .loupedeckLive: "Loupedeck Live"
        case .loupedeckCT: "Loupedeck CT"
        case .loupedeckLiveS: "Loupedeck Live S"
        case .razerStreamController: "Razer Stream Controller"
        case .razerStreamControllerX: "Razer Stream Controller X"
        }
    }

    public init?(vendorId: Int, productId: Int) {
        switch Vendor(rawValue: vendorId) {
        case .loupedeck:
            switch  LoupedeckDevice(rawValue: productId) {
                case .loupedeckLive:
                self = .loupedeckLive
            case .loupedeckCT:
                self = .loupedeckCT
            case .loupedeckLiveS:
                self = .loupedeckLiveS
            default:
                return nil
            }
        case .razer:
            switch RazerDevice(rawValue: productId) {
            case .razerStreamController:
                self = .razerStreamController
            case .razerStreamControllerX:
                self = .razerStreamControllerX
            default:
                return nil
            }
        default:
            return nil
        }
    }

    public var keyRows: Int {
        switch self {
        case .loupedeckLive: 3
        case .loupedeckCT: 3
        case .loupedeckLiveS: 3
        case .razerStreamController: 3
        case .razerStreamControllerX: 3
        }
    }

    public var keyColumns: Int {
        switch self {
        case .loupedeckLive: 4
        case .loupedeckCT: 4
        case .loupedeckLiveS: 5
        case .razerStreamController: 4
        case .razerStreamControllerX: 5
        }
    }

    var keyCount: Int {
        keyRows * keyColumns
    }

    var padding: CGPoint {
        switch self {
        case .loupedeckLive: CGPoint(x: 5, y: 5)
        case .loupedeckCT: CGPoint(x: 5, y: 5)
        case .loupedeckLiveS: CGPoint(x: 18, y: 5)
        case .razerStreamController: CGPoint(x: 5, y: 5)
        case .razerStreamControllerX: CGPoint(x: 5, y: 0)
        }
    }

    var keySize: CGSize {
        switch self {
        case .loupedeckLive: CGSize(width: 60, height: 60)
        case .loupedeckCT: CGSize(width: 60, height: 60)
        case .loupedeckLiveS: CGSize(width: 96, height: 96)
        case .razerStreamController: CGSize(width: 60, height: 60)
        case .razerStreamControllerX: CGSize(width: 78, height: 78)
        }
    }

    var screenSize: CGSize {
        switch self {
        case .loupedeckLive: CGSize(width: 360, height: 270)
        case .loupedeckCT: CGSize(width: 360, height: 270)
        case .loupedeckLiveS: CGSize(width: 480, height: 270)
        case .razerStreamController: CGSize(width: 360, height: 270)
        case .razerStreamControllerX: CGSize(width: 480, height: 270)
        }
    }

    var features: DeviceCapabilities.Features {
        switch self {
        case .loupedeckLive, .loupedeckCT:
            [.setBrightness, .setKeyImage, .fillKey, .setScreenImage, .fillScreen, .keyPressEvents, .touchEvents, .rotaryEvents]
        case .loupedeckLiveS:
            [.setBrightness, .setKeyImage, .fillKey, .setScreenImage, .fillScreen, .keyPressEvents, .rotaryEvents]
        case .razerStreamController:
            [.setBrightness, .setKeyImage, .fillKey, .setScreenImage, .fillScreen, .keyPressEvents, .rotaryEvents]
        case .razerStreamControllerX:
            [.setBrightness, .setKeyImage, .fillKey, .setScreenImage, .fillScreen, .keyPressEvents]
        }
    }

    public var capabilities: DeviceCapabilities {
        DeviceCapabilities(
            keyCount: keyCount,
            keySize: keySize,
            keyRows: keyRows,
            keyColumns: keyColumns,
            dialCount: 0,
            screenSize: screenSize,
            keyAreaRect: CGRect(x: padding.x, y: padding.y, width: screenSize.width - padding.x * 2, height: screenSize.height - padding.y * 2),
            keyHorizontalSpacing: (screenSize.width - keySize.width * CGFloat(keyColumns) - padding.x * 2) / CGFloat(keyColumns - 1),
            keyVerticalSpacing: (screenSize.height - keySize.height * CGFloat(keyRows) - padding.y * 2) / CGFloat(keyRows - 1),
            imageFormat: .rgb565,
            transform: .identity,
            features: features
        )
    }

    var buttonIndexOffset: Int {
        switch self {
        case .loupedeckLive: 0x7
        case .loupedeckCT: 0x7
        case .loupedeckLiveS: 0x7
        case .razerStreamController: 0x7
        case .razerStreamControllerX: 0x1b
        }
    }

    func buttonRect(at index: Int) -> CGRect {
        let col = index % capabilities.keyColumns
        let row = index / capabilities.keyColumns

        let width = capabilities.keySize?.width ?? 0
        let height = capabilities.keySize?.height ?? 0

        let x = CGFloat(index % capabilities.keyColumns) * width
        let y = floor(CGFloat(index / capabilities.keyColumns)) * height

        return CGRect(x: capabilities.keyAreaLeadingSpacing + width * CGFloat(col) + capabilities.keyHorizontalSpacing * CGFloat(col),
                      y: capabilities.keyAreaTopSpacing + height * CGFloat(row) + capabilities.keyVerticalSpacing * CGFloat(row),
                      width: width,
                      height: height)
    }


}
