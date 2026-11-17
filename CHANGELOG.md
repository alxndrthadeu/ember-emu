# Changelog

What changed in each version of Ember. The newest version is on top; `Unreleased` is the work for the next one. Each released version has a git tag (`v1.0.0`) and a GitHub Release with these notes.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/): a new feature bumps the minor number (1.1.0), a fix the patch number (1.0.1).

## [1.3.0] - Unreleased

### Fixed
- A backup left in Ember's folder (AirDrop, Finder, "Save to Files") was restored again every time the app came back, and two restores in the same minute could lose the copy of the saves it replaced. Each backup is now restored once and removed, and the replaced saves are always kept.
- Restoring a backup with only the saves of a game that is not on this device no longer leaves an empty game behind; the saves wait in Backups.
- Restoring a backup keeps the control mappings, profiles and history made on this device after the backup.
- Save states work in the demo game.
- A save state that fails no longer freezes the screen, and a failing autosave no longer retries every few frames.
- Two buttons sending the same key (X and Start on Shift) no longer let go of the key while one is still held.
- An error from the game shown while a menu was closing could leave the game stuck.
- Importing saves no longer accepts the game's own files (scripts, Game.ini), and the error log no longer shows up as a save.
- Two copies of the same game imported at once no longer fail.
- The keys a game uses no longer list keys from commented-out code, test-play blocks or typing screens (the whole alphabet).
- Bringing a game back from iCloud stops with a message when the download makes no progress for a minute, instead of spinning.
- Wi-Fi transfer: a stalled upload is closed after 30 seconds and its half file removed; turning the transfer off ends uploads on their way; turning it on again no longer removes a batch still being imported.
- Archives with links inside no longer create them, and a full disk while unpacking is reported.
- Resuming an RPG Maker VX game loads its areas.

### Added
- Saves in iCloud: each game's saves and save states sync on their own between your iPhones (same game on each), when Ember opens and when you leave a game. Games themselves never go. If a save changed on two devices, the newest stays and the other is kept in Backups. On by default; Settings › iCloud.
- Update a game and keep your progress: importing a new version of a game already on the shelf (same title) offers to put it in the old one's place, keeping saves, save states, cover, controls and name. The saves are also kept in Backups.
- Siri and Shortcuts: "Continue in Ember", "Play <game> in Ember", "Send games to Ember", and the same actions in Spotlight and the Shortcuts app.
- A game's panel shows how many sessions you played and since when.
- When a game stops with an error typical of the wrong Ruby version, the alert offers to switch the game to the other Ruby in one tap.
- Settings › System reports: what iOS reports about Ember on this iPhone (crashes, hangs, heat, CPU, a daily summary), kept on the device and shared only if you choose.

### Changed
- Save state pictures are written as JPEG, quicker on the game's thread.
- Playing on the TV costs nothing until a browser opens the page, and frames are only encoded when a screen can take them.
- Less work on the game's thread while playing: save files are watched in the background, the play history is written in the background, covers and save pictures are decoded once.
- Accessibility: game cards are one VoiceOver button and show when they are pressed; text sizes follow Dynamic Type in the controls screens; darker amber and green where they mark something on cream; Reduce Motion is followed in the library and the game; messages in the game are read by VoiceOver; success and error vibrate differently.
- Swift 6 language mode (full data-race safety); the engine's callbacks are set up outside the main actor.
- Clearer names: "Controls for this game" in a game's panel, "Controls guide" in the library.
- The game menu scrolls when it does not fit (larger text, landscape); deleting a control profile or undoing a game's controls asks first.

## [1.2.1] - 2026-11-15

### Added
- Save a game's controls as a profile, from the game's controls or from Settings › Control profiles, to use them in other games.
- Keyboard mode in a game's controls, for games made for a computer: each button and each direction presses the PC key you pick on a drawn keyboard (Z on A, Enter on B, Ctrl on Y, WASD to walk), with the keys the game uses marked.

