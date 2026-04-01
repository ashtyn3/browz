import SwiftUI
import WebKit

// MARK: - Section model

enum SettingsSection: String, CaseIterable {
    case search   = "Search"
    case tabs     = "Tabs"
    case privacy  = "Privacy"
    case advanced = "Advanced"

    var icon: String {
        switch self {
        case .search:   return "magnifyingglass"
        case .tabs:     return "rectangle.stack"
        case .privacy:  return "lock.shield"
        case .advanced: return "gearshape.2"
        }
    }
}

// MARK: - In-browser settings tab

struct SettingsTabView: View {
    @State private var section: SettingsSection = .search

    private let sidebarBg  = Color(red: 0.96, green: 0.96, blue: 0.97)
    private let contentBg  = Color.white
    private let activeBg   = Color.black.opacity(0.07)
    private let labelColor = Color(red: 0.08, green: 0.08, blue: 0.10)
    private let secondary  = Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.45)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .background(contentBg)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(secondary)
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 12)

            ForEach(SettingsSection.allCases, id: \.self) { s in
                sidebarRow(s)
            }

            Spacer()
        }
        .frame(width: 188)
        .background(sidebarBg)
    }

    private func sidebarRow(_ s: SettingsSection) -> some View {
        Button {
            section = s
        } label: {
            HStack(spacing: 9) {
                Image(systemName: s.icon)
                    .font(.system(size: 13))
                    .frame(width: 18, alignment: .center)
                    .foregroundStyle(section == s ? labelColor : secondary)
                Text(s.rawValue)
                    .font(.system(size: 13, weight: section == s ? .medium : .regular))
                    .foregroundStyle(section == s ? labelColor : secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(section == s ? activeBg : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(section.rawValue)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(labelColor)
                    .padding(.bottom, 20)

                switch section {
                case .search:   SearchSettingsPane()
                case .tabs:     TabsSettingsPane()
                case .privacy:  PrivacySettingsPane()
                case .advanced: AdvancedSettingsPane()
                }
            }
            .padding(36)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(contentBg)
    }
}

// MARK: - Search

struct SearchSettingsPane: View {
    @ObservedObject private var settings = BrowserSettings.shared

    var body: some View {
        Form {
            Section {
                Picker("Search engine", selection: $settings.searchEngine) {
                    ForEach(SearchEngine.allCases) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }

                if settings.searchEngine == .custom {
                    LabeledContent("Search URL") {
                        TextField("https://example.com/search?q=", text: $settings.customSearchBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                    }
                    Text("Append the search query at the end of this URL.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Search Engine")
            }

            Section {
                Picker("New tab shows", selection: $settings.newTabPage) {
                    ForEach(NewTabPage.allCases) { page in
                        Text(page.rawValue).tag(page)
                    }
                }

                if settings.newTabPage == .custom {
                    LabeledContent("URL") {
                        TextField("https://", text: $settings.customNewTabURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                    }
                }
            } header: {
                Text("New Tab Page")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tabs

struct TabsSettingsPane: View {
    @ObservedObject private var settings = BrowserSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Restore tabs on next launch", isOn: $settings.restoreSessionOnLaunch)
            } header: {
                Text("Session")
            }

            Section {
                Toggle("Show keyboard shortcut helper on blank page", isOn: $settings.showKeyboardShortcutHelperOnBlank)
                Text("When you have a single blank tab, show a low-contrast shortcut reference.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Start Screen")
            }

            Section {
                LabeledContent("Discard background tabs after") {
                    Stepper(
                        "\(settings.backgroundTabDiscardLimit) inactive tabs",
                        value: $settings.backgroundTabDiscardLimit,
                        in: 2...32
                    )
                }
                Text("Tabs beyond this limit are discarded from memory and reload when you return to them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Memory Management")
            }

            Section {
                Toggle("Show tab sidebar", isOn: $settings.showTabSidebar)
            } header: {
                Text("Layout")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Privacy

struct PrivacySettingsPane: View {
    @ObservedObject private var settings = BrowserSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Block third-party cookies", isOn: $settings.blockThirdPartyCookies)
            } header: {
                Text("Cookies")
            }

            Section {
                Toggle("Google sign-in compatibility mode", isOn: $settings.googleSignInCompatibilityMode)
                Text("For Google domains, favor compatibility over aggressive tracking protection and UA spoofing to improve sign-in and passkey support.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Google")
            }

            Section {
                Button("Clear Browsing Data…") {
                    clearBrowsingData()
                }
                .foregroundStyle(.red)
            } header: {
                Text("Data")
            }
        }
        .formStyle(.grouped)
    }

    private func clearBrowsingData() {
        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
        ]
        WKWebsiteDataStore.default().removeData(
            ofTypes: types,
            modifiedSince: .distantPast
        ) { }
    }
}

// MARK: - Advanced

struct AdvancedSettingsPane: View {
    @ObservedObject private var settings = BrowserSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable Web Inspector", isOn: $settings.developerExtrasEnabled)
                Text("Right-click any page to access Inspect Element. Takes effect for new tabs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Developer")
            }

            Section {
                LabeledContent("Version") {
                    Text("0.1.0")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("WebKit") {
                    Text(webKitVersionString())
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
    }

    private func webKitVersionString() -> String {
        let info = Bundle(identifier: "com.apple.WebKit")?.infoDictionary
        return info?["CFBundleShortVersionString"] as? String ?? "—"
    }
}
