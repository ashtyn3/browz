## Browz – Browser Architecture & Entitlements

This document explains how **Browz** works as a general‑purpose web browser, how it uses WebKit, how it stores your data locally, and why it requests the `com.apple.developer.web-browser.public-key-credential` entitlement for WebAuthn/passkeys. It is written both for users and contributors who want to understand how the app behaves, and for reviewers who need a deeper technical overview.

---

## 1. High‑level Overview

- **Platform**: macOS, SwiftUI + WebKit (`WKWebView`).
- **Role**: General‑purpose, tabbed web browser capable of navigating to arbitrary `http` and `https` URLs.
- **Primary capabilities**:
  - Address bar that accepts arbitrary URLs and search queries.
  - Multiple tabs, including **regular** and **private** tabs.
  - Navigation controls: back, forward, reload, zoom.
  - Reader mode, ad/tracker blocking, and tab/workspace organization.
  - File downloads into the user’s standard `Downloads` folder.
  - Local, on-device history and bookmarks (no sync or remote storage).

The app does **not** use private APIs and is fully sandboxed.

---

## 2. Entitlements and Sandbox

`browz/browz.entitlements` declares:

- `com.apple.security.app-sandbox = true`
- `com.apple.developer.web-browser.public-key-credential = true`
- `com.apple.security.files.downloads.read-write = true`
- `com.apple.security.files.user-selected.read-write = true`
- `com.apple.security.network.client = true`

**Purpose of each entitlement**:

- **App sandbox**: Required for Mac App Store and to restrict the app’s access to system resources.
- **Web browser public-key credential**: Required for a **general-purpose browser** that wishes to support WebAuthn/passkeys on arbitrary websites, not just fixed first‑party domains.
- **Downloads read-write**: Allows saving website‑initiated downloads to the user’s `Downloads` folder.
- **User-selected read-write**: Allows the user to pick files (e.g., upload in forms) and for the browser to read/write only those selected locations.
- **Network client**: Allows outgoing network connections to arbitrary web servers for general browsing.

No additional system entitlements (e.g. for contacts, photos, camera, microphone, etc.) are requested.

---

## 3. Browser Architecture

### 3.1 Entry point and main window

- The main app entry point is `BrowzApp` (`browz/BrowzApp.swift`).
- `@main struct BrowzApp: App` creates a `BrowserController` and renders `BrowserWindowView(controller:)` inside a `WindowGroup`.
- The app exposes menu commands (Tabs, Navigation, Bookmarks, Settings) that delegate to methods on `BrowserController`:
  - Tab management: `newTab()`, `newPrivateTab()`, `closeSelectedTab()`, selection and pinning.
  - Navigation: `goBack()`, `goForward()`, `reload()`.
  - Address bar: `presentNavigationSurface()`, `navigateSelected(to:)`.
  - Other browser features: find in page, zoom, reader mode, split view, settings.

This wiring demonstrates that the app’s primary purpose is browsing arbitrary web content, not hosting a single fixed web app.

### 3.2 BrowserController and tab model

- `BrowserController` (`BrowzApp.swift`) is the central observable object that coordinates:
  - `TabStateStore` – in‑memory tab state and persistence snapshot.
  - `TabRuntimeRegistry` – manages live `WKWebView` instances for each tab, including navigation callbacks, progress, downloads, dialogs and reader mode.
  - `HistoryStore` – records visits to `http`/`https` URLs.
  - `BookmarkStore` – manages user bookmarks.
  - `WorkspaceStore` – groups tabs into workspaces.
  - `DownloadCoordinator` – handles `WKDownload` and saved files.
  - `JSDialogPresenter` – presents JavaScript dialogs (alert/confirm/etc.).
  - `TabSessionPersistence` and `TabMemoryManager` – restore prior sessions and manage resource usage.

When a user navigates:

1. `BrowserController.navigateSelected(to:)` takes the address bar input.
2. It calls `BrowserSettings.shared.resolve(input:)` to turn search queries or domain names into a proper `URL`.
3. It acquires a `WKWebView` instance from `TabRuntimeRegistry.webView(for:callback:)`.
4. It calls `webView.load(URLRequest(url: url))`.
5. Navigation updates (title and URL) are fed back via the callback into `store.updateNavigation(...)`.

This cycle demonstrates a standard WKWebView-based browser that accepts arbitrary URLs and reacts to site navigation.

### 3.3 WebViewContainer and hosting of WKWebView

- `WebViewContainer` (`browz/WebKit/WebViewContainer.swift`) is an `NSViewRepresentable` that embeds the appropriate `WKWebView` for a given `TabState` into SwiftUI.
- The view:
  - Asks `TabRuntimeRegistry` for the correct `WKWebView` instance for the current tab.
  - Ensures the correct webview is hosted in the container and resizes it to match.
  - Removes stale subviews when the tab changes.

