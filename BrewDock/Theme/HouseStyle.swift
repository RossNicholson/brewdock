// The shared look (colours, fonts, buttons, cards and the menu bar panel)
// lives in the HouseStyle package, shared with Ross's other Mac apps.
// Re-exported so every file here can use it without its own import.
@_exported import HouseStyle

extension AppInfo {
    static let brewDock = AppInfo(name: "BrewDock", repo: "brewdock", cask: "brewdock",
                                  coffeeLine: "If BrewDock saves you time")
}
