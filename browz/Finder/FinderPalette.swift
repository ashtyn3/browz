import SwiftUI

/// Shared palette for floating finder-style surfaces that can be gently
/// influenced by the current page tint.
struct FinderPalette {
    let background: Color
    let input: Color
    let stroke: Color
    let divider: Color
    let rowHover: Color
    let rowSelected: Color
    let labelPrimary: Color
    let labelSecondary: Color
    let labelTertiary: Color
    let iconTint: Color

    static func make(pageTint: PageTint?) -> FinderPalette {
        // Base neutral palette (previous hard-coded values).
        let baseBg       = Color.white
        let baseInput    = Color(red: 0.96, green: 0.96, blue: 0.97)
        let baseStroke   = Color.black.opacity(0.08)
        let baseDivider  = Color.black.opacity(0.06)
        let baseRowHover = Color(red: 0.95, green: 0.95, blue: 0.96)
        let baseRowSel   = Color(red: 0.92, green: 0.92, blue: 0.94)
        let baseLabelPri = Color(red: 0.08, green: 0.08, blue: 0.10)
        let baseLabelSec = baseLabelPri.opacity(0.45)
        let baseLabelTer = baseLabelPri.opacity(0.28)
        let baseIconTint = Color(red: 0.40, green: 0.40, blue: 0.44)

        guard let tint = pageTint else {
            return FinderPalette(
                background: baseBg,
                input: baseInput,
                stroke: baseStroke,
                divider: baseDivider,
                rowHover: baseRowHover,
                rowSelected: baseRowSel,
                labelPrimary: baseLabelPri,
                labelSecondary: baseLabelSec,
                labelTertiary: baseLabelTer,
                iconTint: baseIconTint
            )
        }

        func blend(_ base: Color, towards tint: PageTint, amount: Double, assumeWhite: Bool = true) -> Color {
            let clamped = max(0.0, min(1.0, amount))
            let baseR: Double = assumeWhite ? 1.0 : 0.5
            let baseG: Double = assumeWhite ? 1.0 : 0.5
            let baseB: Double = assumeWhite ? 1.0 : 0.5
            let r = baseR * (1 - clamped) + tint.r * clamped
            let g = baseG * (1 - clamped) + tint.g * clamped
            let b = baseB * (1 - clamped) + tint.b * clamped
            return Color(red: r, green: g, blue: b)
        }

        let bg       = blend(baseBg,       towards: tint, amount: 0.14)
        let input    = blend(baseInput,    towards: tint, amount: 0.10)
        let rowHover = blend(baseRowHover, towards: tint, amount: 0.18)
        let rowSel   = blend(baseRowSel,   towards: tint, amount: 0.22)
        let stroke   = blend(baseStroke,   towards: tint, amount: 0.20, assumeWhite: false).opacity(0.9)
        let divider  = blend(baseDivider,  towards: tint, amount: 0.15, assumeWhite: false).opacity(0.9)

        return FinderPalette(
            background: bg,
            input: input,
            stroke: stroke,
            divider: divider,
            rowHover: rowHover,
            rowSelected: rowSel,
            labelPrimary: baseLabelPri,
            labelSecondary: baseLabelSec,
            labelTertiary: baseLabelTer,
            iconTint: baseIconTint
        )
    }
}

