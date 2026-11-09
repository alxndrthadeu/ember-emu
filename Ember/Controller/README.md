# Controller

Everything about the on-screen controller and game input lives here. Imported skins (Delta, Manic) are read in `Ember/Skins`; this folder decides what a controller looks like and what it does.

## How a layout is made

```
ControllerContext            device (phone / Duo + posture), orientation,
        │                    controller type, game proportion, settings
        ▼
ControllerLayouts.layout(for: skin, in: context)
        │
        ├─ imported skin with that orientation → used as drawn
        │
        └─ built-in skin:
             PhoneLayouts   phone layout (414 × 896 / 896 × 414 points)
                 │          adapted (keyboard button) and fitted (game proportion)
             DuoLayouts     redrawn for an open iPhone Duo: DS (portrait),
                 │          console (landscape flat), book (half folded)
             TypedLayouts   buttons of the controller type: X/Y diamond,
                            L2/R2, stick instead of D-pad
```

The game screen (`SkinStore.layout`) and the previews in "Como você quer jogar?" call the same function, so they always match. Layouts are in Delta's point space: frames in a `mappingSize`, stretched to the screen.

## Folders

| Folder | What |
| --- | --- |
| `ControllerType.swift` | Clássico 2 botões, Clássico 4 botões, Moderno; which one each game uses (`ControllerTypeStore`) |
| `Detection/` | Reads a game's scripts (also inside Game.rgssad/.rgss3a) and suggests a type |
| `Layout/` | The layout rules above |
| `Art/` | Draws built-in skins (Ember Laranja, Vidro): shell, D-pad, stick, buttons |
| `BuiltInSkins.swift` | The list of built-in skins |
| `Input/` | Touch on the skin (D-pad and stick with 8 directions), physical controllers and keyboards |
| `Profiles/` | Control profiles: what each button does (remapping) |
| `Choice/` | The "Como você quer jogar?" screen |

## Adding a controller type

1. Add a case to `ControllerType` (title, detail, icon, buttons).
2. Teach `BuiltInSkins.typed` where its extra buttons go, from the finished layout's A/B and L/R frames, so it works on every device.
3. Draw new kinds of buttons in `BuiltInSkinArt.control`.
4. If a game's scripts can reveal it, add a rule to `ScriptScanner.suggestion(forCode:)`.

## Adding a built-in skin style

1. Add a case to `BuiltInStyle` and a `Skin` to `BuiltInSkins`.
2. Give it colors and shapes in `BuiltInSkinArt` (`background`, `bezel`, `surface`). Layouts are shared, so every device and controller type works at once.

## Rules

- Directions: a diagonal holds two arrows. Games that read `Input.dir8` walk diagonally; the rest read four directions. The D-pad's diagonals are narrow (30°) so four-way games feel the same; the stick's are even.
- Never put controls on an iPhone Duo's fold or under its front camera (`DuoLayouts`).
- Buttons go through the game's control profile (`ControlMapper`); directions go straight to the engine.
