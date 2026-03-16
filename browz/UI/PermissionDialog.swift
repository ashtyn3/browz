import Combine
import SwiftUI

// MARK: - Request model

enum PermissionType {
    case camera
    case microphone
    case cameraAndMicrophone
    case location

    var label: String {
        switch self {
        case .camera:              return "camera"
        case .microphone:          return "microphone"
        case .cameraAndMicrophone: return "camera and microphone"
        case .location:            return "location"
        }
    }

    var systemImage: String {
        switch self {
        case .camera:              return "video"
        case .microphone:          return "mic"
        case .cameraAndMicrophone: return "video.badge.waveform"
        case .location:            return "location"
        }
    }
}

struct PermissionRequest: Identifiable {
    let id = UUID()
    let host: String
    let type: PermissionType
    let decision: (Bool) -> Void
}

// MARK: - Presenter

@MainActor
final class PermissionPresenter: ObservableObject {
    @Published var request: PermissionRequest?

    func present(_ request: PermissionRequest) {
#if DEBUG
        print("[Permission] 🪟 PermissionPresenter.present() called for \(request.host)")
#endif
        dismissCurrent(allowed: false)
        self.request = request
#if DEBUG
        print("[Permission] 🪟 self.request is now \(self.request == nil ? "nil" : "set")")
#endif
    }

    func dismissCurrent(allowed: Bool) {
        guard let r = request else { return }
        request = nil
        r.decision(allowed)
    }
}

// MARK: - Overlay view

struct PermissionOverlay: View {
    @ObservedObject var presenter: PermissionPresenter

    var body: some View {
        if let req = presenter.request {
            ZStack {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .allowsHitTesting(true)

                PermissionCard(request: req, presenter: presenter)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            .animation(.spring(duration: 0.2), value: presenter.request?.id)
        }
    }
}

// MARK: - Card

private struct PermissionCard: View {
    let request: PermissionRequest
    @ObservedObject var presenter: PermissionPresenter

    private let bg     = Color.white
    private let stroke = Color.black.opacity(0.08)
    private let pri    = Color(red: 0.08, green: 0.08, blue: 0.10)
    private let sec    = Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.45)
    private let ter    = Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.26)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // source chip
            HStack {
                Image(systemName: "globe")
                    .font(.system(size: 10))
                    .foregroundStyle(ter)
                Text(request.host)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(sec)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()
                .overlay(Color.black.opacity(0.06))

            // icon + message
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: request.type.systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(pri)
                    .frame(width: 28, alignment: .center)
                    .padding(.top, 2)

                Text("\"\(request.host)\" wants to use your \(request.type.label).")
                    .font(.system(size: 13))
                    .foregroundStyle(pri)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()
                .overlay(Color.black.opacity(0.06))

            // buttons
            HStack(spacing: 8) {
                Spacer()
                denyButton
                allowButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 360)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 32, y: 12)
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }

    private var allowButton: some View {
        Button {
            presenter.request = nil
            request.decision(true)
        } label: {
            Text("Allow")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .background(
                    Color(red: 0.10, green: 0.10, blue: 0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: [])
    }

    private var denyButton: some View {
        Button {
            presenter.request = nil
            request.decision(false)
        } label: {
            Text("Don't Allow")
                .font(.system(size: 13))
                .foregroundStyle(sec)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    Color.black.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.escape, modifiers: [])
    }
}
