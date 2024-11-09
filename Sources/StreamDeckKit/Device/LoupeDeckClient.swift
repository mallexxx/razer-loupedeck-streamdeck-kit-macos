//
//   LoupedeckClient.swift
//  StreamDeckKit
//
//  Created by Alexey Martemyanov on 06.11.2024.
//

import Foundation
import IOKit
import OSLog
import StreamDeckCApi
import SwiftSerial

final class LoupedeckClient {

    enum Command: UInt8 {
        case getSerialNumber = 0x03
        case getVersion = 0x07
        case setBrightness = 0x09
        case setVibration =  0x1B
        case setColor = 0x02
        case drawFramebuffer = 0x10
        case refreshScreen = 0x0F
    }
    enum Screen: UInt16 {
        case left = 0x004C
        case right = 0x0052
        case middle = 0x0041
        case center = 0x004D
        case wheel = 0x0057
    }

    enum Event: UInt8 {
        case press
        case confirm
        case rotate
        case reset
        case touchmove
        case touchend
        case mcu

        init?(rawValue: RawValue) {
            switch rawValue {
            case 0x00: self = .press
            case 0x01: self = .rotate
            case 0x02: self = .confirm
            case 0x06: self = .reset
            case 0x4d: self = .touchmove
            case 0x6d: self = .touchend
            case 0x52: self = .touchmove
            case 0x72: self = .touchend
            case 0x0d: self = .mcu
            default: return nil
            }
        }
    }

    enum ClientError: Error {
        case couldNotGetTtyPath
        case portUnavailable
        case unexpectedPacketSize(expected: Int, actual: Int)
        case portClosed
    }

    let device:  LoupedeckDevice

    private var service: io_service_t
    private var connection: io_connect_t = IO_OBJECT_NULL

    private var serialPort: SerialPort?
    private var readingTask: Task<Void, Error>?
    private var packets = AsyncStream<Packet> { continuation in continuation.finish() }

    private var errorHandler: ClientErrorHandler?

    private var transactionId: UInt64 = 0
    private func nextTransactionId() -> UInt8 {
        transactionId += 1
        let id = transactionId.remainderReportingOverflow(dividingBy: 256).partialValue
        if id == 0 {
            transactionId += 1
            return 1
        }
        return UInt8(id)
    }

    var description: String {
        "<LoupedeckClient \(Unmanaged.passUnretained(self).toOpaque().debugDescription) \(String(format: "%04X", device.vendorId)):\(String(format: "%04X", device.productId))>"
    }

    init?(service: io_service_t) {
        guard let vendorID = IORegistryEntryCreateCFProperty(service, kUSBVendorID as CFString, kCFAllocatorDefault, 0)?.takeUnretainedValue() as? Int,
              let productID = IORegistryEntryCreateCFProperty(service, kUSBProductID as CFString, kCFAllocatorDefault, 0)?.takeUnretainedValue() as? Int,
              let device =  LoupedeckDevice(vendorId: vendorID, productId: productID) else { return nil }
        self.device = device
        self.service = service
    }

    func open() async throws {
        guard connection == IO_OBJECT_NULL else {
            fatalError("Open was already called")
        }
        guard service != IO_OBJECT_NULL else {
            fatalError("Client was already closed")
        }
        let ret = IOServiceOpen(service, mach_task_self_, 0, &connection)
        if let error = IOError(errorCode: ret) { throw error }

        guard let ttyPath = service.ttyPath else { throw ClientError.couldNotGetTtyPath }
        Logger.default.debug("\(self.description): tty path: \(ttyPath)")

        let serialPort = SerialPort(path: ttyPath)
        try serialPort.openPort(portMode: [.readWrite, .noControllingTerminal, .exclusiveLock, .nonBlocking, .closeOnExec, .sync])
        self.serialPort = serialPort
        try serialPort.setSettings(baudRateSetting: .symmetrical(.baud115200), minimumBytesToRead: 1, timeout: 1)

        try await handshake(serialPort)
        subscribeToInputEvents(serialPort)
    }

