import SwiftUI

struct FormulaIcon {
    let symbol: String
    let color: Color
}

enum FormulaIcons {
    static func icon(for name: String) -> FormulaIcon? {
        if let icon = map[name] { return icon }
        // Strip version suffix: "node@20" -> "node", "python@3.13" -> "python", "icu4c@78" -> "icu4c"
        if let base = name.components(separatedBy: "@").first, let icon = map[base] {
            return icon
        }
        return nil
    }

    private static let map: [String: FormulaIcon] = [

        // MARK: Security & Crypto
        "openssl":          .init("lock.fill",              .red),
        "ca-certificates":  .init("checkmark.seal.fill",    .red),
        "gnupg":            .init("key.fill",               .red),
        "gpg":              .init("key.fill",               .red),
        "mkcert":           .init("lock.shield.fill",       .red),
        "certbot":          .init("checkmark.shield.fill",  .red),
        "libsodium":        .init("lock.shield.fill",       .red),
        "libssh2":          .init("lock.fill",              .red),
        "gnutls":           .init("lock.fill",              .blue),
        "krb5":             .init("lock.fill",              .gray),
        "p11-kit":          .init("key.fill",               .gray),
        "libtasn1":         .init("doc.fill",               .gray),
        "libgpg-error":     .init("exclamationmark.circle.fill", .gray),
        "clamav":           .init("shield.fill",            .red),
        "yara":             .init("shield.fill",            .orange),
        "age":              .init("lock.fill",              .red),

        // MARK: Languages & Runtimes
        "node":             .init("n.circle.fill",          .green),
        "python":           .init("p.circle.fill",          .blue),
        "go":               .init("g.circle.fill",          .blue),
        "ruby":             .init("r.circle.fill",          .red),
        "rust":             .init("r.square.fill",          .orange),
        "php":              .init("p.square.fill",          .indigo),
        "openjdk":          .init("cup.and.saucer.fill",    .orange),
        "java":             .init("cup.and.saucer.fill",    .orange),
        "kotlin":           .init("k.circle.fill",          .purple),
        "scala":            .init("s.circle.fill",          .red),
        "lua":              .init("l.circle.fill",          .blue),
        "perl":             .init("p.circle.fill",          .orange),
        "elixir":           .init("e.circle.fill",          .purple),
        "erlang":           .init("e.square.fill",          .red),
        "ghc":              .init("h.circle.fill",          .indigo),
        "clojure":          .init("c.circle.fill",          .green),
        "llvm":             .init("cpu",                    .gray),
        "deno":             .init("d.circle.fill",          .teal),
        "bun":              .init("b.circle.fill",          .orange),
        "uv":               .init("bolt.fill",              .orange),

        // MARK: Version Managers
        "pyenv":            .init("p.square.fill",          .blue),
        "rbenv":            .init("r.square.fill",          .red),
        "mise":             .init("square.stack.fill",      .teal),
        "asdf":             .init("square.stack.fill",      .orange),

        // MARK: Databases
        "sqlite":           .init("cylinder.fill",          .blue),
        "postgresql":       .init("cylinder.fill",          .blue),
        "mysql":            .init("cylinder.fill",          .orange),
        "mariadb":          .init("cylinder.fill",          .teal),
        "redis":            .init("memorychip",             .red),
        "mongodb":          .init("leaf.fill",              .green),
        "cassandra":        .init("cylinder.fill",          .blue),
        "elasticsearch":    .init("magnifyingglass.circle.fill", .teal),

        // MARK: Build Tools
        "cmake":            .init("hammer.fill",            .brown),
        "make":             .init("hammer.fill",            .brown),
        "ninja":            .init("bolt.fill",              .yellow),
        "meson":            .init("hammer.circle.fill",     .brown),
        "gcc":              .init("hammer.fill",            .orange),
        "gradle":           .init("g.circle.fill",          .teal),
        "maven":            .init("m.circle.fill",          .orange),
        "bazel":            .init("hexagon.fill",           .green),
        "xcodegen":         .init("hammer.fill",            .blue),
        "xcbeautify":       .init("hammer.fill",            .blue),
        "pkgconf":          .init("shippingbox.fill",       .gray),

        // MARK: Version Control
        "git":              .init("arrow.triangle.branch",  .orange),
        "gh":               .init("chevron.left.forwardslash.chevron.right", .gray),
        "hub":              .init("chevron.left.forwardslash.chevron.right", .gray),
        "git-lfs":          .init("arrow.triangle.branch",  .orange),
        "lazygit":          .init("arrow.triangle.branch",  .orange),
        "libgit2":          .init("arrow.triangle.branch",  .orange),

        // MARK: Cloud & DevOps
        "awscli":           .init("cloud.fill",             .orange),
        "azure-cli":        .init("cloud.fill",             .blue),
        "docker":           .init("shippingbox.fill",       .blue),
        "docker-desktop":   .init("shippingbox.fill",       .blue),
        "terraform":        .init("cube.fill",              .purple),
        "ansible":          .init("a.circle.fill",          .red),
        "kubectl":          .init("cube.box.fill",          .blue),
        "kubernetes-cli":   .init("cube.box.fill",          .blue),
        "k9s":              .init("cube.box.fill",          .green),
        "vagrant":          .init("v.circle.fill",          .blue),
        "packer":           .init("archivebox.fill",        .blue),
        "vault":            .init("lock.fill",              .yellow),
        "consul":           .init("network",                .pink),
        "nomad":            .init("n.circle.fill",          .green),
        "helm":             .init("arrow.up.forward.square.fill", .blue),
        "minikube":         .init("cube.box.fill",          .teal),

        // MARK: Compression & Archives
        "xz":               .init("archivebox.fill",        .gray),
        "lz4":              .init("archivebox.fill",        .gray),
        "zstd":             .init("archivebox.fill",        .gray),
        "brotli":           .init("archivebox.fill",        .gray),
        "libarchive":       .init("archivebox.fill",        .gray),
        "p7zip":            .init("archivebox.fill",        .gray),

        // MARK: Media
        "ffmpeg":           .init("film.fill",              .red),
        "imagemagick":      .init("photo.on.rectangle.fill", .purple),
        "jpeg-turbo":       .init("photo.fill",             .orange),
        "libpng":           .init("photo.fill",             .orange),
        "webp":             .init("photo.fill",             .teal),
        "gifsicle":         .init("photo.fill",             .blue),
        "libtiff":          .init("photo.fill",             .gray),
        "openexr":          .init("photo.fill",             .gray),
        "aom":              .init("film.fill",              .blue),
        "dav1d":            .init("film.fill",              .blue),
        "jpeg-xl":          .init("photo.fill",             .purple),
        "tesseract":        .init("text.viewfinder",        .blue),
        "ghostscript":      .init("doc.fill",               .gray),
        "openjph":          .init("photo.fill",             .blue),

        // MARK: Network
        "curl":             .init("arrow.down.circle.fill", .blue),
        "wget":             .init("arrow.down.circle.fill", .blue),
        "libnghttp2":       .init("network",                .teal),
        "libnghttp3":       .init("network",                .teal),
        "libngtcp2":        .init("network",                .teal),
        "c-ares":           .init("network",                .gray),
        "unbound":          .init("network",                .blue),
        "yt-dlp":           .init("arrow.down.circle.fill", .red),
        "youtube-dl":       .init("arrow.down.circle.fill", .red),
        "aria2":            .init("arrow.down.to.line.compact", .blue),
        "mole":             .init("network",                .green),
        "ngrok":            .init("network",                .orange),
        "nmap":             .init("network",                .green),
        "mtr":              .init("network",                .teal),

        // MARK: CLI Productivity
        "bat":              .init("doc.text.fill",          .orange),
        "ripgrep":          .init("magnifyingglass",        .blue),
        "fd":               .init("folder.fill",            .blue),
        "fzf":              .init("magnifyingglass.circle.fill", .teal),
        "jq":               .init("curlybraces",            .yellow),
        "yq":               .init("curlybraces",            .orange),
        "htop":             .init("cpu",                    .green),
        "btop":             .init("cpu",                    .green),
        "ncdu":             .init("internaldrive.fill",     .orange),
        "tree":             .init("list.bullet.indent",     .green),
        "coreutils":        .init("terminal.fill",          .green),
        "tmux":             .init("rectangle.split.2x1",    .green),
        "vim":              .init("pencil.circle.fill",     .green),
        "neovim":           .init("pencil.circle.fill",     .teal),
        "emacs":            .init("e.circle.fill",          .purple),
        "nano":             .init("pencil",                 .blue),
        "zoxide":           .init("arrow.forward.circle.fill", .blue),
        "autojump":         .init("arrow.forward.circle.fill", .blue),
        "eza":              .init("list.bullet",            .teal),
        "exa":              .init("list.bullet",            .teal),
        "starship":         .init("star.fill",              .yellow),
        "tldr":             .init("questionmark.circle.fill", .blue),
        "tlrc":             .init("questionmark.circle.fill", .blue),
        "watchman":         .init("eye.fill",               .orange),
        "direnv":           .init("folder.badge.gear",      .orange),
        "topgrade":         .init("arrow.up.circle.fill",   .green),
        "mas":              .init("bag.fill",               .blue),
        "gemini-cli":       .init("sparkles",               .purple),
        "pandoc":           .init("doc.richtext.fill",      .indigo),

        // MARK: Text & Fonts
        "harfbuzz":         .init("textformat.abc",         .indigo),
        "fontconfig":       .init("textformat",             .indigo),
        "freetype":         .init("textformat",             .indigo),
        "pango":            .init("textformat.abc",         .indigo),
        "gettext":          .init("textformat",             .gray),
        "libunistring":     .init("textformat",             .gray),
        "readline":         .init("terminal",               .gray),

        // MARK: Data Formats & Libraries
        "protobuf":         .init("cube.fill",              .blue),
        "simdjson":         .init("curlybraces",            .blue),
        "jansson":          .init("curlybraces",            .gray),
        "json-c":           .init("curlybraces",            .gray),
        "abseil":           .init("a.circle.fill",          .blue),

        // MARK: System Libraries
        "glib":             .init("g.circle.fill",          .orange),
        "gmp":              .init("number.circle.fill",     .gray),
        "pcre2":            .init("magnifyingglass",        .gray),
        "mpdecimal":        .init("number.circle.fill",     .gray),
        "libuv":            .init("bolt.fill",              .green),
        "ncurses":          .init("terminal",               .gray),
        "libidn2":          .init("network",                .gray),
        "libffi":           .init("f.circle.fill",          .gray),
        "libevent":         .init("bolt.fill",              .gray),
        "libmagic":         .init("wand.and.stars",         .purple),
        "zlib":             .init("archivebox.fill",        .gray),
        "expat":            .init("e.circle.fill",          .gray),
        "icu4c":            .init("globe",                  .blue),
        "oniguruma":        .init("o.circle.fill",          .gray),
        "libiconv":         .init("textformat",             .gray),
        "libyaml":          .init("curlybraces",            .gray),
        "simdutf":          .init("textformat",             .gray),
        "uvwasi":           .init("bolt.fill",              .green),
        "z3":               .init("function",               .blue),
        "nettle":           .init("n.circle.fill",          .gray),

        // MARK: Graphics
        "cairo":            .init("paintbrush.fill",        .purple),
        "pixman":           .init("rectangle.3.group.fill", .gray),
        "giflib":           .init("photo.fill",             .gray),
    ]
}

private extension FormulaIcon {
    init(_ symbol: String, _ color: Color) {
        self.symbol = symbol
        self.color = color
    }
}
