import Compression
import Foundation

/// Reads a game's scripts and guesses the controller it wants. Scripts
/// live in Data/Scripts.rxdata (.rvdata, .rvdata2): a Marshal array of
/// [id, name, zlib(code)]. Newer Essentials also keeps .rb files in
/// Data/Scripts and Plugins. Encrypted games hide their scripts: they
/// get the 2-button controller.
enum ScriptScanner {
    static func suggestion(for folder: URL) -> ControllerType {
        let code = scripts(in: folder)
        guard !code.isEmpty else { return .classic2 }
        return suggestion(forCode: code)
    }

    static func suggestion(forCode code: String) -> ControllerType {
        // A real stick (games made for mkxp-z) or an action battle system.
        let modern = [#"axes_left"#, #"axes_right"#, #"\bXAS\b"#, #"Falcao"#, #"\bPearl\b.*\bABS\b"#,
                      #"Sapphire Action System"#, #"\bABS\b"#]
        if modern.contains(where: { code.range(of: $0, options: .regularExpression) != nil }) {
            return .modern
        }
        // Input::X and Input::Y (the A and S keys on a PC) in use.
        let extra = code.matches(of: #"Input::(X|Y)\b"#)
        return extra >= 3 ? .classic4 : .classic2
    }

    /// All the script text of a game, as far as it can be read.
    static func scripts(in folder: URL) -> String {
        let fm = FileManager.default
        var text = ""
        let data = folder.appendingPathComponent("Data")
        let names = (try? fm.contentsOfDirectory(atPath: data.path)) ?? []
        if let file = names.first(where: { $0.lowercased().hasPrefix("scripts.") && !$0.hasPrefix(".") }),
           let blob = try? Data(contentsOf: data.appendingPathComponent(file)) {
            text += marshalScripts(blob).joined(separator: "\n")
        } else if let blob = RGSSArchive.scripts(inGameFolder: folder) {
            // Encrypted game: the scripts file inside Game.rgssad / .rgss2a / .rgss3a.
            text += marshalScripts(blob).joined(separator: "\n")
        }
        for sub in ["Data/Scripts", "Plugins"] {
            let root = folder.appendingPathComponent(sub)
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension.lowercased() == "rb" {
                if let source = try? String(contentsOf: url, encoding: .utf8) { text += "\n" + source }
                if text.utf8.count > 40_000_000 { break }
            }
        }
        return text
    }

    /// The code of each script in a Scripts.r*data file.
    static func marshalScripts(_ data: Data) -> [String] {
        var reader = MarshalReader(bytes: [UInt8](data))
        guard case .array(let entries)? = try? reader.read() else { return [] }
        return entries.compactMap { entry in
            guard case .array(let fields) = entry, fields.count >= 3,
                  case .bytes(let zipped) = fields[2] else { return nil }
            return inflate(zipped).flatMap { String(data: $0, encoding: .utf8) ?? String(data: $0, encoding: .isoLatin1) }
        }
    }

    /// zlib (with its 2-byte header) to plain bytes.
    static func inflate(_ zipped: [UInt8]) -> Data? {
        guard zipped.count > 2 else { return nil }
        let body = Array(zipped.dropFirst(2))
        var capacity = max(body.count * 6, 4096)
        for _ in 0..<6 {
            var output = [UInt8](repeating: 0, count: capacity)
            let written = body.withUnsafeBufferPointer { src in
                compression_decode_buffer(&output, capacity, src.baseAddress!, body.count, nil, COMPRESSION_ZLIB)
            }
            if written == 0 { return nil }
            if written < capacity { return Data(output.prefix(written)) }
            capacity *= 4
        }
        return nil
    }
}

private extension String {
    func matches(of pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(in: self, range: NSRange(startIndex..., in: self))
    }
}

/// Just enough of Ruby's Marshal format to read a scripts file: arrays,
/// integers, strings (with or without encoding), symbols and nil.
struct MarshalReader {
    enum Value {
        case array([Value])
        case int(Int)
        case bytes([UInt8])
        case symbol(String)
        case other
    }

    enum Failure: Error { case unsupported(UInt8), truncated }

    private let bytes: [UInt8]
    private var position = 2  // after the 4.8 version
    private var symbols: [String] = []

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func read() throws -> Value {
        let type = try byte()
        switch type {
        case 0x5B:  // [ array
            let count = try int()
            var items: [Value] = []
            items.reserveCapacity(max(count, 0))
            for _ in 0..<max(count, 0) { items.append(try read()) }
            return .array(items)
        case 0x69:  // i fixnum
            return .int(try int())
        case 0x22:  // " string
            return .bytes(try chunk())
        case 0x49:  // I: object with instance variables (a string's encoding)
            let inner = try read()
            let count = try int()
            for _ in 0..<max(count, 0) {
                _ = try read()
                _ = try read()
            }
            return inner
        case 0x3A:  // : symbol
            let name = String(decoding: try chunk(), as: UTF8.self)
            symbols.append(name)
            return .symbol(name)
        case 0x3B:  // ; symbol link
            let index = try int()
            return index < symbols.count ? .symbol(symbols[index]) : .other
        case 0x40:  // @ object link
            _ = try int()
            return .other
        case 0x30, 0x54, 0x46:  // nil, true, false
            return .other
        default:
            throw Failure.unsupported(type)
        }
    }

    private mutating func byte() throws -> UInt8 {
        guard position < bytes.count else { throw Failure.truncated }
        defer { position += 1 }
        return bytes[position]
    }

    private mutating func int() throws -> Int {
        let c = Int8(bitPattern: try byte())
        if c == 0 { return 0 }
        if c > 0 && c <= 4 {
            var value = 0
            for i in 0..<Int(c) { value |= Int(try byte()) << (8 * i) }
            return value
        }
        if c < 0 && c >= -4 {
            var value = -1
            for i in 0..<Int(-c) {
                value &= ~(0xFF << (8 * i))
                value |= Int(try byte()) << (8 * i)
            }
            return value
        }
        return c > 0 ? Int(c) - 5 : Int(c) + 5
    }

    private mutating func chunk() throws -> [UInt8] {
        let length = try int()
        guard length >= 0, position + length <= bytes.count else { throw Failure.truncated }
        defer { position += length }
        return Array(bytes[position..<position + length])
    }
}

/// RPG Maker's encrypted archives (Game.rgssad, .rgss2a, .rgss3a): only
/// to find Data/Scripts.* inside. Version 1 (XP, VX) and 3 (VX Ace).
enum RGSSArchive {
    static func scripts(inGameFolder folder: URL) -> Data? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard let name = names.first(where: { ["rgssad", "rgss2a", "rgss3a"].contains(($0 as NSString).pathExtension.lowercased()) }),
              let data = try? Data(contentsOf: folder.appendingPathComponent(name), options: .mappedIfSafe)
        else { return nil }
        return scripts(in: [UInt8](data))
    }

    static func scripts(in bytes: [UInt8]) -> Data? {
        guard bytes.count > 8, Array(bytes[0..<6]) == Array("RGSSAD".utf8) else { return nil }
        switch bytes[7] {
        case 1: return version1(bytes)
        case 3: return version3(bytes)
        default: return nil
        }
    }

    private static func u32(_ b: [UInt8], _ at: Int) -> UInt32? {
        guard at + 4 <= b.count else { return nil }
        return UInt32(b[at]) | UInt32(b[at + 1]) << 8 | UInt32(b[at + 2]) << 16 | UInt32(b[at + 3]) << 24
    }

    private static func isScripts(_ name: String) -> Bool {
        let lower = name.replacingOccurrences(of: "\\", with: "/").lowercased()
        return lower.hasPrefix("data/scripts.")
    }

    private static func version1(_ b: [UInt8]) -> Data? {
        var key: UInt32 = 0xDEADCAFE
        func next() { key = key &* 7 &+ 3 }
        var at = 8
        while at < b.count {
            guard let rawLength = u32(b, at) else { return nil }
            let length = Int(rawLength ^ key); next(); at += 4
            guard length > 0, length < 4096, at + length <= b.count else { return nil }
            var nameBytes: [UInt8] = []
            for i in 0..<length {
                nameBytes.append(b[at + i] ^ UInt8(key & 0xFF)); next()
            }
            at += length
            guard let rawSize = u32(b, at) else { return nil }
            let size = Int(rawSize ^ key); next(); at += 4
            guard size >= 0, at + size <= b.count else { return nil }
            if isScripts(String(decoding: nameBytes, as: UTF8.self)) {
                return decrypt(b, from: at, size: size, key: key)
            }
            at += size
        }
        return nil
    }

    private static func version3(_ b: [UInt8]) -> Data? {
        guard let seed = u32(b, 8) else { return nil }
        let key = seed &* 9 &+ 3
        var at = 12
        while at < b.count {
            guard let rawOffset = u32(b, at), let rawSize = u32(b, at + 4),
                  let rawKey = u32(b, at + 8), let rawLength = u32(b, at + 12) else { return nil }
            let offset = Int(rawOffset ^ key)
            if offset == 0 { return nil }
            let size = Int(rawSize ^ key), fileKey = rawKey ^ key, length = Int(rawLength ^ key)
            at += 16
            guard length > 0, length < 4096, at + length <= b.count else { return nil }
            var nameBytes: [UInt8] = []
            for i in 0..<length {
                nameBytes.append(b[at + i] ^ UInt8((key >> (8 * UInt32(i % 4))) & 0xFF))
            }
            at += length
            if isScripts(String(decoding: nameBytes, as: UTF8.self)) {
                guard offset >= 0, offset + size <= b.count else { return nil }
                return decrypt(b, from: offset, size: size, key: fileKey)
            }
        }
        return nil
    }

    /// The file's bytes, XORed four at a time with a key that advances.
    private static func decrypt(_ b: [UInt8], from start: Int, size: Int, key start0: UInt32) -> Data {
        var key = start0
        var out = [UInt8](repeating: 0, count: size)
        var i = 0
        while i < size {
            for j in 0..<4 where i + j < size {
                out[i + j] = b[start + i + j] ^ UInt8((key >> (8 * UInt32(j))) & 0xFF)
            }
            key = key &* 7 &+ 3
            i += 4
        }
        return Data(out)
    }
}
