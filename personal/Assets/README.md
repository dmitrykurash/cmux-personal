# Axiom Desktop design assets

The personal fork adapts the owner's Axiom Desktop UI at
https://github.com/astrea-foundation/axiom-desktop/tree/21f8136fbfdde6530e96b4df14a92a9b661a79b0
with the owner's explicit permission.

- `PPCirka-*.otf` and its accompanying repository license come from
  `packages/brand/` in that revision. No Axiom logos are shipped.
- `personal-symbol.svg` is the original chat/terminal mark for this fork; its
  PNG is a native raster export. The app icon is a separately generated
  original chat/terminal design, with no Axiom emblem.
- `DMSans.ttf` is DM Sans from Google Fonts (`ofl/dmsans`), under the included
  `DMSans-OFL.txt` license.
- `AXIOM-LICENSE.txt` preserves Axiom Desktop's Apache 2.0 license. The rest of
  cmux retains its existing license.

Native adaptations use the palette, sizing and timings from
`packages/chat-ui/src/styles.css`, `WelcomeView.tsx`, `GreetingHeadline.tsx`,
`ChatComposer.tsx`, `Sidebar.tsx` and `MessageBubble.tsx`. They retain cmux's
actual SSH, Claude Code and permission flows. Axiom's encryption and account
claims are not copied: SSH only protects the connection to the VPS.

Both system appearances and Reduce Motion are supported. Fonts fall back via
CoreText for scripts missing from the original font assets.

## Original app icon

`PersonalAppIcon.png` was generated with the built-in imagegen tool, then
converted into a standard macOS `PersonalAppIcon.icns` with all 16–1024 px
representations. The selected concept is a coral speech bubble with a terminal
chevron and underscore on a charcoal rounded square. The earlier bird/globe
concept was rejected and is not included in this repository or app bundle.