All actual content rendering and WebAuthn/passkey UX are handled by WebKit within these web views.

### 3.4 Main browser UI (address bar, tabs, split view)

- `BrowserWindowView` (`browz/UI/BrowserWindowView.swift`) is the main browser UI:
  - **Top bar** with:
    - Current tab title.
    - Private tab indicator.
    - Reader mode toggle.
    - Bookmark toggle.
    - Zoom indicator/reset.
    - Download indicator.
  - **Navigation surface** shown when the address bar is active:
    - Text field labeled “URL or search” which accepts arbitrary `http/https` URLs or queries.
    - Navigation buttons (back, forward, reload).
    - An inline suggestion list fed by `SuggestionService` based on history/bookmarks and possibly search heuristics.
  - **Content area**:
    - Displays either a single `WebViewContainer` for the active tab, or a **split view** with two containers side by side when split mode is enabled.
  - **Find in page**:
    - `FindBar` overlay is shown and bound to `BrowserController` methods (`findNext`, `findPrev`, `clearFind`).

The UI is that of a general web browser (arbitrary address bar input, multiple tabs, split panes), not a single-purpose web wrapper.

---

## 4. WebAuthn / Passkeys and the Entitlement

### 4.1 Why `com.apple.developer.web-browser.public-key-credential` is needed

Browz is a **general‑purpose web browser** built on `WKWebView`. It:

- Allows users to navigate to arbitrary `http` and `https` URLs via its address bar.
- Does not constrain navigation to a fixed or first‑party domain.
- Intends to support modern web authentication flows, including **WebAuthn / passkeys**, on any site that supports them.

On macOS, the `com.apple.developer.web-browser.public-key-credential` entitlement is required for a general‑purpose browser to:

- Integrate with the system’s passkey/WebAuthn infrastructure.
- Allow sites to call `navigator.credentials.create()` / `navigator.credentials.get()` and obtain public-key credentials via the system UI.
- Do this across arbitrary domains, not just a predefined set.

Browz does not implement its own cryptography or key storage for WebAuthn. It relies entirely on the system’s WebKit implementation and associated system dialogs.

### 4.2 How WebAuthn is handled

- WebAuthn prompts are surfaced by WebKit within the standard system UI for passkeys.
- The app does **not** inspect, intercept, or log credential material.
- The browser simply allows the `WKWebView` to present and handle these flows as designed by Apple’s WebKit/WebAuthn implementation.

No additional data is stored by Browz for WebAuthn beyond whatever WebKit and the system manage internally.

---

## 5. Content Blocking and Privacy Protections

### 5.1 Content blocker

- `ContentBlocker` (`browz/ContentBlocking/ContentBlocker.swift`) builds a `WKContentRuleList` with rules that:
  - Block known analytics, advertising, and tracking domains (e.g. Google Analytics, DoubleClick, Hotjar, Mixpanel, etc.).
  - Target resource types such as `script`, `fetch`, `image`, and `xmlhttprequest`.
- A rule list is compiled and cached via `WKContentRuleListStore.default()`.
- `BrowserController` loads the rule list asynchronously at startup and assigns it to `runtimeRegistry.contentRuleList`, which is then applied to webviews.

This improves privacy by preventing many third‑party trackers from loading at all.

### 5.2 Private tabs

- `BrowserController.newPrivateTab(...)` creates tabs with `isPrivate: true`.
- For navigation updates (`navigationDidUpdate(tabID:title:url:)`), the code checks if the tab is private:
  - If `isPrivate == true`, history entries are **not** recorded.
  - Only non‑private (`regular`) tabs record visits in `HistoryStore`.
- Private tabs function as ephemeral sessions:
  - No entries are added to history.
  - Bookmarks are **never** created automatically; users must explicitly save a bookmark, and only for non-private pages.

---

## 6. Data Storage and Privacy

### 6.1 History

- Implementation: `HistoryStore` (`browz/History/HistoryStore.swift`).
- Data model: `HistoryEntry` items containing:
  - Title.
  - URL string.
  - Timestamp of last visit.
- Storage:
  - Stored **locally** in the user’s Application Support directory:
    - `~/Library/Application Support/com.local.aob/history.json`
  - Limited to `maxEntries = 5000`; older entries are trimmed.
  - Writes are debounced and saved as JSON.
- Scope:
  - Only `http` and `https` URLs are recorded.
  - Private tabs are excluded (no recording).
- Features:
  - Provides search (`search(query:limit:)`) using a fuzzy matcher to power suggestions and `Find Tab` UX.

