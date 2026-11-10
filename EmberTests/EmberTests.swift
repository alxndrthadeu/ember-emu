import Compression
import XCTest
@testable import Ember

/// Logic that runs without a game: script detection, controller
/// layouts, skin conversion helpers, keys and names.
final class ScriptScannerTests: XCTestCase {
    func testModernFromStickAPI() {
        XCTAssertEqual(ScriptScanner.suggestion(forCode: "x, y = Input::Controller.axes_left"), .modern)
    }

    func testModernFromActionBattleSystem() {
        XCTAssertEqual(ScriptScanner.suggestion(forCode: "module XAS\nend"), .modern)
    }

    func testFourButtonsFromXAndY() {
        let code = "if Input.trigger?(Input::X)\nend\nInput.press?(Input::Y)\nInput.trigger?(Input::X)"
        XCTAssertEqual(ScriptScanner.suggestion(forCode: code), .classic4)
    }

    func testTwoButtonsByDefault() {
        XCTAssertEqual(ScriptScanner.suggestion(forCode: "Input.trigger?(Input::C)"), .classic2)
        XCTAssertEqual(ScriptScanner.suggestion(forCode: "Input::X once"), .classic2)
    }

    /// A Scripts.rxdata (Ruby 1.8, plain strings) and a Scripts.rvdata2
    /// (Ruby 1.9, strings with an encoding) are both read.
    func testMarshalScriptsBothStringForms() throws {
        let sources = ["class Scene_Map; end", "Input::X"]
        for wrapped in [false, true] {
            let data = Self.scriptsFile(sources, encodingWrapped: wrapped)
            XCTAssertEqual(ScriptScanner.marshalScripts(data), sources, "wrapped: \(wrapped)")
        }
    }

    func testInflateRejectsGarbage() {
        XCTAssertNil(ScriptScanner.inflate([1, 2, 3, 4, 5]))
    }

    // MARK: Fixture

    /// [[id, name, zlib(code)], ...] in Ruby's Marshal format.
    static func scriptsFile(_ sources: [String], encodingWrapped: Bool) -> Data {
        var out: [UInt8] = [4, 8]
        func int(_ n: Int) { out += n == 0 ? [0] : [UInt8(n + 5)] }  // small values only
        func string(_ bytes: [UInt8]) {
            if encodingWrapped { out.append(0x49) }  // I: with instance variables
            out.append(0x22)
            int(bytes.count)
            out += bytes
            if encodingWrapped {
                int(1)
                out += [0x3A]; int(1); out += Array("E".utf8)  // :E
                out += [0x54]                                  // true
            }
        }
        out.append(0x5B); int(sources.count)
        for (index, source) in sources.enumerated() {
            out.append(0x5B); int(3)
            out.append(0x69); int(index + 1)
            string(Array("Script \(index)".utf8))
            // The section's code is zlib bytes, kept raw (no encoding).
            out.append(0x22)
            let zipped = zlib(Array(source.utf8))
            if zipped.count < 123 { int(zipped.count) } else { out += [1, UInt8(zipped.count)] }
            out += zipped
        }
        return Data(out)
    }

    /// zlib: a 2-byte header, raw deflate, and the Adler-32 checksum.
    static func zlib(_ bytes: [UInt8]) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: bytes.count + 64)
        let size = compression_encode_buffer(&output, output.count, bytes, bytes.count, nil, COMPRESSION_ZLIB)
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in bytes { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        let adler = (b << 16) | a
        return [0x78, 0x9C] + output.prefix(size) + [UInt8(adler >> 24), UInt8(adler >> 16 & 0xFF), UInt8(adler >> 8 & 0xFF), UInt8(adler & 0xFF)]
    }
}

final class ControllerLayoutTests: XCTestCase {
    private func frames(_ layout: SkinLayout, _ input: SkinInput) -> CGRect? {
        layout.items.first { $0.inputs.first == input }?.frame
    }