    private func handshake(_ serialPort: SerialPort) async throws {
        // Write the WebSocket handshake request
        let handshakeRequest = """
        GET /index.html HTTP/1.1
        Connection: Upgrade
        Upgrade: websocket
        Sec-WebSocket-Key: 123abc


        """

        //in case loupedeck was already in websocket mode
        var written = try serialPort.writeData(Data([0x88, 0x80, 0x00, 0x00, 0x00, 0x00]))
        Logger.default.trace("\(self.description): closeBytes sent: \(written)")

        // send data
        written = try serialPort.writeString(handshakeRequest)
        Logger.default.trace("\(self.description): handshake request sent: \(written)")

        var buffer = Data()
        let expectedResponseEndSequence = "\r\n\r\n".data(using: .utf8)!.map(\.self)
        // Read the response
        for await byte in try serialPort.asyncBytes() {
            buffer.append(byte)
            if buffer.suffix(4) == expectedResponseEndSequence { break }
        }

        Logger.default.debug("\(self.description): 👋 handshake response: \(String(data: buffer, encoding: .utf8) ?? buffer.debugDescription)")
    }

    private func subscribeToInputEvents(_ serialPort: SerialPort) {
        packets = AsyncStream<Packet> { continuation in
            readingTask = Task {
                let readStream = try serialPort.asyncBytes()
                Logger.default.debug("\(self.description): reading serial stream")

                var buffer = Data()
                var expectedLength: Int?

                for await byte in readStream {
                    if expectedLength == 0 {
                        expectedLength = Int(byte)
                        if expectedLength == 0 {
                            expectedLength = nil
                        }
                    } else if let length = expectedLength {
                        buffer.append(byte)
                        if buffer.count == length, length >= 3 {
                            expectedLength = nil
                            let packetLen = buffer[0]
                            let header = buffer[1]
                            let transactionId = buffer[2]
                            if packetLen != length {
                                Logger.default.error("\(self.description): length \(packetLen) does not match expected \(length)")
                            }
                            continuation.yield(Packet(header: header, transactionId: transactionId, data: buffer.dropFirst(3)))
                            buffer.removeAll(keepingCapacity: true)
                        }
                    } else if byte == 0x82 {
                        expectedLength = 0
                    } else {
                        Logger.default.error("\(self.description): Unexpected \(String(format: "%02X", byte)): dropping")
                    }
                }
                Logger.default.debug("\(self.description): closing reading stream")
                continuation.finish()
            }
        }
    }

    func close() {
        readingTask?.cancel()
        readingTask = nil
        packets = AsyncStream<Packet> { continuation in continuation.finish() }
        serialPort?.closePort()
        serialPort = nil
        if connection != IO_OBJECT_NULL {
            IOServiceClose(connection)
            IOObjectRelease(connection)
            connection = IO_OBJECT_NULL
        }
        if service != IO_OBJECT_NULL {
            IOObjectRelease(service)
            service = IO_OBJECT_NULL
        }
    }

    deinit {
        close()
    }

    func getVersion() async -> Version? {
        guard let data = try? await getResponse(for: .getVersion).data, data.count >= 3 else { return nil }
        return Version(data: data)
    }

    func getSerialNumber() async -> String? {
        (try? await getResponse(for: .getSerialNumber)).flatMap { String(data: $0.data, encoding: .utf8)?.trimmingCharacters(in: .whitespaces) }
    }

    func getDeviceInfo() async -> DeviceInfo? {
        guard let serialNumber = await getSerialNumber(),
              let _ = await getVersion() else { return nil }

        return DeviceInfo(
            vendorID: device.vendorId,
            productID: device.productId,
            manufacturer: device.vendor.name,
            productName: device.productName,
            serialNumber: serialNumber
        )
    }

    func getDeviceCapabilities() -> DeviceCapabilities? {
        device.capabilities
    }

    private func getStruct<Value>(_ command: Command) async throws -> Value {
        let packet = try await getResponse(for: command, MemoryLayout<Value>.size)

        return packet.data.withUnsafeBytes { buffer in
            buffer.baseAddress!.assumingMemoryBound(to: Value.self).pointee
        }
    }

