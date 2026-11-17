import XCTest
@testable import Ember

/// Fixes from the 1.3 review: keys held by two buttons, merging a
/// backup's settings, game files kept out of save imports.
@MainActor
final class ControlMapperTests: XCTestCase {
    private var events: [(Int32, Bool)] = []

    private func mapper(_ profile: ControlProfile) -> ControlMapper {
        let mapper = ControlMapper()
        mapper.profile = profile
        mapper.inject = { [unowned self] scancode, down in events.append((scancode, down)) }
        return mapper
    }

    private var shift: KeyboardKey { KeyboardKey(scancode: 225) }

    func testKeyHeldByTwoButtonsWaitsForBoth() {
        var profile = ControlProfile.standard
        profile.put(shift, on: .x)
        profile.put(shift, on: .start)
        let mapper = mapper(profile)

        mapper.press(.x)
        mapper.press(.start)
        mapper.release(.start)
        XCTAssertEqual(events.map(\.1), [true], "Shift goes down once and stays down while X holds it")
        mapper.release(.x)
        XCTAssertEqual(events.map(\.1), [true, false])
        XCTAssertTrue(events.allSatisfy { $0.0 == 225 })
    }

    func testDirectionAndButtonOnTheSameKey() {
        var profile = ControlProfile.standard
        profile.switchToKeyboard()
        let w = KeyboardKey(scancode: 26)
        profile.put(w, on: .up)
        profile.put(w, on: .r)
        let mapper = mapper(profile)

        mapper.press(.up)
        mapper.press(.r)
        mapper.release(.r)
        XCTAssertEqual(events.count, 1)
        mapper.release(.up)
        XCTAssertEqual(events.map(\.1), [true, false])
    }

    func testReleaseAllLetsGoOfEveryKey() {
        var profile = ControlProfile.standard
        profile.put(shift, on: .x)
        profile.put(shift, on: .start)
        let mapper = mapper(profile)
        mapper.press(.x)
        mapper.press(.start)
        mapper.press(.down)
        mapper.releaseAll()
        XCTAssertEqual(events.filter { $0.1 }.count, events.filter { !$0.1 }.count)
        mapper.release(.x)
        XCTAssertEqual(events.filter { !$0.1 }.count, 2, "nothing left to let go of")
    }
}

final class BackupMergeTests: XCTestCase {
    func testDictionariesKeepThisDevicesKeys() {
        let merged = EmberBackup.merged(["a": "local", "b": "local"], with: ["b": "backup", "c": "backup"])
        XCTAssertEqual(merged as? [String: String], ["a": "local", "b": "backup", "c": "backup"])
    }

    func testJSONMappingsMergeByGame() throws {
        let local = try JSONSerialization.data(withJSONObject: ["Game A": ["name": "A"], "Game B": ["name": "B"]])
        let backup = try JSONSerialization.data(withJSONObject: ["Game B": ["name": "B2"]])
        let merged = try XCTUnwrap(EmberBackup.merged(local, with: backup) as? Data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: merged) as? [String: [String: String]])
        XCTAssertEqual(object["Game A"]?["name"], "A")
        XCTAssertEqual(object["Game B"]?["name"], "B2")
    }

    func testJSONListsMergeByID() throws {
        let local = try JSONSerialization.data(withJSONObject: [["id": "1", "v": "local"], ["id": "2", "v": "local"]])
        let backup = try JSONSerialization.data(withJSONObject: [["id": "2", "v": "backup"], ["id": "3", "v": "backup"]])
        let merged = try XCTUnwrap(EmberBackup.merged(local, with: backup) as? Data)
        let list = try XCTUnwrap(JSONSerialization.jsonObject(with: merged) as? [[String: String]])
        XCTAssertEqual(Set(list.compactMap { $0["id"] }), ["1", "2", "3"])
        XCTAssertEqual(list.first { $0["id"] == "2" }?["v"], "backup")
    }

    func testPlainValuesTakeTheBackup() {
        XCTAssertEqual(EmberBackup.merged("local", with: "backup") as? String, "backup")
        XCTAssertEqual(EmberBackup.merged(nil, with: 3) as? Int, 3)
    }
}

final class SaveImportTests: XCTestCase {
    func testGameFilesAreNotSaves() {
        for path in ["Data/Scripts.rxdata", "Game.ini", "Game.exe", "Game.rgss3a", "Graphics/Titles/t.png",
                     "Scripts.rvdata2", "RGSS104E.dll"] {
            XCTAssertTrue(SaveManager.isGameFile(path), path)
        }
        for path in ["Save01.rvdata2", "Save1.rxdata", "Game.rxdata", "Game_1.rxdata", "Save Data/File A.rxdata"] {
            XCTAssertFalse(SaveManager.isGameFile(path), path)
        }
    }
}

final class GameKeyScannerBlockTests: XCTestCase {
    func testCommentBlocksAndDebugBlocksDoNotCount() {
        let code = """
        =begin
        Input.triggerex?(:F6)
        =end
        if $DEBUG
          if Input.triggerex?(:F7)
            puts 1
          end
        else
          Input.triggerex?(:F8)
        end
        x = 1 # Input.triggerex?(:F9)
        s = "#{Input::F5}" if Input.triggerex?(:Q)
        """
        let names = GameKeyScanner.keys(inCode: code).map(\.name)
        XCTAssertEqual(Set(names), ["F8", "F5", "Q"])
    }

    func testTypingScriptsDoNotListTheAlphabet() {
        let code = (0x41...0x5A).map { "Input.triggerex?(0x\(String($0, radix: 16)))" }.joined(separator: "\n")
            + "\nInput.triggerex?(:F5)"
        XCTAssertEqual(GameKeyScanner.keys(inCode: code).map(\.name), ["F5"])
    }
}
