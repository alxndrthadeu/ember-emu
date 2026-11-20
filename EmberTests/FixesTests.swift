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

final class GameUpdaterTests: XCTestCase {
    private func makeGame(at folder: URL, title: String, scripts: String, save: String?) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder.appendingPathComponent("Data"), withIntermediateDirectories: true)
        try "[Game]\nTitle=\(title)\nLibrary=System\\RGSS301.dll\n".write(
            to: folder.appendingPathComponent("Game.ini"), atomically: true, encoding: .utf8)
        try scripts.write(to: folder.appendingPathComponent("Data/Scripts.rvdata2"), atomically: true, encoding: .utf8)
        if let save {
            try save.write(to: folder.appendingPathComponent("Save01.rvdata2"), atomically: true, encoding: .utf8)
        }
    }

    func testNewVersionTakesTheOldPlaceAndKeepsSaves() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("UpdaterTest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("Updater Test Game")
        let new = root.appendingPathComponent("Updater Test Game 2")
        try makeGame(at: old, title: "Updater Test Game", scripts: "v1", save: "progress")
        try makeGame(at: new, title: "Updater Test Game", scripts: "v2", save: nil)
        let existing = try XCTUnwrap(GameEntry(folder: old))
        let incoming = try XCTUnwrap(GameEntry(folder: new))
        XCTAssertEqual(GameUpdater.existingVersion(of: incoming, in: [existing, incoming])?.id, existing.id)

        let carried = try GameUpdater.update(GameUpdater.Offer(incoming: incoming, existing: existing))
        XCTAssertEqual(carried, 1)
        XCTAssertFalse(fm.fileExists(atPath: new.path))
        XCTAssertEqual(try String(contentsOf: old.appendingPathComponent("Data/Scripts.rvdata2"), encoding: .utf8), "v2")
        XCTAssertEqual(try String(contentsOf: old.appendingPathComponent("Save01.rvdata2"), encoding: .utf8), "progress")
        try? fm.removeItem(at: SaveManager.backupsFolder(for: existing))
    }
}

