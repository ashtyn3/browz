import SwiftUI

/// Shared button styles for the browser UI.
enum BrowserButtonStyleKind {
    case primary       // solid, high-emphasis
    case secondary     // subtle filled (e.g. workspace pill, small controls)
    case ghost         // text/icon only, minimal background
    case chip          // small keyboard-chip style
    case row           // full-width row-style actions (e.g. Cmd+K items)
}

struct BrowserButton<Label: View>: View {
    let kind: BrowserButtonStyleKind
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    init(
        kind: BrowserButtonStyleKind,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.kind = kind
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .primary:
            label()
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    Color(red: 0.10, green: 0.10, blue: 0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .foregroundStyle(Color.white)
                .hoverElevated(cornerRadius: 8)

        case .secondary:
            label()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Color.white.opacity(0.94),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.09), lineWidth: 1)
                )
                .hoverElevated(cornerRadius: 7)

        case .ghost:
            label()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

        case .chip:
            label()
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Color.white,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                )
                .hoverElevated(cornerRadius: 5, baseOpacity: 0.0, hoverOpacity: 0.10)

        case .row:
            label()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white)
                )
                .hoverElevated(cornerRadius: 10, baseOpacity: 0.0, hoverOpacity: 0.10)
        }
    }
}

// MARK: - Shared hover elevation

struct HoverElevated: ViewModifier {
    let cornerRadius: CGFloat
    let baseOpacity: Double
    let hoverOpacity: Double

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .shadow(
                color: Color.black.opacity(isHovering ? hoverOpacity : baseOpacity),
                radius: isHovering ? 10 : 6,
                y: isHovering ? 5 : 3
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.9), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

extension View {
    func hoverElevated(
        cornerRadius: CGFloat = 7,
        baseOpacity: Double = 0.02,
        hoverOpacity: Double = 0.12
    ) -> some View {
        modifier(HoverElevated(cornerRadius: cornerRadius, baseOpacity: baseOpacity, hoverOpacity: hoverOpacity))
    }
}

