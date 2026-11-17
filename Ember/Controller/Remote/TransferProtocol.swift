import Foundation
import Network

/// Sending games from the iPhone to Ember on a Mac, nearby: no iCloud,
/// no shared Wi-Fi needed (peer-to-peer on, as AirDrop).
///
/// The Mac's library advertises `_ember-xfer._tcp` with the Mac's name.
/// The iPhone offers a list of games; the Mac asks its user and answers
/// with the ones it takes; then each game comes file by file: the game
/// folder, its UserData saves and its save states, under the same game
/// id as on the iPhone (iCloud save sync pairs games by id).
///
/// Messages: 4 bytes of length (big endian), 1 byte of kind, payload.
enum TransferProtocol {
    static let serviceType = "_ember-xfer._tcp"
    /// File bytes travel in pieces of this size.
    static let chunkSize = 1 << 20

    enum Kind: UInt8 {
        /// iPhone → Mac: `Offer` as JSON.
        case offer = 1
        /// Mac → iPhone: the ids taken, as JSON (empty: declined).
        case answer = 2
        /// iPhone → Mac: `FileHeader` as JSON; its bytes follow as chunks.
        case file = 3
        /// iPhone → Mac: raw bytes of the current file.
        case chunk = 4
        /// iPhone → Mac: a game is complete (its id).
        case gameDone = 5
        /// iPhone → Mac: everything was sent.
        case done = 6
    }

    struct Offer: Codable {
        struct Game: Codable, Identifiable {
            let id: String
            let title: String
            let bytes: Int64
        }
        let device: String
        let games: [Game]
    }

    enum Area: String, Codable {
        /// Games/<id>/…
        case game
        /// UserData/<id>/…
        case userData
        /// Application Support/States/<id>/…
        case states
        /// Application Support/Covers/<id>.jpg and <id>-custom.jpg
        case covers
    }

    struct FileHeader: Codable {
        let id: String
        let area: Area
        /// Relative to the area's folder.
        let path: String
        let size: Int64
        let modified: Date
    }

    static var parameters: NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveInterval = 10
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }

    static func encode(_ kind: Kind, _ payload: Data = Data()) -> Data {
        let length = UInt32(payload.count + 1)
        var data = Data([UInt8(length >> 24), UInt8((length >> 16) & 0xFF), UInt8((length >> 8) & 0xFF),
                         UInt8(length & 0xFF), kind.rawValue])
        data.append(payload)
        return data
    }

    static func encode<T: Encodable>(_ kind: Kind, json value: T) -> Data {
        encode(kind, (try? JSONEncoder().encode(value)) ?? Data())
    }

    /// Reads one message, then calls `handle`; the caller asks for the
    /// next one when ready (so a slow disk slows the sender down).
    static func receiveOne(on connection: NWConnection,
                           _ handle: @escaping @Sendable (Kind?, Data) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { header, _, _, error in
            guard let header, header.count == 4, error == nil else { return handle(nil, Data()) }
            let bytes = [UInt8](header)
            let length = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
            guard length > 0, length <= chunkSize + 1024 else { return handle(nil, Data()) }
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { body, _, _, error in
                guard let body, body.count == length, error == nil else { return handle(nil, Data()) }
                handle(Kind(rawValue: body[body.startIndex]), Data(body.dropFirst()))
            }
        }
    }

    /// A relative path with nothing that climbs out of its folder.
    static func safePath(_ path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." }
        guard !parts.isEmpty, !parts.contains(".."), !path.hasPrefix("/") else { return nil }
        return parts.joined(separator: "/")
    }

    static func safeID(_ id: String) -> Bool {
        !id.isEmpty && !id.contains("/") && id != "." && id != ".." && !id.hasPrefix(".")
    }
}
