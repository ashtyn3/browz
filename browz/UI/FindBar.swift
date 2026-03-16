import SwiftUI

struct FindBar: View {
    @Binding var query: String
    var matchFound: Bool?       // nil = no search yet, true/false = result
    var onNext: () -> Void
    var onPrev: () -> Void
    var onClose: () -> Void

    @FocusState private var isFocused: Bool

    private let bg      = Color.white.opacity(0.90)
    private let stroke  = Color.black.opacity(0.09)
    private let label   = Color(red: 0.08, green: 0.08, blue: 0.10)
    private let sec     = Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.45)

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(sec)

            TextField("Find in page…", text: $query)
                .font(.system(size: 13))
                .foregroundStyle(label)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .frame(minWidth: 180)
                .onSubmit { onNext() }

            if let found = matchFound, !query.isEmpty {
                Text(found ? "Found" : "Not found")
                    .font(.system(size: 11))
                    .foregroundStyle(found ? Color(red: 0.12, green: 0.60, blue: 0.32) : Color.red)
            }

            Spacer()

            HStack(spacing: 4) {
                findBtn(icon: "chevron.up",   action: onPrev)
                findBtn(icon: "chevron.down",  action: onNext)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(sec)
                    .frame(width: 18, height: 18)
                    .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
        .onAppear { isFocused = true }
    }

    private func findBtn(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(sec)
                .frame(width: 26, height: 26)
                .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
