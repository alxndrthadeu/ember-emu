# Changelog

What changed in each version of Ember. The newest version is on top; `Unreleased` is the work for the next one. Each released version has a git tag (`v1.0.0`) and a GitHub Release with these notes.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/): a new feature bumps the minor number (1.1.0), a fix the patch number (1.0.1).

## [1.2.0] - Unreleased

### Added
- Cheats from the game menu: level up, money and items in RPG Maker XP, VX and VX Ace; heal the party, items and walk through walls in Pokémon Essentials. Also in games where the engine could not load them before (The Witch's House).
- Screen filters: Pixel, Smooth, Sharp (Lanczos) and Rounded (xBRZ), in Settings and switchable mid-game from the game menu.
- "Keyboard key" as a button action in control profiles: any letter, number, Space, Tab, Ctrl, Alt, F3–F11 and more, for games that read keys beyond the RGSS buttons.

### Changed
- Engine updated to mkxp-z-apple-mobile v14: fixes the black screen after PikaTaxi in Pokémon Insurgence and finding files a game writes while it runs; MIDI now comes with the engine.
- Unit tests and checks on every pull request.

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

[1.2.0]: https://github.com/alxndrthadeu/ember-emu/compare/v1.1.0...release/1.2.0
[1.1.0]: https://github.com/alxndrthadeu/ember-emu/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/alxndrthadeu/ember-emu/releases/tag/v1.0.0
