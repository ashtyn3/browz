import SwiftUI

// MARK: - Request model

enum JSDialogKind {
    case alert(completion: () -> Void)
    case confirm(completion: (Bool) -> Void)
    case prompt(defaultText: String?, completion: (String?) -> Void)
}

struct JSDialogRequest: Identifiable {
    let id = UUID()
    let message: String
    let source: String        // e.g. "example.com"
    let kind: JSDialogKind
}

// MARK: - Presenter

@MainActor
final class JSDialogPresenter: ObservableObject {
    @Published var request: JSDialogRequest?

    func present(_ request: JSDialogRequest) {
        // dismiss previous (call cancel) before replacing
        dismissCurrent(cancelled: true)
        self.request = request
    }

    func dismissCurrent(cancelled: Bool = false) {
        guard let r = request else { return }
        request = nil
        switch r.kind {
        case .alert(let done):
            if cancelled { done() }
        case .confirm(let done):
            if cancelled { done(false) }
        case .prompt(_, let done):
            if cancelled { done(nil) }
        }
    }
}

// MARK: - Overlay view

struct JSDialogOverlay: View {
    @ObservedObject var presenter: JSDialogPresenter

    var body: some View {
        if let req = presenter.request {
            ZStack {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .allowsHitTesting(true)

                DialogCard(request: req, presenter: presenter)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            .animation(.spring(duration: 0.2), value: presenter.request?.id)
        }
    }
}

// MARK: - Card

private struct DialogCard: View {
    let request: JSDialogRequest
    @ObservedObject var presenter: JSDialogPresenter

    @State private var inputText: String = ""
    @FocusState private var inputFocused: Bool

    private let bg      = Color.white
    private let stroke  = Color.black.opacity(0.08)
    private let pri     = Color(red: 0.08, green: 0.08, blue: 0.10)
    private let sec     = Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.45)
    private let ter     = Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.26)
    private let inputBg = Color(red: 0.96, green: 0.96, blue: 0.97)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // source chip
            HStack {
                Image(systemName: "globe")
                    .font(.system(size: 10))
                    .foregroundStyle(ter)
                Text(request.source)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(sec)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()
                .overlay(Color.black.opacity(0.06))

            // message
            ScrollView {
                Text(request.message)
                    .font(.system(size: 13))
                    .foregroundStyle(pri)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
            .frame(maxHeight: 160)

            // prompt input field
            if case .prompt(let defaultText, _) = request.kind {
                TextField("", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(pri)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(inputBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(stroke, lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .focused($inputFocused)
                    .onSubmit { submit() }
                    .onAppear {
                        inputText = defaultText ?? ""
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            inputFocused = true
                        }
                    }
            }

            Divider()
                .overlay(Color.black.opacity(0.06))

            // buttons
            HStack(spacing: 8) {
                Spacer()
                if hasCancel {
                    cancelButton
                }
                okButton
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

    private var hasCancel: Bool {
        switch request.kind {
        case .alert: return false
        case .confirm, .prompt: return true
        }
    }

    private var okButton: some View {
        Button(action: submit) {
            Text("OK")
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

    private var cancelButton: some View {
        Button(action: cancel) {
            Text("Cancel")
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

    private func submit() {
        presenter.request = nil
        switch request.kind {
        case .alert(let done):
            done()
        case .confirm(let done):
            done(true)
        case .prompt(_, let done):
            done(inputText)
        }
    }

    private func cancel() {
        presenter.request = nil
        switch request.kind {
        case .alert(let done):
            done()
        case .confirm(let done):
            done(false)
        case .prompt(_, let done):
            done(nil)
        }
    }
}
