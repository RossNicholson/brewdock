import SwiftUI

struct DiscoverPackage: Identifiable {
    let id: String
    let displayName: String
    let description: String
    let category: Category
    let type: BrewPackage.PackageType
    let iconURL: String?
    /// Third-party tap the package lives in, e.g. "rossnicholson/tap". Installing
    /// by the tap-qualified name makes brew tap it automatically.
    var tap: String? = nil

    /// The name to pass to `brew install`.
    var installToken: String {
        tap.map { "\($0)/\(id)" } ?? id
    }

    /// Whether an installed package with this name is this catalog entry. An
    /// alias like "python" installs a versioned formula ("python@3.15"), so match
    /// versioned names too.
    func matches(installedName name: String) -> Bool {
        // Search results from third-party taps are tap-qualified ("user/tap/foo"),
        // but brew lists installed packages by their short name.
        let short = id.split(separator: "/").last.map(String.init) ?? id
        return name == short || name.hasPrefix(short + "@")
    }

    /// A package found by searching Homebrew, outside the curated catalog
    init(searchResult id: String, displayName: String, description: String, type: BrewPackage.PackageType) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.category = .utilities
        self.type = type
        self.iconURL = nil
    }

    enum Category: String, CaseIterable {
        case browsers      = "Browsers"
        case development   = "Development"
        case ai            = "AI & ML"
        case databases     = "Databases"
        case devops        = "DevOps & Cloud"
        case media         = "Media & Design"
        case productivity  = "Productivity"
        case communication = "Communication"
        case security      = "Security"
        case utilities     = "Utilities"

        var symbol: String {
            switch self {
            case .browsers:      return "safari"
            case .development:   return "hammer"
            case .ai:            return "brain.head.profile"
            case .databases:     return "cylinder"
            case .devops:        return "cloud"
            case .media:         return "photo"
            case .productivity:  return "star"
            case .communication: return "message"
            case .security:      return "lock.shield"
            case .utilities:     return "wrench.and.screwdriver"
            }
        }

        var color: Color {
            switch self {
            case .browsers:      return .blue
            case .development:   return .orange
            case .ai:            return .indigo
            case .databases:     return .teal
            case .devops:        return .purple
            case .media:         return .pink
            case .productivity:  return .yellow
            case .communication: return .green
            case .security:      return .red
            case .utilities:     return Color(nsColor: .secondaryLabelColor)
            }
        }
    }

    var icon: FormulaIcon {
        FormulaIcons.icon(for: id) ?? FormulaIcon(symbol: category.symbol, color: category.color)
    }
}

private extension DiscoverPackage {
    init(_ id: String, _ displayName: String, _ description: String, _ category: Category, _ type: BrewPackage.PackageType, _ iconURL: String? = nil, tap: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.category = category
        self.type = type
        self.iconURL = iconURL
        self.tap = tap
    }
}

private func icon(_ domain: String) -> String {
    "https://icon.horse/icon/\(domain)"
}