    func testFourButtonsAddsXAndYWithoutOverlap() throws {
        let layout = BuiltInSkins.typed(BuiltInSkins.portrait, type: .classic4)
        let faces: [SkinInput] = [.key(.confirm), .key(.back), .key(.x), .key(.y)]
        let rects = try faces.map { try XCTUnwrap(frames(layout, $0), "\($0)") }
        for i in rects.indices {
            XCTAssertTrue(CGRect(origin: .zero, size: layout.mappingSize).contains(rects[i]))
            // Round buttons: their circles must not overlap.
            for j in rects.indices where j > i {
                let distance = hypot(rects[i].midX - rects[j].midX, rects[i].midY - rects[j].midY)
                XCTAssertGreaterThanOrEqual(distance, (rects[i].width + rects[j].width) / 2 - 0.5,
                                            "\(faces[i]) overlaps \(faces[j])")
            }
        }
    }

    func testModernTurnsTheDPadIntoAStickAndAddsTriggers() {
        let layout = BuiltInSkins.typed(BuiltInSkins.portrait, type: .modern)
        XCTAssertTrue(layout.items.contains { $0.kind == .stick })
        XCTAssertFalse(layout.items.contains { $0.kind == .dpad })
        XCTAssertNotNil(frames(layout, .key(.l2)))
        XCTAssertNotNil(frames(layout, .key(.r2)))
    }

    func testClassicTwoIsUnchanged() {
        XCTAssertEqual(BuiltInSkins.typed(BuiltInSkins.portrait, type: .classic2), BuiltInSkins.portrait)
    }

    /// The iPhone Duo's DS layout: game above the fold, every control
    /// below it, nothing on the crease.
    func testDuoPortraitKeepsTheFoldClear() throws {
        let gap: CGFloat = 26
        let layout = BuiltInSkins.splitPortrait(BuiltInSkins.portrait, viewAspect: 1.46, gameAspect: 4 / 3, gap: gap)
        let fold = try XCTUnwrap(layout.fold)
        let screen = try XCTUnwrap(layout.screen)
        XCTAssertLessThanOrEqual(screen.maxY, fold - gap / 2)
        for item in layout.items where item.inputs.first != .swapScreens {
            XCTAssertGreaterThanOrEqual(item.frame.minY, fold + gap / 2 - 0.5, "\(item.inputs)")
            XCTAssertLessThanOrEqual(item.frame.maxY, layout.mappingSize.height)
        }
    }

    func testDuoModernDiamondStaysOffTheGame() throws {
        let base = BuiltInSkins.handheldLandscape(BuiltInSkins.landscape, viewAspect: 1.46, gameAspect: 4 / 3)
        let layout = BuiltInSkins.typed(base, type: .modern)
        let screen = try XCTUnwrap(layout.screen)
        for item in layout.items {
            XCTAssertFalse(item.frame.insetBy(dx: 1, dy: 1).intersects(screen), "\(item.inputs) covers the game")
        }
    }

    func testContextKnowsTheDuo() {
        XCTAssertEqual(ControllerContext.device(for: CGSize(width: 393, height: 852)), .phone)
        if case .duo = ControllerContext.device(for: CGSize(width: 699, height: 1017)) {} else {
            XCTFail("an open iPhone Duo is a duo")
        }
    }
}

final class SkinTests: XCTestCase {
    private func item(_ inputs: [SkinInput], kind: SkinItem.Kind = .button, w: CGFloat = 50, h: CGFloat = 50) -> SkinItem {
        SkinItem(kind: kind, inputs: inputs, frame: CGRect(x: 0, y: 0, width: w, height: h))
    }

    func testOtherConsolesButtonsMapToEmbers() {
        XCTAssertEqual(SkinInput(deltaName: "cUp"), .key(.x))
        XCTAssertEqual(SkinInput(deltaName: "z"), .key(.l2))
        XCTAssertEqual(SkinInput(deltaName: "cross"), .key(.confirm))
        XCTAssertEqual(SkinInput(deltaName: "L1"), .key(.l))
    }

