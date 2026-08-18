import Foundation

struct BridgeResponse: Decodable {
    let ok: Bool
    let error: String?
    let result: JSONValue?
}

enum JSONValue: Decodable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }
}

private struct BridgeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class AssetToolsBridge {
    static let shared = AssetToolsBridge()

    private let lock = NSLock()
    private var initialized = false

    private init() {}

    func initialize() throws {
        try lock.withLock {
            if initialized { return }
            let status = uae_bridge_initialize()
            guard status == 0 else {
                throw BridgeError(message: "Native asset bridge initialization failed (status \(status)).")
            }
            initialized = true
        }
    }

    func execute(_ request: [String: Any]) throws -> BridgeResponse {
        try initialize()
        let data = try JSONSerialization.data(withJSONObject: request, options: [])
        let responseData = try data.withUnsafeBytes { rawBuffer -> Data in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw BridgeError(message: "Unable to create bridge request.")
            }
            let result = uae_bridge_execute(baseAddress.assumingMemoryBound(to: UInt8.self), Int32(data.count))
            guard let result else {
                throw BridgeError(message: "Native bridge returned a null response.")
            }
            defer { uae_bridge_free(result) }
            return Data(bytes: result, count: strlen(result))
        }
        let response = try JSONDecoder().decode(BridgeResponse.self, from: responseData)
        if !response.ok {
            throw BridgeError(message: response.error ?? "Native bridge request failed.")
        }
        return response
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

@_silgen_name("uae_bridge_initialize")
private func uae_bridge_initialize() -> Int32

@_silgen_name("uae_bridge_execute")
private func uae_bridge_execute(_ request: UnsafePointer<UInt8>, _ requestLength: Int32) -> UnsafeMutablePointer<CChar>?

@_silgen_name("uae_bridge_free")
private func uae_bridge_free(_ value: UnsafeMutablePointer<CChar>)
