## Browz

**Browz** is a fast, privacy‑minded web browser for macOS built with SwiftUI and
WebKit. It focuses on a clean, minimal UI, powerful keyboard shortcuts, and
sensible defaults around privacy (content blocking, private tabs, and local‑only
data storage).

---

## Features

- **General‑purpose browser**: Navigate to any `http` or `https` site via a
  single address bar that accepts both URLs and search queries.
- **Tabbed browsing**: Open, close, pin, and reorder multiple tabs; switch
  quickly with keyboard shortcuts.
- **Private tabs**: Create private tabs that do not record history and behave
  like ephemeral sessions.
- **Reader mode**: Toggle a distraction‑free reading experience for
  article‑style pages.
- **Split view**: View two tabs side‑by‑side in a single window.
- **Smart navigation surface**:
  - Fuzzy search across open tabs, history, and bookmarks.
  - Inline suggestions as you type.
- **Downloads HUD**: Lightweight overlay for monitoring and clearing downloads.
- **Workspaces**: Group related tabs into workspaces to keep different contexts
  separated.
- **Content blocking**: Built‑in rules to block many analytics, advertising, and
  tracking scripts by default.

---

## Installation & Building

At the moment Browz is distributed as source; you can build it yourself with
Xcode:

1. Clone this repository.
2. Open `browz.xcodeproj` in Xcode on macOS.
3. Select the `browz` scheme and your desired destination (e.g. “My Mac”).
4. Build and run (`⌘R`).

The app is fully sandboxed. The entitlements are declared in
`browz/browz.entitlements` and explained in more detail in `ARCHITECTURE.md`.

---

## Keyboard Shortcuts (High Level)

- **Tabs**
  - `⌘T` — New tab
  - `⇧⌘N` — New private tab
  - `⌘W` — Close current tab
  - `⌘1` … `⌘9` — Jump to tab 1–9
  - `⇧⌘]` / `⇧⌘[` — Next / previous tab
- **Navigation**
  - `⌘L` — Focus the address bar
  - `⌘K` — Open tab/history/bookmark finder
  - `⌘[` / `⌘]` — Back / forward
  - `⌘R` — Reload
  - `⌘F` — Find in page
- **Zoom**
  - `⌘+` / `⌘-` — Zoom in / out
  - `⌘0` — Reset zoom
- **Other**
  - `⇧⌘R` — Toggle reader mode
  - `⇧⌘\` — Toggle split view
  - `⌘,` — Open settings

(See the `BrowzApp` command menus and `BrowserWindowView` for the authoritative
list.)

---

## Privacy & Data

Browz is designed so that your browsing data stays on your Mac:

- **History**: Stored locally in
  `~/Library/Application Support/.../history.json`, used for suggestions and the
  tab finder. Only `http`/`https` URLs are recorded; private tabs are excluded.
- **Bookmarks**: Stored locally in
  `~/Library/Application Support/.../bookmarks.json`. Created and removed
  explicitly by you.
- **Downloads**: Saved into your standard `~/Downloads` folder. Filenames are
  de‑duplicated to avoid silent overwrites.
- **Settings, workspaces, sessions**: Stored locally in the app’s Application
  Support directory.
- **No analytics**: There are no third‑party analytics SDKs, crash reporters, or
  telemetry libraries in this project.

For a deeper, code‑level discussion of storage locations, models, and sandbox
entitlements, see `ARCHITECTURE.md`.

---

## WebAuthn / Passkeys

Browz supports modern WebAuthn / passkey flows through WebKit:

- Sites can use `navigator.credentials.create()` and
  `navigator.credentials.get()` inside the browser.
- All prompts and credential handling are performed by the system’s passkey UI
  and WebKit implementation.
- Browz does not inspect or store credential material beyond what WebKit and the
  OS manage internally.

To enable this across arbitrary sites, the app requests the
`com.apple.developer.web-browser.public-key-credential` entitlement. The
reasoning and implementation details are documented in `ARCHITECTURE.md`.

---

## Contributing

Contributions, bug reports, and ideas are welcome:

- File issues for bugs or rough edges in everyday browsing.
- Open pull requests for small, focused improvements (UI polish, performance
  tweaks, bug fixes).
- For larger changes, please open an issue first to discuss design and scope.

If you are modifying core browser behavior or entitlements, read
`ARCHITECTURE.md` before making changes so the documentation stays accurate.

---

## License

TBD. Until a formal license is added, please treat this repository as “source
available” for review and personal experimentation only.