    private func getResponse(for command: Command, _ size: Int? = nil) async throws -> Packet {
        let transactionId = try send(command)
        for await packet in packets {
            guard packet.transactionId == transactionId else { continue }
            guard size == nil || packet.size == size else {
                Logger.default.error("\(self.description): unexpected packet size for \(String(describing: command)): \(packet.size), expected: \(size!)")
                throw ClientError.unexpectedPacketSize(expected: size!, actual: packet.size)
            }

            return packet
        }
        Logger.default.error("\(self.description): Error getting response for \(String(describing: command)): port closed")
        errorHandler?(.disconnected(reason: "port closed"))
        throw ClientError.portClosed
    }

    @MainActor
    func setInputEventHandler(_ handler: @escaping InputEventHandler) {
        Task { @MainActor [packets] in
            for await packet in self.packets {
                inputEventHandler(packet, handler: handler)
            }
        }
    }

    @MainActor
    private func inputEventHandler(_ packet: Packet, handler: @escaping InputEventHandler) {
        guard packet.transactionId == 0 else { return }

        switch Event(rawValue: packet.header) {
        case .press:
            guard packet.size >= 2 else {
                assertionFailure("Unexpected Press packet size \(packet.size)")
                return
            }
            var button = Int(packet.data[packet.data.startIndex])
            let state = (packet.data[packet.data.startIndex + 1] == 0)
            if button >= device.buttonIndexOffset {
                button -= device.buttonIndexOffset
                handler(.keyPress(index: button, pressed: state))
            } else if button >= 1 {
                handler(.rotaryEncoderPress(index: button - 1, pressed: state))
            } else {
                assertionFailure("Unexpected Button index \(button)")
            }

        case .rotate:
            guard packet.size >= 2 else {
                assertionFailure("Unexpected Press packet size \(packet.size)")
                return
            }
            let index = Int(packet.data[packet.data.startIndex])
            guard index >= 1 else { assertionFailure("Unexpected index \(index)"); return }

            let delta = Int(packet.data[packet.data.startIndex + 1])
            handler(.rotaryEncoderRotation(index: index - 1, rotation: delta))

        case .touchmove:
            fatalError("not implemented")
//            case SDInputEventType_Touch.rawValue:
//                inputEventHandler?(.touch(.init(
//                    x: Int(event.touch.x),
//                    y: Int(event.touch.y))
//                ))
//
//            case SDInputEventType_Fling.rawValue:
//                let fling = event.fling
//                inputEventHandler?(.fling(
//                    start: .init(x: Int(fling.startX), y: Int(fling.startY)),
//                    end: .init(x: Int(fling.endX), y: Int(fling.endY))
//                ))
        case .touchend:
            fatalError("not implemented")
        default:
            Logger.default.trace("[\(packet.transactionId)] response: \(packet.header.description):\(packet.data.hexEncoded())")
        }
    }

    private func send(_ command: Command, _ data: Data = Data()) throws -> UInt8 {
        guard let serialPort else { throw ClientError.portUnavailable }

        let transactionId = nextTransactionId()
        let payloadSize = 3 + data.count
        var payload = Data([
            data.count >= 0xff ? 0xff : UInt8(payloadSize),
            command.rawValue,
            transactionId
        ])

        if data.count > 0 {
            payload.append(data)
        }

        var header: Data
        if (payloadSize > 125) {
            header = Data(count: 14)
            header[0] = 0x82
            header[1] = 0xff
            header.replaceSubrange(6..<(6 + MemoryLayout<UInt32>.size), with: withUnsafeBytes(of: UInt32(payloadSize).bigEndian) { Data($0) })
        }
        // Small messages
        else {
            // Prepend each message with a send indicating the length to come
            header = Data(count: 6)
            header[0] = 0x82
            header[1] = 0x80 + UInt8(payloadSize)
        }

//        Logger.default.trace("[\(transactionId)] sending \(header.hexEncoded()) : \(payload[0..<min(payload.count, 255)].hexEncoded())")

        do {
            var written = try serialPort.writeData(header)
            written += try serialPort.writeData(payload)
            assert(written == header.count + payload.count)
        } catch {
            Logger.default.error("\(self.description): Error sending \(String(describing: command)): \(error.localizedDescription)")
            errorHandler?(.disconnected(reason: error.localizedDescription))
            throw error
        }

        return transactionId
    }


}

