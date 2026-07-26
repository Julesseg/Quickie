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
    ///
    /// The connector words come from the accepted date keyword tables (ADR
    /// 0036; issue #211) — the same tables that localize the date grammar — so
    /// "5 m en pieds" converts on a French device while "5 m to ft" converts
    /// everywhere. Defaults to English alone, the dual-accept floor.
    public static func convert(_ query: String, tables: [DateKeywordTable] = [.english]) -> Conversion? {
        guard let parsed = parse(query, tables: tables) else { return nil }
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

    /// Matches `<number> <from-unit> <connector> <to-unit>`. The connector word
    /// is validated against the accepted tables *after* the match — the shape
    /// is language-independent, the words are table data (ADR 0036). Unit
    /// tokens accept any letters (accented names like "mètres" and "fuß"
    /// included) plus the degree/quote symbols that stand in for temperature
    /// and feet/inches.
    private static let pattern = try! NSRegularExpression(
        pattern: #"^\s*(-?\d+(?:\.\d+)?)\s*([\p{L}°"'µ]+)\s+([\p{L}°"'µ]+)\s+([\p{L}°"'µ]+)\s*$"#,
        options: [.caseInsensitive]
    )

    private static func parse(_ query: String, tables: [DateKeywordTable]) -> Parsed? {
        let lowered = query.lowercased()
        let range = NSRange(lowered.startIndex..., in: lowered)
        guard let match = pattern.firstMatch(in: lowered, range: range),
              let amountRange = Range(match.range(at: 1), in: lowered),
              let fromRange = Range(match.range(at: 2), in: lowered),
              let connectorRange = Range(match.range(at: 3), in: lowered),
              let toRange = Range(match.range(at: 4), in: lowered),
              let amount = Double(lowered[amountRange]) else { return nil }
        let connectors = Set(tables.flatMap { $0.unitConnectors.map(normalize) })
        guard connectors.contains(normalize(String(lowered[connectorRange]))) else { return nil }
        return Parsed(amount: amount, from: normalize(String(lowered[fromRange])), to: normalize(String(lowered[toRange])))
    }

    /// The registry/connector normalization: lowercased with diacritics folded,
    /// mirroring the date grammar's token normalization — "mètres" lands on the
    /// registered "metres", "kilómetros" on "kilometros".
    private static func normalize(_ token: String) -> String {
        token.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
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

        // Aliases are stored diacritic-folded — lookup folds the query token the
        // same way, so "mètres" lands on "metres" and "kilómetros" on
        // "kilometros". The FR/ES/DE names (issue #211) sit beside the English
        // ones: the registry is global, the *connector* is what each language's
        // table gates. German "Pfund" is deliberately absent — it means 500 g,
        // not a pound, and a wrong conversion is worse than a decline.

        // Length
        add(["mm", "millimeter", "millimeters", "millimetre", "millimetres", "milimetro", "milimetros"], UnitLength.millimeters, "length", "mm")
        add(["cm", "centimeter", "centimeters", "centimetre", "centimetres", "centimetro", "centimetros", "zentimeter"], UnitLength.centimeters, "length", "cm")
        add(["m", "meter", "meters", "metre", "metres", "metro", "metros"], UnitLength.meters, "length", "m")
        add(["km", "kilometer", "kilometers", "kilometre", "kilometres", "kilometro", "kilometros"], UnitLength.kilometers, "length", "km")
        add(["in", "inch", "inches", "\"", "pouce", "pouces", "pulgada", "pulgadas", "zoll"], UnitLength.inches, "length", "in")
        add(["ft", "foot", "feet", "'", "pied", "pieds", "pie", "pies", "fuß", "fuss"], UnitLength.feet, "length", "ft")
        add(["yd", "yard", "yards"], UnitLength.yards, "length", "yd")
        add(["mi", "mile", "miles", "milla", "millas", "meile", "meilen"], UnitLength.miles, "length", "mi")

        // Mass
        add(["mg", "milligram", "milligrams"], UnitMass.milligrams, "mass", "mg")
        add(["g", "gram", "grams", "gramme", "grammes", "gramo", "gramos", "gramm"], UnitMass.grams, "mass", "g")
        add(["kg", "kilogram", "kilograms", "kilogramme", "kilogrammes", "kilogramo", "kilogramos", "kilogramm"], UnitMass.kilograms, "mass", "kg")
        add(["oz", "ounce", "ounces", "onza", "onzas", "unze", "unzen"], UnitMass.ounces, "mass", "oz")
        add(["lb", "lbs", "pound", "pounds", "livre", "livres", "libra", "libras"], UnitMass.pounds, "mass", "lb")
        add(["st", "stone", "stones"], UnitMass.stones, "mass", "st")
        add(["t", "tonne", "tonnes", "metricton", "metrictons"], UnitMass.metricTons, "mass", "t")

        // Temperature
        add(["c", "°c", "celsius", "centigrade"], UnitTemperature.celsius, "temperature", "°C")
        add(["f", "°f", "fahrenheit"], UnitTemperature.fahrenheit, "temperature", "°F")
        add(["k", "kelvin"], UnitTemperature.kelvin, "temperature", "K")

        // Volume
        add(["ml", "milliliter", "milliliters", "millilitre", "millilitres", "mililitro", "mililitros"], UnitVolume.milliliters, "volume", "mL")
        add(["l", "liter", "liters", "litre", "litres", "litro", "litros"], UnitVolume.liters, "volume", "L")
        add(["gal", "gallon", "gallons", "galon", "galones"], UnitVolume.gallons, "volume", "gal")
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
