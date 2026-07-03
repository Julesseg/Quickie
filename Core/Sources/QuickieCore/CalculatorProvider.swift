import Foundation

/// The built-in **Dynamic Provider** for calculation and unit conversion (issue
/// #8). It inspects the live query and, when it parses as math or an offline
/// unit conversion, injects a single result whose main action **copies** the
/// answer. The SearchEngine floats a Dynamic Provider's result to the top of the
/// Result list (boosted rank), so the answer reads as a top hit even though it
/// is not a name match (ADR 0008).
///
/// It declines cleanly — returning `[]` — for anything that is neither math nor
/// a conversion, so it never adds a spurious row. Math is tried first; a bare
/// number (no operator) is *not* treated as a calculation. Currency is out of
/// scope (network-dependent, deferred).
public struct CalculatorProvider: Provider {
    public let kind: ProviderKind = .dynamic

    /// The Calculator is a configurable kind (issue #67): its Enabled toggle
    /// governs the injected result, though its typed settings command row rides
    /// the built-ins and stays.
    public let id: ProviderID? = .calculator

    /// Whether offline unit conversions are answered too (CONTEXT.md → Calculator;
    /// ADR 0020, issue #69), gated by the Calculator's unit-conversion schema toggle.
    /// Off keeps the provider to arithmetic only; defaults on so the Core stays fully
    /// functional and the App merely reflects the user's stored preference.
    private let unitConversion: Bool

    public init(unitConversion: Bool = true) {
        self.unitConversion = unitConversion
    }

    public func candidates(for query: String) -> [Action] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Math first. A query that evaluates but carries no operator is just a
        // bare number, not a calculation — declining keeps "42" from spawning a
        // pointless "copy 42" row.
        if isCalculation(trimmed), let value = Calculator.evaluate(trimmed) {
            let answer = NumberFormat.string(value, maxFractionDigits: 10)
            return [result(id: "calc.math", title: answer, subtitle: trimmed, copying: answer)]
        }

        // Otherwise an offline unit conversion, when enabled and the query parses.
        if unitConversion, let conversion = Units.convert(trimmed) {
            return [result(id: "calc.conversion", title: conversion.formatted, subtitle: trimmed, copying: conversion.formatted)]
        }

        return []
    }

    /// True when the query carries an arithmetic operator (or the `of` keyword) —
    /// the signal that the user is *calculating*, not merely typing a number.
    /// `of` is matched on word boundaries so it triggers on "15% of 200" but not
    /// on words that merely contain the letters (`profile`, `off`).
    private func isCalculation(_ query: String) -> Bool {
        if query.contains(where: { "+-*/^%()".contains($0) }) { return true }
        return query.range(of: "\\bof\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Builds the boosted result row: its title is the answer, its subtitle the
    /// expression that produced it, and its main action copies the answer
    /// (CONTEXT.md → main action). It produces a `.number` and consumes nothing —
    /// it is self-contained, like a Snippet, not a Fallback.
    private func result(id: String, title: String, subtitle: String, copying copy: String) -> Action {
        Action(
            id: id,
            kind: .calculator,
            title: title,
            subtitle: subtitle,
            inputTypes: [],
            outputType: .number,
            // Declared `.number` content (ADR 0017), *not* derived from the
            // copy-text outcome: the answer reads as a number even though tapping
            // it copies text. This is the one factory the derive-from-outcome
            // default can't get right, so it overrides.
            content: .number
        ) { _ in .copyText(copy) }
    }
}
