import Foundation

/// The result of an offline unit conversion: the converted numeric `value`, the
/// target `unit`'s display symbol, and a ready-to-show `formatted` string
/// (e.g. `32.1869 km`). The Provider shows `formatted` as the row title and
/// copies it as the main action (issue #8).
public struct Conversion: Equatable, Sendable {
    public let value: Double
    public let unit: String
    public let formatted: String

    public init(value: Double, unit: String, formatted: String) {
        self.value = value
        self.unit = unit
        self.formatted = formatted
    }
}

/// The offline unit-conversion engine behind the Dynamic Calculator Provider
/// (issue #8). It parses a natural-language conversion — `<number> <from> to|in
/// <to>` — and evaluates it through Foundation `Measurement`, so the conversion
/// factors are the platform's, not ours. It returns `nil` when the text is not
/// a conversion it can serve (missing units, unknown units, or a cross-family
/// request like miles → kilograms), which is how the Provider declines cleanly.
///
/// **Currency is out of scope** (network-dependent, deferred — ROADMAP "Later
/// bucket"); only offline, dimensionally-fixed quantities are handled.
///
/// Named `Units` rather than `UnitConverter` to avoid colliding with
/// Foundation's `UnitConverter` class. The interface is one function
/// (`convert`); the unit registry and parsing are private.
public enum Units {

    /// Parses and evaluates `query` as a unit conversion, or returns `nil` when
    /// it is not one. Both units must belong to the same family (length, mass,
    /// temperature, volume) — a cross-family request declines.
    public static func convert(_ query: String) -> Conversion? {
        guard let parsed = parse(query) else { return nil }
        guard let from = registry[parsed.from], let to = registry[parsed.to] else { return nil }
        // Cross-family conversions (miles → kilograms) are not meaningful; the
        // shared family is what makes the `Measurement` conversion valid.
        guard from.family == to.family else { return nil }

        let measurement = Measurement(value: parsed.amount, unit: from.unit)
        let converted = measurement.converted(to: to.unit)
        let rounded = round(converted.value)
        let text = NumberFormat.string(rounded, maxFractionDigits: 4)
        return Conversion(value: rounded, unit: to.symbol, formatted: "\(text) \(to.symbol)")
    }

    // MARK: - Parsing

    /// The three parts of a conversion query: the amount, the source unit token,
    /// and the target unit token (both lowercased for registry lookup).
    private struct Parsed {
        let amount: Double
        let from: String
        let to: String
    }

    /// Matches `<number> <from-unit> (to|in|as) <to-unit>`. The connector word
    /// is `to`, `in`, or `as`; unit tokens may carry the degree/quote symbols
    /// that stand in for temperature and feet/inches.
    private static let pattern = try! NSRegularExpression(
        pattern: #"^\s*(-?\d+(?:\.\d+)?)\s*([a-z°"'µ]+)\s+(?:to|in|as)\s+([a-z°"'µ]+)\s*$"#,
        options: [.caseInsensitive]
    )

    private static func parse(_ query: String) -> Parsed? {
        let lowered = query.lowercased()
        let range = NSRange(lowered.startIndex..., in: lowered)
        guard let match = pattern.firstMatch(in: lowered, range: range),
              let amountRange = Range(match.range(at: 1), in: lowered),
              let fromRange = Range(match.range(at: 2), in: lowered),
              let toRange = Range(match.range(at: 3), in: lowered),
              let amount = Double(lowered[amountRange]) else { return nil }
        return Parsed(amount: amount, from: String(lowered[fromRange]), to: String(lowered[toRange]))
    }

    // MARK: - Unit registry

    /// One recognised unit: the Foundation `Dimension` it maps to, the `family`
    /// that gates cross-family conversions, and the `symbol` shown in results.
    private struct UnitDef {
        let unit: Dimension
        let family: String
        let symbol: String
    }

    /// All units the converter recognises, keyed by every accepted spelling
    /// (lowercased). Grouped by family so a conversion only succeeds within a
    /// family. New units and families are added here, not in the parser.
    private static let registry: [String: UnitDef] = {
        var map: [String: UnitDef] = [:]

        func add(_ aliases: [String], _ unit: Dimension, _ family: String, _ symbol: String) {
            for alias in aliases { map[alias] = UnitDef(unit: unit, family: family, symbol: symbol) }
        }

        // Length
        add(["mm", "millimeter", "millimeters", "millimetre", "millimetres"], UnitLength.millimeters, "length", "mm")
        add(["cm", "centimeter", "centimeters", "centimetre", "centimetres"], UnitLength.centimeters, "length", "cm")
        add(["m", "meter", "meters", "metre", "metres"], UnitLength.meters, "length", "m")
        add(["km", "kilometer", "kilometers", "kilometre", "kilometres"], UnitLength.kilometers, "length", "km")
        add(["in", "inch", "inches", "\""], UnitLength.inches, "length", "in")
        add(["ft", "foot", "feet", "'"], UnitLength.feet, "length", "ft")
        add(["yd", "yard", "yards"], UnitLength.yards, "length", "yd")
        add(["mi", "mile", "miles"], UnitLength.miles, "length", "mi")

        // Mass
        add(["mg", "milligram", "milligrams"], UnitMass.milligrams, "mass", "mg")
        add(["g", "gram", "grams"], UnitMass.grams, "mass", "g")
        add(["kg", "kilogram", "kilograms"], UnitMass.kilograms, "mass", "kg")
        add(["oz", "ounce", "ounces"], UnitMass.ounces, "mass", "oz")
        add(["lb", "lbs", "pound", "pounds"], UnitMass.pounds, "mass", "lb")
        add(["st", "stone", "stones"], UnitMass.stones, "mass", "st")
        add(["t", "tonne", "tonnes", "metricton", "metrictons"], UnitMass.metricTons, "mass", "t")

        // Temperature
        add(["c", "°c", "celsius", "centigrade"], UnitTemperature.celsius, "temperature", "°C")
        add(["f", "°f", "fahrenheit"], UnitTemperature.fahrenheit, "temperature", "°F")
        add(["k", "kelvin"], UnitTemperature.kelvin, "temperature", "K")

        // Volume
        add(["ml", "milliliter", "milliliters", "millilitre", "millilitres"], UnitVolume.milliliters, "volume", "mL")
        add(["l", "liter", "liters", "litre", "litres"], UnitVolume.liters, "volume", "L")
        add(["gal", "gallon", "gallons"], UnitVolume.gallons, "volume", "gal")
        add(["qt", "quart", "quarts"], UnitVolume.quarts, "volume", "qt")
        add(["pt", "pint", "pints"], UnitVolume.pints, "volume", "pt")
        add(["cup", "cups"], UnitVolume.cups, "volume", "cup")
        add(["floz", "fluidounce", "fluidounces"], UnitVolume.fluidOunces, "volume", "fl oz")
        add(["tbsp", "tablespoon", "tablespoons"], UnitVolume.tablespoons, "volume", "tbsp")
        add(["tsp", "teaspoon", "teaspoons"], UnitVolume.teaspoons, "volume", "tsp")

        return map
    }()

    // MARK: - Formatting

    /// Rounds a converted value to four fractional digits — enough precision for
    /// everyday conversions without a wall of float noise. Display formatting is
    /// shared with the Calculator via `NumberFormat`.
    private static func round(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }
}