### Changed
- Directions from the D-pad, the stick and game controllers go through the game's mapping, so they can press other keys than the arrows.
- Control profiles redone: the same editor as a game's controls (Simple and Keyboard modes), the games that use each profile, and the games with their own controls in one list.

## [1.2.0] - 2026-11-15

### Added
- Cheats from the game menu: level up, money and items in RPG Maker XP, VX and VX Ace; heal the party, items and walk through walls in Pokémon Essentials. Also in games where the engine could not load them, or loaded the wrong one (The Witch's House, Pokémon Flux).
- Screen filters: Pixel, Smooth and Sharp (Lanczos), in Settings and switchable mid-game from the game menu.
- "Keyboard key" as a button action in control profiles: any letter, number, Space, Tab, Ctrl, Alt, F3–F11 and more, for games that read keys beyond the RGSS buttons.
- Controls per game (game panel › Controls): start from a profile and change any button for that game only. Ember reads the game's scripts for the PC keys it uses (F5, numbers, Ctrl…), lists them first with the button that sends each one, and puts one on a button with a tap.

### Changed
- Engine updated to mkxp-z-apple-mobile v14: fixes the black screen after PikaTaxi in Pokémon Insurgence and finding files a game writes while it runs; MIDI now comes with the engine.
- Unit tests and checks on every pull request.
- Code cleanup: Swift 6 concurrency checks at zero, Observation instead of ObservableObject, sources grouped by feature, the play history read once per library load.

## [1.1.0] - 2026-11-09

### Added
- Controller types for each game: Classic 2 buttons, Classic 4 buttons (X and Y) and Modern (analog stick, X, Y, L2, R2). Ember reads the game's scripts on import, also inside encrypted RGSS archives, suggests one, and asks once ("How do you want to play?").
- Eight directions: the D-pad, the stick and game controllers send diagonals for games that walk diagonally.
- Skins for any console: Delta and Manic EMU skins of any system work, one skin per controller type. Each skin is converted into an `.ember` package and drawn with its own buttons on devices and orientations its artist did not draw.
- iPhone Duo: a DS layout in portrait (game on the top screen, a 4:3 window below that can take the game), a handheld console layout in landscape, and a book layout when half folded.
- Play on a TV or computer through its browser, with sound.
- Backups you choose (`.emberbackup`), games archived to iCloud and brought back with a tap.
- Saves screen with thumbnails of where each save was made.
- Send saves to another iPhone by AirDrop (`.embersave`).
- Home screen quick actions (Continue, Import, Wi-Fi), a rating prompt after good sessions, and a "Rate Ember on the App Store" button in Settings.
- A "4 buttons" control profile, chosen automatically for 4-button and Modern games.

### Changed
- The game options sheet: a big Play button, quick actions and grouped lists.
- The keyboard button shows for every game.
- Delta skins drawn for the bottom of the screen sit at the bottom with the game above, instead of stretching.
- The demo game's Save and Continue work for real.

### Fixed
- Texts that stayed in Portuguese in English and Spanish (import progress, "All/None" in backups, the copy button's spoken label, the restore folder's name).

## [1.0.0] - 2026-11-06

First release on the App Store.

### Added
- RPG Maker XP, VX and VX Ace games on iPhone, with Ruby 1.8, 1.9 or 3.1 picked per game.
- Import from Files, a computer browser over Wi-Fi, the clipboard, drag and drop or "Open in Ember": .zip, .rar, .7z, self-extracting .exe or a game folder; the RTP the same way.
- On-screen controller with skins, Bluetooth and USB controllers, physical keyboards, up to 5x speed.
- Save states, autosave and "Continue" from where you left off; save export and import.
- MIDI music, covers, play history, logs per game and a performance overlay.
- The sample game "A Última Brasa".
- iOS 17 or later; Portuguese, English and Spanish.

[1.2.1]: https://github.com/alxndrthadeu/ember-emu/compare/v1.2.0...release/1.2.1
[1.2.0]: https://github.com/alxndrthadeu/ember-emu/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/alxndrthadeu/ember-emu/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/alxndrthadeu/ember-emu/releases/tag/v1.0.0