    func testCoverageFollowsTheButtons() {
        let directions: [SkinInput] = [.key(.up), .key(.down), .key(.left), .key(.right)]
        func skin(_ items: [SkinItem]) -> Skin {
            let layout = SkinLayout(mappingSize: CGSize(width: 320, height: 274), artwork: nil, items: items,
                                    screen: nil, extendedEdges: .zero, translucent: false)
            return Skin(id: "test", name: "Test", source: .imported(URL(fileURLWithPath: "/tmp")),
                        portrait: layout, landscape: nil)
        }
        let gba = skin([item(directions, kind: .dpad), item([.key(.confirm)]), item([.key(.back)])])
        XCTAssertEqual(gba.covers, [.classic2])
        let snes = skin(gba.portrait!.items + [item([.key(.x)]), item([.key(.y)])])
        XCTAssertEqual(snes.covers, [.classic2, .classic4])
        let n64 = skin([item(directions, kind: .stick), item([.key(.confirm)]), item([.key(.back)]),
                        item([.key(.x)]), item([.key(.y)])])
        XCTAssertEqual(n64.covers, [.classic2, .classic4, .modern])
        XCTAssertEqual(BuiltInSkins.ember.covers, Set(ControllerType.allCases))
    }

    func testConverterKeys() {
        XCTAssertEqual(EmberSkinConverter.key(for: item([.key(.confirm)])), "a")
        XCTAssertEqual(EmberSkinConverter.key(for: item([.key(.up)], kind: .stick)), "stick")
        XCTAssertNil(EmberSkinConverter.key(for: item([.keyboard])))
    }
}

final class SmallThingsTests: XCTestCase {
    func testKeyboardKeyNames() {
        XCTAssertEqual(KeyboardKey(scancode: 4).name, "A")
        XCTAssertEqual(KeyboardKey(scancode: 29).name, "Z")
        XCTAssertEqual(KeyboardKey(scancode: 30).name, "1")
        XCTAssertEqual(KeyboardKey(scancode: 39).name, "0")
        XCTAssertEqual(KeyboardKey(scancode: 62).name, "F5")
        // The engine's own keys are never offered.
        let offered = Set(KeyboardKey.all.map(\.scancode))
        XCTAssertFalse(offered.contains(58))  // F1
        XCTAssertFalse(offered.contains(59))  // F2
        XCTAssertFalse(offered.contains(69))  // F12
    }

    /// A profile saved by 1.1 has no `keys`.
    func testProfilesFromBefore12StillDecode() throws {
        struct OldProfile: Codable {
            var id: String, name: String, mapping: [ControlButton: GameAction]
        }
        let saved = try JSONEncoder().encode(OldProfile(id: "x", name: "Old", mapping: [.a: .confirm, .b: .back]))
        let profile = try JSONDecoder().decode(ControlProfile.self, from: saved)
        XCTAssertEqual(profile.action(for: .a), .confirm)
        XCTAssertNil(profile.keys)
        XCTAssertEqual(profile.scancode(for: .a), GameKey.confirm.scancode)
    }

    func testKeyActionSendsItsKey() {
        var profile = ControlProfile.standard
        profile.mapping[.x] = .key
        profile.keys = [.x: KeyboardKey(scancode: 30)]
        XCTAssertEqual(profile.scancode(for: .x), 30)
    }

    func testSaveDisplayNames() {
        func name(_ id: String) -> String {
            SaveThumbnails.displayName(SaveManager.SaveFile(id: id, url: URL(fileURLWithPath: "/tmp/\(id)"),
                                                            modified: .now, size: 0))
        }
        XCTAssertEqual(name("Save1.rxdata"), "Save 1")
        XCTAssertEqual(name("Save01.rvdata2"), "Save 1")
        XCTAssertEqual(name("Game_2.rxdata"), "Game 2")
        XCTAssertEqual(name("Save Data/Game.rxdata"), "Game")
    }

    func testFilterCycleVisitsEveryFilter() {
        var seen: [ScreenFilter] = []
        var filter = ScreenFilter.pixel
        for _ in ScreenFilter.allCases { seen.append(filter); filter = filter.next }
        XCTAssertEqual(Set(seen), Set(ScreenFilter.allCases))
        XCTAssertEqual(filter, .pixel)
    }
}
