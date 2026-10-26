# App icon source

The home-screen icon is the handwritten word "Midas", black on white (founder, 2026-10-11). Until the
founder's own handwriting is traced, the hand is Caveat Bold (SIL Open Font Licence, Google Fonts),
included here as `Caveat-Bold.ttf`.

Three HTML files render the three appearances at 1024 x 1024:

- `icon-light.html`: Any Appearance, black #111111 on white #FFFFFF. Must have no alpha channel.
- `icon-dark.html`: dark, white on #111111.
- `icon-tinted.html`: tinted, white on black (iOS tints the grayscale).

Regenerate (Brave is installed on the founder's Macs; any Chromium works):

```sh
cd shell/icon-source
for v in light dark tinted; do
  "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" --headless --disable-gpu \
    --hide-scrollbars --window-size=1024,1024 --force-device-scale-factor=1 \
    --virtual-time-budget=3000 --screenshot="AppIcon-$v.png" "file://$PWD/icon-$v.html"
done
cp AppIcon-light.png  ../Midas/Assets.xcassets/AppIcon.appiconset/AppIcon.png
cp AppIcon-dark.png   ../Midas/Assets.xcassets/AppIcon.appiconset/AppIcon-dark.png
cp AppIcon-tinted.png ../Midas/Assets.xcassets/AppIcon.appiconset/AppIcon-tinted.png
sips -g hasAlpha ../Midas/Assets.xcassets/AppIcon.appiconset/AppIcon.png   # must say no
```

## jess's home tile

jess's tile is the written "Jess", capital J, in the same Caveat Bold at the same size as the Midas
icon (founder, 2026-10-22). It is jess's one icon everywhere (founder, 2026-10-26): the home grid,
widget folders and Make all draw this asset, kept in `Shared.xcassets` so the widgets have it too. `jess-tile.py` draws it from the font's outlines
into `jess-tile-light.svg` and `jess-tile-dark.svg`; render and copy them like the app icon:

```sh
cd shell/icon-source
python3 jess-tile.py   # needs fontTools
for v in light dark; do
  "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" --headless --disable-gpu \
    --hide-scrollbars --window-size=1024,1024 --force-device-scale-factor=1 \
    --virtual-time-budget=2000 --screenshot="JessTile-$v.png" "file://$PWD/jess-tile-$v.svg"
done
mv JessTile-light.png ../Shared/Shared.xcassets/JessTile.imageset/JessTile.png
mv JessTile-dark.png  ../Shared/Shared.xcassets/JessTile.imageset/JessTile-dark.png
```

## jess's control symbol

Control Center, the Lock Screen and the Action button show "Ask jess" with a one-colour custom
symbol: the same written "Jess" (founder, 2026-10-23). `jess-symbol.py` writes it straight into
`../Shared/Shared.xcassets/JessSymbol.symbolset` on the SF Symbols template's Regular-M guides:

```sh
cd shell/icon-source
python3 jess-symbol.py   # needs fontTools
```

The App Shortcut cannot take a custom symbol; it uses Apple's `waveform` (`Shared/JessSymbols.swift`).

For the app icon and the tile: a guard-suite check verifies size, alpha and the catalog entries. The icon never animates; the Greek
cycle-then-lock motion lives in the app (see `docs/DESIGN.md`).