No browsing history is transmitted off-device or synced to any remote server by this app.

### 6.2 Bookmarks

- Implementation: `BookmarkStore` (`browz/Bookmarks/BookmarkStore.swift`).
- Data model: `BookmarkEntry` items containing:
  - Title.
  - URL string.
  - Stable UUID identifier.
- Storage:
  - Stored as JSON in Application Support:
    - `~/Library/Application Support/AOB/bookmarks.json`
- Behavior:
  - Bookmarks are only added explicitly by the user via UI actions (`bookmarkCurrentTab`).
  - Duplicate URLs are prevented.
  - Users can remove bookmarks by ID or URL.
  - Search is a simple case-insensitive filter over title and URL.

Bookmarks are not synced or transmitted off-device.

### 6.3 Downloads

- Implementation: `DownloadCoordinator` (`browz/Downloads/DownloadCoordinator.swift`) plus `DownloadItem`.
- Flow:
  - When a site initiates a download, WebKit creates a `WKDownload` object, which is routed to `DownloadCoordinator.handle(_:)`.
  - `DownloadCoordinator` acts as the `WKDownloadDelegate`.
  - In `decideDestinationUsing:suggestedFilename:completionHandler:`:
    - The destination is chosen under the user’s standard `Downloads` directory.
    - A helper (`uniqueURL(for:)`) ensures filenames do not silently overwrite existing files.
  - Download state is tracked in `items` to power a download HUD UI (`DownloadHUD`).
- Permissions:
  - Uses `com.apple.security.files.downloads.read-write` to write into `~/Downloads`.

The app does not inspect the content of downloaded files beyond what is required to save them and track progress.

### 6.4 Other local state

- **Tab session**:
  - `TabSessionPersistence` snapshots tab state and selected tab, saving it locally so sessions can be restored.
  - This includes URLs and some per-tab metadata (e.g., pinned, last accessed).
- **Workspaces**:
  - `WorkspaceStore` groups tabs into logical collections (workspaces) and stores this metadata locally.
- **Settings**:
  - `BrowserSettings` holds user preferences such as default new tab URL and search behavior, stored on-device.

No analytics SDKs, crash-reporting backends, or third‑party telemetry libraries are used in this codebase; there is no network transmission of browsing data beyond standard web requests initiated by the user’s navigation.

---

## 7. User Interaction and Scope of Browsing

- **Address bar**:
  - Accepts arbitrary text and resolves it to either:
    - Direct URL navigation (for well‑formed URLs), or
    - A search URL (using the configured search engine) for free‑form queries.
  - Suggestions shown under the address bar are derived from local history and bookmarks.
- **Navigation scope**:
  - The browser does not restrict navigation by host, path, or scheme beyond:
    - Legitimate security restrictions enforced by WebKit.
    - Only `http`/`https` URLs being recorded in history.
- **Multiple windows / tabs**:
  - Apps can have many tabs, pinned tabs, and optionally a split view with two pages visible at once.
- **Reader mode**:
  - Reader mode (`ReaderMode` via `TabRuntimeRegistry`) activates a simplified view for articles, controlled entirely on the client.

Overall, Browz behaves as a typical modern multi-tab web browser.

---

## 8. Security Considerations

- The app is fully sandboxed and only requests:
  - Outbound network client access.
  - Access to the Downloads directory.
  - Access to user-selected files.
  - Web browser public-key credential entitlement for WebAuthn/passkey support.
- There are no:
  - Private API calls.
  - Elevated entitlements for sensitive resources (camera, microphone, contacts, etc.).
  - Background services or daemons.
- All history, bookmarks, workspace data and settings are stored locally in JSON under the app’s Application Support container.
- Content blocking reduces tracking surface area by preventing common analytics/advertising URLs from loading.

The WebAuthn/passkey flows are delegated entirely to WebKit and system UI.

---

## 9. How to Build and Verify

1. Clone the GitHub repository.
2. Open `browz.xcodeproj` in Xcode on macOS.
3. Select the `browz` target and ensure the `browz.entitlements` file is associated with it.
4. Build and run the app.
5. In the running browser:
   - Use the address bar (`⌘L`) to navigate to arbitrary `https://` websites.
   - Open multiple tabs (`⌘T`), including private tabs (`⇧⌘N`).
   - Confirm history and bookmarks behavior using the fuzzy finder (`⌘K`).
   - Visit a site that supports WebAuthn/passkeys and initiate login or registration:
     - The standard system passkey UI should appear.
     - Authentication should complete successfully via the system’s passkey infrastructure.

This demonstrates that the app functions as a full general‑purpose browser and also provides concrete context for the `com.apple.developer.web-browser.public-key-credential` entitlement.

