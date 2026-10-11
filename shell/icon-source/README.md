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

A guard-suite check verifies size, alpha and the catalog entries. The icon never animates; the Greek
cycle-then-lock motion lives in the app (see `docs/DESIGN.md`).
