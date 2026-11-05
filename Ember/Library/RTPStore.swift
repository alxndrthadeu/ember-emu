import Foundation

/// The RPG Maker "Run Time Package": the stock graphics and sounds many
/// games leave out and expect Windows to have installed (on a PC, in
/// Common Files\Enterbrain\RGSS). Ember ships none: the player imports
/// each one once, as a folder or archive, and every game of that
/// version reads from it.
enum RTPStore {
    enum Kind: String, CaseIterable, Identifiable {
        case xp, vx, vxace
        var id: String { rawValue }

        /// The game's RGSS version (1 XP, 2 VX, 3 VX Ace).
        init?(rgss: Int) {
            switch rgss {
            case 1: self = .xp
            case 2: self = .vx
            case 3: self = .vxace
            default: return nil
            }
        }

        var shortName: String {
            switch self {
            case .xp: "XP"
            case .vx: "VX"
            case .vxace: "VX Ace"
            }
        }

        var name: String {
            switch self {
            case .xp: "RPG Maker XP"
            case .vx: "RPG Maker VX"
            case .vxace: "RPG Maker VX Ace"
            }
        }
    }

    static var root: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("RTP", isDirectory: true)
    }

    static func folder(for kind: Kind) -> URL {
        root.appendingPathComponent(kind.rawValue, isDirectory: true)
    }

    static func isInstalled(_ kind: Kind) -> Bool {
        let graphics = folder(for: kind).appendingPathComponent("Graphics")
        return FileManager.default.fileExists(atPath: graphics.path)
    }

    /// The RTP a game reads from, when installed.
    static func path(forRGSS rgss: Int?) -> String? {
        guard let kind = rgss.flatMap(Kind.init(rgss:)), isInstalled(kind) else { return nil }
        return folder(for: kind).path
    }

    static func delete(_ kind: Kind) {
        try? FileManager.default.removeItem(at: folder(for: kind))
    }

    // MARK: - Recognizing one

    /// An RTP is Graphics and Audio with no game around them. The
    /// folders tell the version apart: only XP has Autotiles, only
    /// VX Ace has Battlebacks1.
    static func kind(of folder: URL) -> Kind? {
        guard !GameFolder.looksLikeGame(folder) else { return nil }
        let names = Set(contents(of: folder).map { $0.lowercased() })
        guard names.contains("graphics"), names.contains("audio") else { return nil }
        let graphics = Set(contents(of: folder.appendingPathComponent(match("Graphics", in: folder)))
            .map { $0.lowercased() })
        if graphics.contains("autotiles") { return .xp }
        if graphics.contains("battlebacks1") { return .vxace }
        if graphics.contains("system") { return .vx }
        return nil
    }

    /// Finds the RTP inside an extracted archive or a picked folder.
    static func findRoot(in folder: URL, depth: Int = 4) -> (URL, Kind)? {
        if let kind = kind(of: folder) { return (folder, kind) }
        guard depth > 0 else { return nil }
        for name in contents(of: folder) where !name.hasPrefix(".") && name != "__MACOSX" {
            let child = folder.appendingPathComponent(name)
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if let found = findRoot(in: child, depth: depth - 1) { return found }
        }
        return nil
    }

    /// Moves an unpacked RTP into place, replacing an older copy.
    static func install(_ source: URL, as kind: Kind) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let target = folder(for: kind)
        try? fm.removeItem(at: target)
        try fm.moveItem(at: source, to: target)
    }

    // MARK: - Missing files

    /// The file a "file not found" error names: the engine words it in
    /// English, or in Japanese for RGSS1 games.
    static func missingFile(in message: String) -> String? {
        let patterns = [#"ファイル (.+?) が見つかりません"#,
                        #"Unable to find (?:file )?[“"']?([^“”"'\n]+)"#,
                        #"No such file or directory[^\n]*?- ([^\n]+)"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
                  let range = Range(match.range(at: 1), in: message)
            else { continue }
            return message[range].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// RTP files live in these folders; a game's own data does not.
    static func isRTPAsset(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasPrefix("graphics/") || lower.hasPrefix("audio/")
    }

    private static func match(_ name: String, in folder: URL) -> String {
        contents(of: folder).first { $0.lowercased() == name.lowercased() } ?? name
    }

    private static func contents(of folder: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }
}
