import Foundation
import Network

/// The iPhone as the Mac's controller ("Usar como controle").
///
/// A game running on the Mac advertises a Bonjour service, `_ember-ctl._tcp`,
/// with peer-to-peer on (the same direct link AirDrop uses), so an iPhone
/// finds it without sharing a Wi-Fi network. The iPhone connects over TCP
/// and sends what its buttons do; the Mac applies the game's control
/// profile (ControlMapper), as it would on the iPhone itself.
///
/// Messages: 2 bytes of length (big endian), 1 byte of kind, then the
/// payload as UTF-8 text.
enum RemoteProtocol {
    static let serviceType = "_ember-ctl._tcp"

    enum Kind: UInt8 {
        /// iPhone → Mac: the iPhone's name.
        case hello = 1
        /// Mac → iPhone: "<controller type>|<game title>".
        case info = 2
        /// iPhone → Mac: a ControlButton's raw value.
        case buttonDown = 3
        case buttonUp = 4
        /// iPhone → Mac: a ControlDirection's raw value.
        case directionDown = 5
        case directionUp = 6
        /// iPhone → Mac: text typed on the iPhone's keyboard.
        case text = 7
        /// iPhone → Mac: "enter" or "backspace".
        case key = 8
        /// iPhone → Mac: a menu command (see `Command`).
        case command = 9
        /// iPhone → Mac: let go of everything (the app left the screen).
        case releaseAll = 10
    }

    enum Command: String {
        case saveState = "save"
        case loadState = "load"
        case cheats
        case quit
        /// "speed:<n>"
        case speed
    }

    /// TCP without delay, peer-to-peer allowed: every press goes out at once.
    static var parameters: NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveInterval = 5
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }

    static func encode(_ kind: Kind, _ payload: String = "") -> Data {
        let body = Data(payload.utf8)
        let length = UInt16(body.count + 1)
        var data = Data([UInt8(length >> 8), UInt8(length & 0xFF), kind.rawValue])
        data.append(body)
        return data
    }

    /// Reads messages off a connection, one after another, until it ends.
    static func receive(on connection: NWConnection, _ handle: @escaping @Sendable (Kind, String) -> Void,
                        ended: @escaping @Sendable () -> Void) {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { header, _, done, error in
            guard let header, header.count == 2, error == nil else { return ended() }
            let length = Int(header[header.startIndex]) << 8 | Int(header[header.startIndex + 1])
            guard length > 0 else { return ended() }
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { body, _, _, error in
                guard let body, body.count == length, error == nil else { return ended() }
                if let kind = Kind(rawValue: body[body.startIndex]) {
                    handle(kind, String(decoding: body.dropFirst(), as: UTF8.self))
                }
                if done { return ended() }
                receive(on: connection, handle, ended: ended)
            }
        }
    }
}