final class SaveSyncTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var game: SaveSync.GameFolders!

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("SyncTest-\(UUID().uuidString)")
        let id = "Sync Test \(UUID().uuidString.prefix(8))"
        game = SaveSync.GameFolders(id: id, title: "Sync Test", folder: root.appendingPathComponent("game"),
                                    userData: root.appendingPathComponent("userdata"),
                                    states: root.appendingPathComponent("states"))
        for folder in [game.folder, game.userData, game.states] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    override func tearDown() {
        try? fm.removeItem(at: root)
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? fm.removeItem(at: documents.appendingPathComponent("Backups/\(game.id)"))
    }

    private var cloud: URL { root.appendingPathComponent("cloud") }

    private func write(_ text: String, _ url: URL, age: TimeInterval = 0) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
    }

    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    func testUpThenDownThenConflict() throws {
        let local = game.folder.appendingPathComponent("Save01.rvdata2")
        let remote = cloud.appendingPathComponent("\(game.id)/folder/Save01.rvdata2")
        try write("one", local, age: 100)
        try write("essentials", game.userData.appendingPathComponent("Game.rxdata"), age: 100)
        var report = SaveSync.sync([game], root: cloud)
        XCTAssertEqual(report.uploaded, 2)
        XCTAssertEqual(read(remote), "one")

        // Nothing changed: nothing moves.
        report = SaveSync.sync([game], root: cloud)
        XCTAssertEqual(report.uploaded + report.downloaded, 0)

        // Another device saved: it comes down.
        try write("two", remote, age: 50)
        report = SaveSync.sync([game], root: cloud)
        XCTAssertEqual(report.downloaded, 1)
        XCTAssertEqual(read(local), "two")

        // Both sides saved: the newer one wins, nothing is lost.
        try write("three-here", local, age: 10)
        try write("three-there", remote, age: 20)
        report = SaveSync.sync([game], root: cloud)
        XCTAssertEqual(report.conflicts, ["Sync Test"])
        XCTAssertEqual(read(local), "three-here")
        XCTAssertEqual(read(remote), "three-here")
    }

    func testIncomingSaveAndWhoSavedLast() throws {
        SaveSync.deviceName = "Mac de Teste"
        let local = game.folder.appendingPathComponent("Save01.rvdata2")
        let remote = cloud.appendingPathComponent("\(game.id)/folder/Save01.rvdata2")
        try write("one", local, age: 100)
        let report = SaveSync.sync([game], root: cloud)
        XCTAssertEqual(report.games[game.id]?.uploaded, 1)
        XCTAssertEqual(report.games[game.id]?.lastDevice, "Mac de Teste")
        XCTAssertFalse(SaveSync.hasIncoming(game, root: cloud))

        // Another device saved: something is coming until the next sync.
        try write("two", remote, age: 10)
        XCTAssertTrue(SaveSync.hasIncoming(game, root: cloud))
        _ = SaveSync.sync([game], root: cloud)
        XCTAssertFalse(SaveSync.hasIncoming(game, root: cloud))
        XCTAssertEqual(read(local), "two")
    }

    /// While a game plays: what it saved goes up, nothing comes down
    /// under it, and the next full sync still brings what waited.
    func testUploadOnlyNeverTouchesTheRunningGame() throws {
        let mine = game.folder.appendingPathComponent("Save01.rvdata2")
        let theirs = game.folder.appendingPathComponent("Save02.rvdata2")
        try write("one", mine, age: 100)
        try write("old", theirs, age: 100)
        _ = SaveSync.sync([game], root: cloud)

        // The game saves slot 1; another device saved slot 2 meanwhile.
        try write("one-new", mine, age: 5)
        try write("two-from-mac", cloud.appendingPathComponent("\(game.id)/folder/Save02.rvdata2"), age: 10)
        var report = SaveSync.sync([game], root: cloud, uploadOnly: true)
        XCTAssertEqual(report.uploaded, 1)
        XCTAssertEqual(report.downloaded, 0)
        XCTAssertEqual(read(cloud.appendingPathComponent("\(game.id)/folder/Save01.rvdata2")), "one-new")
        XCTAssertEqual(read(theirs), "old")

        // After the game: the other device's save comes down.
        report = SaveSync.sync([game], root: cloud)
        XCTAssertEqual(report.downloaded, 1)
        XCTAssertEqual(read(theirs), "two-from-mac")
    }

    /// By hand: sending replaces iCloud's copy even when iCloud's is
    /// newer, bringing replaces this device's, and the next automatic
    /// sync sees both sides in step.
    func testSendAndBringByHand() throws {
        let local = game.folder.appendingPathComponent("Save01.rvdata2")
        let remote = cloud.appendingPathComponent("\(game.id)/folder/Save01.rvdata2")
        try write("mine-old", local, age: 100)
        try write("theirs-new", remote, age: 10)

        XCTAssertEqual(try SaveSync.sendAll(game, root: cloud).sent, 1)
        XCTAssertEqual(read(remote), "mine-old")
        XCTAssertEqual(SaveSync.cloudSide(game, root: cloud).files, 1)
        var report = SaveSync.sync([game], root: cloud)
        XCTAssertEqual(report.uploaded + report.downloaded, 0)

        try write("theirs-again", remote, age: 5)
        let result = try SaveSync.bringAll(game, root: cloud)
        XCTAssertEqual(result.brought, 1)
        XCTAssertEqual(read(local), "theirs-again")
        report = SaveSync.sync([game], root: cloud)
        XCTAssertEqual(report.uploaded + report.downloaded, 0)

        XCTAssertThrowsError(try SaveSync.bringAll(SaveSync.GameFolders(
            id: "Empty \(UUID())", title: "Empty", folder: root, userData: root, states: root), root: cloud))
    }

    /// By hand, the two sides end up the same: files only the other side
    /// had are taken out (kept in Backups), and a file iCloud has not
    /// brought down yet stops the send until it is here.
    func testByHandBothSidesEndUpTheSame() throws {
        let one = game.folder.appendingPathComponent("Save01.rvdata2")
        let cloudGame = cloud.appendingPathComponent("\(game.id)/folder")
        try write("one", one, age: 50)
        try write("two-only-in-icloud", cloudGame.appendingPathComponent("Save02.rvdata2"), age: 40)

        // A placeholder in iCloud: nothing changes yet.
        let placeholder = cloudGame.appendingPathComponent(".Save03.rvdata2.icloud")
        try write("", placeholder, age: 30)
        XCTAssertEqual(try SaveSync.sendAll(game, root: cloud).waiting, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cloudGame.appendingPathComponent("Save02.rvdata2").path))
        try FileManager.default.removeItem(at: placeholder)

        XCTAssertEqual(try SaveSync.sendAll(game, root: cloud).waiting, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloudGame.appendingPathComponent("Save02.rvdata2").path))
        XCTAssertEqual(read(cloudGame.appendingPathComponent("Save01.rvdata2")), "one")

        // Now a save only on this device: bringing takes it out.
        let four = game.folder.appendingPathComponent("Save04.rvdata2")
        try write("four-only-here", four, age: 20)
        _ = try SaveSync.bringAll(game, root: cloud)
        XCTAssertFalse(FileManager.default.fileExists(atPath: four.path))
        XCTAssertEqual(read(one), "one")
    }

    func testAGameCanSyncOnlyByHand() {
        XCTAssertTrue(SaveSync.syncsAutomatically(game.id))
        SaveSync.setSyncsAutomatically(false, for: game.id)
        XCTAssertFalse(SaveSync.syncsAutomatically(game.id))
        SaveSync.setSyncsAutomatically(true, for: game.id)
        XCTAssertTrue(SaveSync.syncsAutomatically(game.id))
    }
}

@MainActor
final class RubySuggestionTests: XCTestCase {
    func testVersionErrorsSuggestTheOtherRuby() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("RubyTest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: folder) }
        try fm.createDirectory(at: folder.appendingPathComponent("Data"), withIntermediateDirectories: true)
        try "[Game]\nTitle=Ruby Test\nLibrary=RGSS102E.dll\n".write(
            to: folder.appendingPathComponent("Game.ini"), atomically: true, encoding: .utf8)
        try "x".write(to: folder.appendingPathComponent("Data/Scripts.rxdata"), atomically: true, encoding: .utf8)
        let game = try XCTUnwrap(GameEntry(folder: folder))
        let suggestion = EngineSession.rubySuggestion(for: "Script 'Main' line 3: SyntaxError occurred.", game: game)
        XCTAssertNotNil(suggestion)
        XCTAssertNotEqual(suggestion?.version, game.rubyVersion)
        XCTAssertNil(EngineSession.rubySuggestion(for: "Unable to find file Graphics/Titles/x", game: game))
    }
}