enum DiscoverCatalog {
    static let all: [DiscoverPackage] = [

        // MARK: Featured
        .init("clawdbar", "ClawdBar", "macOS menu bar app showing your Claude Code usage limits at a glance", .utilities, .cask, tap: "rossnicholson/tap"),

        // MARK: Browsers
        .init("google-chrome",  "Google Chrome",   "Fast, secure web browser by Google",              .browsers, .cask, icon("chrome.google.com")),
        .init("firefox",        "Firefox",         "Free and open-source web browser",                .browsers, .cask, icon("mozilla.org")),
        .init("arc",            "Arc",             "Browser that puts you in control",                .browsers, .cask, icon("arc.net")),
        .init("brave-browser",  "Brave",           "Privacy-focused browser with ad blocking",        .browsers, .cask, icon("brave.com")),
        .init("opera",          "Opera",           "Feature-rich browser with built-in VPN",          .browsers, .cask, icon("opera.com")),
        .init("vivaldi",        "Vivaldi",         "Highly customisable Chromium-based browser",      .browsers, .cask, icon("vivaldi.com")),
        .init("microsoft-edge", "Microsoft Edge",  "Fast browser built on Chromium by Microsoft",     .browsers, .cask, icon("microsoft.com/edge")),
        .init("tor-browser",    "Tor Browser",     "Browse privately using the Tor network",          .browsers, .cask, icon("torproject.org")),

        // MARK: Development
        .init("visual-studio-code", "VS Code",           "Lightweight but powerful source code editor",     .development, .cask, icon("code.visualstudio.com")),
        .init("cursor",             "Cursor",            "AI-first code editor",                            .development, .cask, icon("cursor.sh")),
        .init("devin-desktop",      "Devin Desktop",     "Agentic AI code editor (formerly Windsurf)",      .development, .cask, icon("devin.ai")),
        .init("zed",                "Zed",               "High-performance multiplayer code editor",        .development, .cask, icon("zed.dev")),
        .init("iterm2",             "iTerm2",            "Feature-rich terminal emulator for macOS",        .development, .cask, icon("iterm2.com")),
        .init("warp",               "Warp",              "Modern terminal with AI built in",                .development, .cask, icon("warp.dev")),
        .init("ghostty",            "Ghostty",           "Fast, native terminal emulator",                  .development, .cask, icon("ghostty.org")),
        .init("wezterm",            "WezTerm",           "GPU-accelerated cross-platform terminal",         .development, .cask, icon("wezfurlong.org")),
        .init("kitty",              "Kitty",             "Fast, feature-rich GPU-based terminal emulator",  .development, .cask, icon("sw.kovidgoyal.net")),
        .init("sublime-text",       "Sublime Text",      "Sophisticated text editor for code",              .development, .cask, icon("sublimetext.com")),
        .init("nova",               "Nova",              "Native macOS code editor by Panic",               .development, .cask, icon("nova.app")),
        .init("jetbrains-toolbox",  "JetBrains Toolbox", "Manage all your JetBrains tools in one place",   .development, .cask, icon("jetbrains.com")),
        .init("android-studio",     "Android Studio",    "Official IDE for Android development",            .development, .cask, icon("developer.android.com")),
        .init("postman",            "Postman",           "API platform for building and using APIs",        .development, .cask, icon("postman.com")),
        .init("insomnia",           "Insomnia",          "Open source API client and design tool",          .development, .cask, icon("insomnia.rest")),
        .init("bruno",              "Bruno",             "Open source API client — Postman alternative",    .development, .cask, icon("usebruno.com")),
        .init("mockoon",            "Mockoon",           "Mock REST APIs locally in seconds",               .development, .cask, icon("mockoon.com")),
        .init("devtoys",            "DevToys",           "Swiss army knife of developer utilities",         .development, .cask, icon("devtoys.app")),
        .init("cyberduck",          "Cyberduck",         "FTP, SFTP, and cloud storage browser",            .development, .cask, icon("cyberduck.io")),
        .init("transmit",           "Transmit",          "Fast, reliable file transfer client for Mac",     .development, .cask, icon("panic.com")),
        .init("forklift",           "ForkLift",          "Dual-pane file manager and FTP client",           .development, .cask, icon("binarynights.com")),
        .init("xcodes-app",         "Xcodes",            "Install and switch between Xcode versions",       .development, .cask, icon("github.com")),
        .init("github",             "GitHub Desktop",    "Easy-to-use GitHub GUI client",                   .development, .cask, icon("desktop.github.com")),
        .init("sourcetree",         "Sourcetree",        "Free Git and Mercurial client by Atlassian",      .development, .cask, icon("sourcetreeapp.com")),
        .init("fork",               "Fork",              "Fast and friendly Git client for Mac",            .development, .cask, icon("fork.dev")),
        .init("tower",              "Tower",             "Powerful Git client with a clean UI",             .development, .cask, icon("git-tower.com")),
        .init("dash",               "Dash",              "Offline documentation browser and snippet manager", .development, .cask, icon("kapeli.com")),
        .init("node",               "Node.js",           "JavaScript runtime built on Chrome's V8",         .development, .formula, icon("nodejs.org")),
        .init("deno",               "Deno",              "Secure JavaScript and TypeScript runtime",        .development, .formula, icon("deno.com")),
        .init("python",             "Python",            "Interpreted, high-level programming language",    .development, .formula, icon("python.org")),
        .init("go",                 "Go",                "Fast, statically typed compiled language",        .development, .formula, icon("go.dev")),
        .init("ruby",               "Ruby",              "Dynamic, open source programming language",       .development, .formula, icon("ruby-lang.org")),
        .init("rust",               "Rust",              "Safe, concurrent systems programming language",   .development, .formula, icon("rust-lang.org")),
        .init("openjdk",            "OpenJDK",           "Open-source implementation of the Java Platform", .development, .formula, icon("adoptium.net")),
        .init("git",                "Git",               "Distributed version control system",              .development, .formula, icon("git-scm.com")),
        .init("gh",                 "GitHub CLI",        "GitHub's official command-line tool",             .development, .formula, icon("cli.github.com")),
        .init("cmake",              "CMake",             "Cross-platform build system generator",           .development, .formula, icon("cmake.org")),
        .init("jq",                 "jq",                "Lightweight command-line JSON processor",         .development, .formula, icon("jqlang.github.io")),
        .init("httpie",             "HTTPie",            "Modern, user-friendly HTTP client for the CLI",   .development, .formula, icon("httpie.io")),
        .init("wget",               "wget",              "Internet file retriever",                         .development, .formula),
        .init("tmux",               "tmux",              "Terminal multiplexer for persistent sessions",    .development, .formula),
        .init("zellij",             "Zellij",            "Modern terminal multiplexer with a friendly UI",  .development, .formula, icon("zellij.dev")),
        .init("neovim",             "Neovim",            "Hyperextensible vim-based text editor",           .development, .formula, icon("neovim.io")),
        .init("helix",              "Helix",             "Post-modern modal text editor",                   .development, .formula, icon("helix-editor.com")),
        .init("starship",           "Starship",          "Minimal, fast, customisable shell prompt",        .development, .formula, icon("starship.rs")),
        .init("pnpm",               "pnpm",              "Fast, disk space efficient package manager",      .development, .formula, icon("pnpm.io")),
        .init("yarn",               "Yarn",              "Fast, reliable JavaScript package manager",       .development, .formula, icon("yarnpkg.com")),
        .init("fnm",                "fnm",               "Fast and simple Node.js version manager",         .development, .formula, icon("github.com")),
        .init("volta",              "Volta",             "Hassle-free JavaScript tool manager",             .development, .formula, icon("volta.sh")),
        .init("mise",               "mise",              "Polyglot dev environment manager",                .development, .formula, icon("mise.jdx.dev")),
        .init("cocoapods",          "CocoaPods",         "Dependency manager for Swift and Objective-C",    .development, .formula, icon("cocoapods.org")),
        .init("fastlane",           "Fastlane",          "Automate iOS and macOS deployment",               .development, .formula, icon("fastlane.tools")),
        .init("swiftlint",          "SwiftLint",         "Enforce Swift style and conventions",             .development, .formula, icon("github.com")),
        .init("swiftformat",        "SwiftFormat",       "Code formatter for Swift",                        .development, .formula, icon("github.com")),
        .init("xcbeautify",         "xcbeautify",        "Beautify Xcode build log output",                 .development, .formula, icon("github.com")),
        .init("lazydocker",         "lazydocker",        "Terminal UI for Docker and docker-compose",        .development, .formula, icon("github.com")),
        .init("mkcert",             "mkcert",            "Create locally-trusted SSL certificates",          .development, .formula, icon("github.com")),
        .init("direnv",             "direnv",            "Load and unload environment variables per directory", .development, .formula, icon("direnv.net")),
        .init("pre-commit",         "pre-commit",        "Framework for managing multi-language pre-commit hooks", .development, .formula, icon("pre-commit.com")),

        // MARK: AI & ML
        .init("claude",       "Claude",        "Anthropic's Claude AI desktop app",                .ai, .cask, icon("claude.ai")),
        .init("chatgpt",      "ChatGPT",       "Official OpenAI ChatGPT desktop app",             .ai, .cask, icon("chatgpt.com")),
        .init("ollama-app",   "Ollama",        "Run large language models locally",                .ai, .cask, icon("ollama.com")),
        .init("lm-studio",    "LM Studio",     "Discover, download and run local LLMs",           .ai, .cask, icon("lmstudio.ai")),
        .init("jan",          "Jan",           "Open source ChatGPT-alternative that runs offline", .ai, .cask, icon("jan.ai")),
        .init("diffusionbee", "DiffusionBee",  "Stable Diffusion app for AI image generation",    .ai, .cask, icon("diffusionbee.com")),
        .init("anaconda",     "Anaconda",      "Python distribution for data science and ML",     .ai, .cask, icon("anaconda.com")),
        .init("miniconda",    "Miniconda",     "Minimal Conda installer for Python environments", .ai, .cask, icon("docs.conda.io")),

        // MARK: Databases
        .init("tableplus",          "TablePlus",         "Modern native database management tool",          .databases, .cask, icon("tableplus.com")),
        .init("sequel-ace",         "Sequel Ace",        "Fast MySQL and MariaDB database manager",         .databases, .cask, icon("sequel-ace.com")),
        .init("postico",            "Postico",           "PostgreSQL client for macOS",                     .databases, .cask, icon("eggerapps.at")),
        .init("dbeaver-community",  "DBeaver",           "Free universal database management tool",         .databases, .cask, icon("dbeaver.io")),
        .init("beekeeper-studio",   "Beekeeper Studio",  "Cross-platform SQL editor and database manager",  .databases, .cask, icon("beekeeperstudio.io")),
        .init("mongodb-compass",    "MongoDB Compass",   "Official GUI for MongoDB",                        .databases, .cask, icon("mongodb.com")),
        .init("redis-insight",      "Redis Insight",     "Official GUI for Redis",                          .databases, .cask, icon("redis.io")),
        .init("pgadmin4",           "pgAdmin 4",         "Feature-rich PostgreSQL administration tool",      .databases, .cask, icon("pgadmin.org")),
        .init("neo4j-desktop",      "Neo4j Desktop",     "Leading graph database platform",                  .databases, .cask, icon("neo4j.com")),
        .init("dbgate",             "DbGate",            "Open source universal database client",            .databases, .cask, icon("dbgate.org")),
        .init("postgresql",         "PostgreSQL",        "Powerful open source relational database",        .databases, .formula, icon("postgresql.org")),
        .init("mysql",              "MySQL",             "World's most popular open source database",       .databases, .formula, icon("mysql.com")),
        .init("mariadb",            "MariaDB",           "Community-developed MySQL-compatible database",    .databases, .formula, icon("mariadb.org")),
        .init("redis",              "Redis",             "In-memory data structure store",                  .databases, .formula, icon("redis.io")),
        .init("sqlite",             "SQLite",            "Lightweight embedded SQL database engine",        .databases, .formula, icon("sqlite.org")),

        // MARK: DevOps & Cloud
        .init("docker-desktop",  "Docker Desktop",          "Platform for building and running containers",     .devops, .cask, icon("docker.com")),
        .init("orbstack",        "OrbStack",        "Fast, light Docker and Linux VM manager",         .devops, .cask, icon("orbstack.dev")),
        .init("rancher",         "Rancher Desktop", "Container management on the desktop",             .devops, .cask, icon("rancherdesktop.io")),
        .init("podman-desktop",  "Podman Desktop",  "Open source container management UI",             .devops, .cask, icon("podman.io")),
        .init("lens",            "Lens",            "The Kubernetes IDE",                              .devops, .cask, icon("k8slens.dev")),
        .init("ngrok",           "ngrok",           "Expose local servers to the internet instantly",  .devops, .cask, icon("ngrok.com")),
        .init("gcloud-cli",      "Google Cloud CLI", "Command-line tools for Google Cloud",            .devops, .cask, icon("cloud.google.com")),
        .init("vagrant",         "Vagrant",         "Build and manage virtual machine environments",   .devops, .cask, icon("vagrantup.com")),
        .init("kubernetes-cli",  "kubectl",         "Kubernetes command-line tool",                    .devops, .formula, icon("kubernetes.io")),
        .init("helm",            "Helm",            "Package manager for Kubernetes",                  .devops, .formula, icon("helm.sh")),
        .init("k9s",             "k9s",             "Terminal UI for Kubernetes clusters",             .devops, .formula, icon("k9scli.io")),
        .init("k3d",             "k3d",             "Run k3s Kubernetes clusters in Docker",           .devops, .formula, icon("k3d.io")),
        .init("minikube",        "Minikube",        "Run Kubernetes locally",                          .devops, .formula, icon("minikube.sigs.k8s.io")),
        .init("kubectx",         "kubectx",         "Faster way to switch between Kubernetes contexts", .devops, .formula, icon("github.com")),
        .init("stern",           "stern",           "Tail logs from multiple Kubernetes pods",         .devops, .formula, icon("github.com")),
        .init("skaffold",        "Skaffold",        "Continuous development for Kubernetes apps",      .devops, .formula, icon("skaffold.dev")),
        .init("dive",            "dive",            "Explore and optimise Docker image layers",        .devops, .formula, icon("github.com")),
        .init("colima",          "Colima",          "Minimal container runtime for macOS",             .devops, .formula, icon("github.com")),
        .init("pulumi",          "Pulumi",          "Infrastructure as code in any language",          .devops, .formula, icon("pulumi.com")),
        .init("opentofu",        "OpenTofu",        "Open source Terraform alternative",               .devops, .formula, icon("opentofu.org")),
        .init("cloudflared",     "cloudflared",     "Cloudflare Tunnel client and DNS-over-HTTPS",     .devops, .formula, icon("cloudflare.com")),
        .init("act",             "act",             "Run GitHub Actions locally",                      .devops, .formula),
        .init("ansible",         "Ansible",         "Agentless IT automation platform",               .devops, .formula, icon("ansible.com")),
        .init("awscli",          "AWS CLI",         "Amazon Web Services command-line interface",      .devops, .formula, icon("aws.amazon.com")),
        .init("azure-cli",       "Azure CLI",       "Microsoft Azure command-line interface",          .devops, .cask, icon("azure.microsoft.com")),
        .init("doctl",           "doctl",           "DigitalOcean official command-line tool",         .devops, .formula, icon("digitalocean.com")),

        // MARK: Media & Design
        .init("figma",        "Figma",          "Collaborative interface design tool",              .media, .cask, icon("figma.com")),
        .init("sketch",       "Sketch",         "Digital design platform for macOS",                .media, .cask, icon("sketch.com")),
        .init("affinity",          "Affinity",          "Photo editing, vector design and layout in one app", .media, .cask, icon("affinity.studio")),
        .init("blender",      "Blender",        "Free and open source 3D creation suite",          .media, .cask, icon("blender.org")),
        .init("obs",          "OBS Studio",     "Free and open source streaming and recording",    .media, .cask, icon("obsproject.com")),
        .init("screenflow",   "ScreenFlow",     "Professional screen recording and video editing", .media, .cask, icon("telestream.net")),
        .init("vlc",          "VLC",            "Free and open source media player",                .media, .cask, icon("videolan.org")),
        .init("iina",         "IINA",           "Modern media player built for macOS",              .media, .cask, icon("iina.io")),
        .init("audacity",     "Audacity",       "Free, open source cross-platform audio editor",   .media, .cask, icon("audacityteam.org")),
        .init("handbrake-app","HandBrake",      "Open source video transcoder",                     .media, .cask, icon("handbrake.fr")),
        .init("kap",          "Kap",            "Open source screen recorder built with web tech", .media, .cask, icon("getkap.co")),
        .init("losslesscut",  "LosslessCut",    "Lossless video and audio trimming tool",          .media, .cask, icon("mifi.no")),
        .init("imageoptim",   "ImageOptim",     "Optimises images by removing bloated metadata",   .media, .cask, icon("imageoptim.com")),
        .init("gimp",         "GIMP",           "Free and open source image editor",                .media, .cask, icon("gimp.org")),
        .init("inkscape",     "Inkscape",       "Free and open source vector graphics editor",     .media, .cask, icon("inkscape.org")),
        .init("ffmpeg",       "FFmpeg",         "Record, convert and stream audio and video",       .media, .formula, icon("ffmpeg.org")),
        .init("imagemagick",  "ImageMagick",    "Create, edit, compose or convert images",          .media, .formula, icon("imagemagick.org")),
        .init("exiftool",     "ExifTool",       "Read and write meta information in files",         .media, .formula, icon("exiftool.org")),
        .init("downie",       "Downie",         "Download videos from hundreds of websites",        .media, .cask, icon("software.charliemonroe.net")),
        .init("yt-dlp",       "yt-dlp",         "Download videos from YouTube and other sites",    .media, .formula, icon("youtube.com")),

        // MARK: Productivity
        .init("raycast",           "Raycast",          "Supercharged macOS launcher",                      .productivity, .cask, icon("raycast.com")),
        .init("alfred",            "Alfred",           "Award-winning productivity app for macOS",         .productivity, .cask, icon("alfredapp.com")),
        .init("notion",            "Notion",           "All-in-one workspace for notes and docs",          .productivity, .cask, icon("notion.so")),
        .init("obsidian",          "Obsidian",         "Knowledge base on local Markdown files",           .productivity, .cask, icon("obsidian.md")),
        .init("todoist-app",       "Todoist",          "Organise work and life with task management",      .productivity, .cask, icon("todoist.com")),
        .init("fantastical",       "Fantastical",      "Award-winning calendar and tasks app",             .productivity, .cask, icon("flexibits.com")),
        .init("1password",         "1Password",        "Password manager and secure digital wallet",       .productivity, .cask, icon("1password.com")),
        .init("bitwarden",         "Bitwarden",        "Open source password manager",                     .productivity, .cask, icon("bitwarden.com")),
        .init("mimestream",        "Mimestream",       "Native Gmail client built for macOS",              .productivity, .cask, icon("mimestream.com")),
        .init("pdf-expert",        "PDF Expert",       "Fast and powerful PDF editor for Mac",             .productivity, .cask, icon("pdfexpert.com")),
        .init("libreoffice",       "LibreOffice",      "Free and open source office suite",                .productivity, .cask, icon("libreoffice.org")),
        .init("keyboard-maestro",  "Keyboard Maestro", "Powerful keyboard and macro automation tool",      .productivity, .cask, icon("keyboardmaestro.com")),
        .init("popclip",           "PopClip",          "Instant text actions for what you select",         .productivity, .cask, icon("pilotmoon.com")),
        .init("logseq",            "Logseq",           "Privacy-first knowledge management tool",          .productivity, .cask, icon("logseq.com")),
        .init("linear",            "Linear",           "Modern project management for software teams",     .productivity, .cask, icon("linear.app")),
        .init("notion-calendar",   "Notion Calendar",  "Smart calendar with Notion integration",           .productivity, .cask, icon("notion.so")),
        .init("netnewswire",       "NetNewsWire",      "Fast, free, open source RSS reader for Mac",       .productivity, .cask, icon("netnewswire.com")),
        .init("readdle-spark",     "Spark",            "Smart email client for Mac",                       .productivity, .cask, icon("sparkmailapp.com")),
        .init("textexpander",      "TextExpander",     "Type more with less — powerful text expansion",    .productivity, .cask, icon("textexpander.com")),
        .init("cleanmymac",        "CleanMyMac",       "Mac cleaning and performance optimiser",           .productivity, .cask, icon("macpaw.com")),
        .init("bartender",         "Bartender",        "Take control of your menu bar",                    .productivity, .cask, icon("macbartender.com")),
        .init("craft",             "Craft",            "Beautiful native document editor",                 .productivity, .cask, icon("craft.do")),

        // MARK: Communication
        .init("slack",            "Slack",           "Business communication platform",            .communication, .cask, icon("slack.com")),
        .init("discord",          "Discord",         "Voice, video and text communication",        .communication, .cask, icon("discord.com")),
        .init("telegram",         "Telegram",        "Fast and secure messaging app",              .communication, .cask, icon("telegram.org")),
        .init("signal",           "Signal",          "Private and encrypted messenger",            .communication, .cask, icon("signal.org")),
        .init("zoom",             "Zoom",            "Video conferencing and online meetings",      .communication, .cask, icon("zoom.us")),
        .init("microsoft-teams",  "Microsoft Teams", "Chat-based workspace in Microsoft 365",      .communication, .cask, icon("microsoft.com")),
        .init("whatsapp",         "WhatsApp",        "WhatsApp desktop client",                    .communication, .cask, icon("whatsapp.com")),
        .init("mattermost",       "Mattermost",      "Open source messaging platform for teams",   .communication, .cask, icon("mattermost.com")),
        .init("element",          "Element",         "Secure, decentralised Matrix messaging client", .communication, .cask, icon("element.io")),
        .init("loom",             "Loom",            "Record and share video messages instantly",   .communication, .cask, icon("loom.com")),
        .init("krisp",            "Krisp",           "AI-powered noise cancellation for calls",     .communication, .cask, icon("krisp.ai")),
        .init("webex",            "Webex",           "Cisco's video conferencing platform",         .communication, .cask, icon("webex.com")),

        // MARK: Security
        .init("wireshark-app",  "Wireshark",      "Network protocol analyser",                    .security, .cask, icon("wireshark.org")),
        .init("proxyman",       "Proxyman",       "Debug network traffic on macOS",               .security, .cask, icon("proxyman.io")),
        .init("keepassxc",      "KeePassXC",      "Cross-platform open source password manager",  .security, .cask, icon("keepassxc.org")),
        .init("mullvad-vpn",    "Mullvad VPN",    "VPN service focused on privacy and anonymity", .security, .cask, icon("mullvad.net")),
        .init("tunnelblick",    "Tunnelblick",    "Free and open source OpenVPN client for Mac",  .security, .cask, icon("tunnelblick.net")),
        .init("gpg-suite",      "GPG Suite",      "GPG encryption tools for macOS",               .security, .cask, icon("gpgtools.org")),
        .init("nordvpn",        "NordVPN",        "Fast and secure VPN service",                  .security, .cask, icon("nordvpn.com")),
        .init("little-snitch",  "Little Snitch",  "Monitor outgoing network connections",         .security, .cask, icon("obdev.at")),
        .init("charles",        "Charles",        "HTTP proxy and monitor",                       .security, .cask, icon("charlesproxy.com")),
        .init("burp-suite",     "Burp Suite",     "Web security testing platform",                .security, .cask, icon("portswigger.net")),
        .init("veracrypt",      "VeraCrypt",      "Strong disk encryption for your files",        .security, .cask, icon("veracrypt.fr")),
        .init("protonvpn",      "ProtonVPN",      "Secure VPN from the makers of ProtonMail",     .security, .cask, icon("protonvpn.com")),
        .init("expressvpn",     "ExpressVPN",     "Fast, secure and private VPN service",         .security, .cask, icon("expressvpn.com")),
        .init("proxifier",      "Proxifier",      "Route any app's traffic through a proxy",      .security, .cask, icon("proxifier.com")),
        .init("lulu",           "LuLu",           "Open source macOS firewall",                   .security, .cask, icon("objective-see.org")),
        .init("oversight",      "OverSight",      "Monitor camera and microphone access",          .security, .cask, icon("objective-see.org")),
        .init("blockblock",     "BlockBlock",     "Monitor and alert on persistent malware",       .security, .cask, icon("objective-see.org")),
        .init("nmap",           "nmap",           "Network exploration and security scanner",      .security, .formula, icon("nmap.org")),
        .init("lynis",          "Lynis",          "Security auditing tool for Unix systems",       .security, .formula, icon("cisofy.com")),
        .init("clamav",         "ClamAV",         "Open source antivirus engine",                 .security, .formula, icon("clamav.net")),

        // MARK: Utilities
        .init("the-unarchiver",  "The Unarchiver",    "Open any archive format in seconds",        .utilities, .cask, icon("theunarchiver.com")),
        .init("keka",            "Keka",              "The macOS file archiver",                   .utilities, .cask, icon("keka.io")),
        .init("appcleaner",      "AppCleaner",        "Thoroughly uninstall unwanted apps",        .utilities, .cask, icon("freemacsoft.net")),
        .init("daisydisk",       "DaisyDisk",         "Visualise disk usage and free up space",    .utilities, .cask, icon("daisydiskapp.com")),
        .init("rectangle",       "Rectangle",         "Move and resize windows with shortcuts",    .utilities, .cask, icon("rectangleapp.com")),
        .init("karabiner-elements", "Karabiner-Elements", "Powerful keyboard customiser for macOS", .utilities, .cask, icon("karabiner-elements.pqrs.org")),
        .init("aldente",         "AlDente",           "Battery charge limiter for long-term health", .utilities, .cask, icon("apphousekitchen.com")),
        .init("stats",           "Stats",             "macOS system monitor in your menu bar",     .utilities, .cask, icon("github.com")),
        .init("jordanbaird-ice", "Ice",               "Powerful menu bar manager — free Bartender alternative", .utilities, .cask, icon("icemenubar.app")),
        .init("betterdisplay",   "BetterDisplay",     "Custom resolutions and display controls",   .utilities, .cask, icon("betterdisplay.app")),
        .init("istat-menus",     "iStat Menus",       "Advanced Mac system monitor",               .utilities, .cask, icon("bjango.com")),
        .init("bettertouchtool", "BetterTouchTool",   "Powerful input device customisation",       .utilities, .cask, icon("folivora.ai")),
        .init("hazel",           "Hazel",             "Automated folder organisation for Mac",     .utilities, .cask, icon("noodlesoft.com")),
        .init("cleanshot",       "CleanShot X",       "Best-in-class screen capture for Mac",      .utilities, .cask, icon("cleanshot.com")),
        .init("transmission",    "Transmission",      "Fast, easy and free BitTorrent client",     .utilities, .cask, icon("transmissionbt.com")),
        .init("calibre",         "Calibre",           "Powerful e-book management",                .utilities, .cask, icon("calibre-ebook.com")),
        .init("alt-tab",         "AltTab",            "Windows-style app switcher for macOS",      .utilities, .cask, icon("alt-tab-macos.netlify.app")),
        .init("aerial",          "Aerial",            "Apple TV aerial screensavers for Mac",      .utilities, .cask, icon("github.com")),
        .init("carbon-copy-cloner", "Carbon Copy Cloner", "Powerful backup and cloning utility",   .utilities, .cask, icon("bombich.com")),
        .init("superduper",      "SuperDuper!",        "Easy, fast, and reliable Mac backup tool", .utilities, .cask, icon("shirt-pocket.com")),
        .init("maccy",           "Maccy",             "Open source clipboard manager for macOS",  .utilities, .cask, icon("maccy.app")),
        .init("swish",           "Swish",             "Intuitive trackpad gestures for macOS",    .utilities, .cask, icon("highlyopinionated.co")),
        .init("superwhisper",    "SuperWhisper",      "AI voice transcription anywhere on Mac",   .utilities, .cask, icon("superwhisper.com")),
        .init("eza",             "eza",               "Modern replacement for ls with colour and icons", .utilities, .formula, icon("eza.rocks")),
        .init("zoxide",          "zoxide",            "Smarter cd that learns your habits",        .utilities, .formula),
        .init("lazygit",         "lazygit",           "Terminal UI for git commands",              .utilities, .formula),
        .init("fd",              "fd",                "Fast and user-friendly find alternative",   .utilities, .formula),
        .init("yazi",            "Yazi",              "Blazing fast terminal file manager",        .utilities, .formula, icon("yazi.rs")),
        .init("tlrc",            "tldr",              "Simplified man pages with examples",        .utilities, .formula, icon("tldr.sh")),
        .init("fzf",             "fzf",               "Command-line fuzzy finder",                 .utilities, .formula),
        .init("ripgrep",         "ripgrep",           "Fast recursive search tool",                .utilities, .formula),
        .init("bat",             "bat",               "cat clone with syntax highlighting",        .utilities, .formula),
        .init("htop",            "htop",              "Interactive process viewer",                .utilities, .formula, icon("htop.dev")),
        .init("git-delta",       "delta",             "Syntax-highlighted git diff viewer",        .utilities, .formula, icon("github.com")),
        .init("duf",             "duf",               "Modern disk usage tool — better df",        .utilities, .formula, icon("github.com")),
        .init("dust",            "dust",              "More intuitive disk usage tool — better du", .utilities, .formula, icon("github.com")),
        .init("glow",            "glow",              "Render Markdown in the terminal",            .utilities, .formula, icon("github.com")),
        .init("hyperfine",       "hyperfine",         "Command-line benchmarking tool",             .utilities, .formula, icon("github.com")),
        .init("difftastic",      "difftastic",        "Structural diff tool that understands code", .utilities, .formula, icon("github.com")),
        .init("tokei",           "tokei",             "Count lines of code quickly",                .utilities, .formula, icon("github.com")),
        .init("bandwhich",       "bandwhich",         "Terminal bandwidth utilisation monitor",     .utilities, .formula, icon("github.com")),
    ]
}
