import Foundation

/// Locale-independent number-to-string formatting shared by the Calculator
/// result row and the unit converter (issue #8). It always uses a `.` decimal
/// separator and no grouping — the result is a value to *copy and paste*, not a
/// localised display string — and trims trailing zeros so whole results read as
/// `161`, not `161.0000000000`.
enum NumberFormat {

    /// Formats `value` with up to `maxFractionDigits` of fractional precision,
    /// rounding first (which absorbs binary-floating-point noise so `0.1 + 0.2`
    /// reads as `0.3`) and then dropping any trailing zeros. Whole values render
    /// without a decimal point.
    static func string(_ value: Double, maxFractionDigits: Int) -> String {
        let scale = pow(10.0, Double(maxFractionDigits))
        var rounded = (value * scale).rounded() / scale
        if rounded == 0 { rounded = 0 } // normalise -0 to 0

        if rounded == rounded.rounded() {
            return String(format: "%.0f", rounded)
        }
        var text = String(format: "%.\(maxFractionDigits)f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
