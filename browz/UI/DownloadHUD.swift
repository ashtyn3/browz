import SwiftUI
import AppKit

private let hudBg       = Color.white
private let hudStroke   = Color.black.opacity(0.08)
private let hudDivider  = Color.black.opacity(0.05)
private let labelPri    = Color(red: 0.08, green: 0.08, blue: 0.10)
private let labelSec    = Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.45)
private let labelTer    = Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.28)

struct DownloadHUD: View {
    @ObservedObject var coordinator: DownloadCoordinator
    var onClose: () -> Void
    @State private var autoDismissTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(hudDivider)
            itemList
        }
        .frame(width: 300)
        .background(hudBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(hudStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 24, y: 8)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .onChange(of: coordinator.items.map(\.isTerminal)) { _, terminals in
            scheduleAutoDismissIfNeeded(terminals: terminals)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Downloads")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(labelPri)
            Spacer()
            if coordinator.items.allSatisfy(\.isTerminal) {
                Button("Clear") {
                    coordinator.clearCompleted()
                }
                .font(.system(size: 11))
                .foregroundStyle(labelSec)
                .buttonStyle(.plain)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(labelTer)
                    .frame(width: 18, height: 18)
                    .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var itemList: some View {
        VStack(spacing: 0) {
            ForEach(coordinator.items) { item in
                downloadRow(item)
                if item.id != coordinator.items.last?.id {
                    Divider().overlay(hudDivider).padding(.leading, 14)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func downloadRow(_ item: DownloadItem) -> some View {
        HStack(spacing: 10) {
            stateIcon(item)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(labelPri)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if case .downloading = item.state {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .frame(width: 80)
                            .scaleEffect(x: 1, y: 0.6)
                    }
                    Text(item.sizeLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(labelSec)
                }
            }

            Spacer()

            if case .complete(let url) = item.state {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(labelSec)
                        .frame(width: 24, height: 24)
                        .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func stateIcon(_ item: DownloadItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(stateIconBg(item))
            Image(systemName: stateIconName(item))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(stateIconFg(item))
        }
    }

    private func stateIconName(_ item: DownloadItem) -> String {
        switch item.state {
        case .downloading:  return "arrow.down"
        case .complete:     return "checkmark"
        case .failed:       return "exclamationmark"
        }
    }

    private func stateIconBg(_ item: DownloadItem) -> Color {
        switch item.state {
        case .downloading:  return Color.black.opacity(0.06)
        case .complete:     return Color(red: 0.18, green: 0.78, blue: 0.42).opacity(0.15)
        case .failed:       return Color.red.opacity(0.10)
        }
    }

    private func stateIconFg(_ item: DownloadItem) -> Color {
        switch item.state {
        case .downloading:  return labelSec
        case .complete:     return Color(red: 0.12, green: 0.60, blue: 0.32)
        case .failed:       return Color.red
        }
    }

    private func scheduleAutoDismissIfNeeded(terminals: [Bool]) {
        guard !terminals.isEmpty && terminals.allSatisfy({ $0 }) else {
            autoDismissTask?.cancel()
            return
        }
        autoDismissTask?.cancel()
        autoDismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                coordinator.clearCompleted()
            }
        }
    }
}
