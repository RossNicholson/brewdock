# BrewDock

**A free, native macOS menu bar app for Homebrew.** Browse, install, update, and remove your apps and tools without touching the Terminal.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift 6](https://img.shields.io/badge/Swift-6.0-orange) ![License: GPL v3](https://img.shields.io/badge/license-GPL--v3-blue) ![Free](https://img.shields.io/badge/price-free-brightgreen)

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
    <img src="docs/screenshot-light.png" alt="BrewDock's menu bar panel listing installed apps, with an Updates ready banner" width="380">
  </picture>
</p>

---

- **Apps** — all your Homebrew casks with real icons. Click to launch; hover or right-click to update or uninstall.
- **Tools** — all your formulae. Click to open in Terminal or iTerm2.
- **Services** — start, stop, and restart Homebrew services on hover.
- **Discover** — browse 230+ curated packages across 10 categories, or search all of Homebrew, and install with one click.
- **Updates** — checked in the background, with optional notifications. Update one or all at once, with live progress. Can include apps that update themselves.
- **Free up space** — clear old versions and cached downloads in one click.
- **⌥⌘B** — open BrewDock from any app; Esc closes it.
- **Brewfile** — back up your setup, restore it on a new Mac, or see what's missing.
- 100% native SwiftUI — no Electron, no bloat. Light and dark mode.

---

## Install

```bash
brew tap RossNicholson/tap
brew trust --cask rossnicholson/tap/brewdock
brew install --cask brewdock
```

Homebrew 7 asks you to trust casks from other taps before installing them. On older versions, skip the `brew trust` line.

**Requirements:** macOS 13+ · [Homebrew](https://brew.sh) installed · Apple Silicon or Intel

---

## Contributing

Bug reports, feature requests, and PRs welcome — open an issue or start a discussion.

To build from source: `brew install xcodegen && xcodegen generate`, then open `BrewDock.xcodeproj` and press `Cmd+R`. The checked-in `.xcodeproj` is generated from `project.yml`, so re-run `xcodegen generate` after editing that file.

---

## Support

If you find BrewDock helpful, consider [buying me a coffee](https://buymeacoffee.com/rossnicholson) ☕

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Support%20Ross-yellow?logo=buy-me-a-coffee)](https://buymeacoffee.com/rossnicholson)

---

## License

GPL v3 — see [LICENSE](LICENSE) for details.