extension  LoupedeckClient: StreamDeckClientDeviceProtocol {

    func setErrorHandler(_ handler: @escaping ClientErrorHandler) {
        errorHandler = handler
    }

    func setBrightness(_ brightness: Int /* 0...100 */) {
        try? send(.setBrightness, Data([UInt8(brightness / 10 /* 0...10 */)]))
    }

    func setKeyImage(_ imageData: Data, at index: Int) {
        let rect = device.buttonRect(at: index)

        var data = Data(capacity: Int(rect.width) * Int(rect.height) * 2 + 10)
        data.append(withUnsafeBytes(of: /*screen*/Screen.center.rawValue.bigEndian) { Data($0) })

        data.append(withUnsafeBytes(of: UInt16(rect.minX).bigEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(rect.minY).bigEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(rect.width).bigEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(rect.height).bigEndian) { Data($0) })

        data.append(imageData)

        try? send(.drawFramebuffer, data)
        try? send(.refreshScreen)
    }

    func setScreenImage(_ imageData: Data) {
        let rect = CGRect(origin: .zero, size: device.capabilities.screenSize ?? .zero)

        var data = Data(capacity: Int(rect.width) * Int(rect.height) * 2 + 10)
        data.append(withUnsafeBytes(of: /*screen*/Screen.center.rawValue.bigEndian) { Data($0) })

        data.append(withUnsafeBytes(of: UInt16(rect.minX).bigEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(rect.minY).bigEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(rect.width).bigEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(rect.height).bigEndian) { Data($0) })

        data.append(imageData)

        try? send(.drawFramebuffer, data)
    }

    func setWindowImage(_ imageData: Data) {
        let rect = CGRect(origin: .zero, size: device.capabilities.screenSize ?? .zero)

        var data = Data(capacity: Int(rect.width) * Int(rect.height) * 2 + 10)
        data.append(withUnsafeBytes(of: /*screen*/Screen.center.rawValue.bigEndian) { Data($0) })

        data.append(withUnsafeBytes(of: UInt16(rect.minX).bigEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(rect.minY).bigEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(rect.width).bigEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(rect.height).bigEndian) { Data($0) })

        data.append(imageData)

        try? send(.drawFramebuffer, data)
    }

    func setWindowImage(_ imageData: Data, at rect: CGRect) {
        var data = Data(capacity: Int(rect.width) * Int(rect.height) * 2 + 10)
        data.append(withUnsafeBytes(of: /*screen*/Screen.center.rawValue.bigEndian) { Data($0) })

        data.append(withUnsafeBytes(of: UInt16(rect.minX).bigEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(rect.minY).bigEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(rect.width).bigEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(rect.height).bigEndian) { Data($0) })

        data.append(imageData)

        try? send(.drawFramebuffer, data)
    }

    func fillScreen(red: UInt8, green: UInt8, blue: UInt8) {
        let color = UIColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
        let size = device.capabilities.screenSize ?? CGSize(width: 1, height: 1)
        let image = UIImage.sdk_colored(color, size: size)
        let data = image.rgb565data(with: size)
        setScreenImage(data)
    }

    func fillKey(red: UInt8, green: UInt8, blue: UInt8, at index: Int) {
        let color = UIColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
        let size = device.capabilities.keySize ?? CGSize(width: 1, height: 1)
        let image = UIImage.sdk_colored(color, size: size)
        let data = image.rgb565data(with: size)
        setKeyImage(data, at: index)
    }

    func showLogo() {
    }

}

private extension  LoupedeckClient {
    struct Packet: CustomDebugStringConvertible {
        var header: UInt8
        var transactionId: UInt8
        var data: Data
        var size: Int { data.count }

        var debugDescription: String {
            let utf8String = String(data: data, encoding: .utf8)
            let str = (utf8String != nil && header == 0x73) ? "\"" + utf8String! + "\"" : data.hexEncoded()
            return "Packet(\(header), transactionId: \(transactionId), data: \(str))"
        }
    }

}

private extension Version {
    init(data: Data) {
        self.major = Int(data[data.startIndex])
        self.minor = Int(data[data.startIndex + 1])
        self.patch = Int(data[data.startIndex + 2])
    }
}
