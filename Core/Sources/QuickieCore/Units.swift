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

        // A length conversion *to feet* answers compound — "180 cm to ft" → "5 ft
        // 10.9 in" — because nobody thinks in decimal feet (issue #215). The
        // compound string re-parses as compound input, so the row round-trips.
        // Every other target, `to in` included, stays plain decimal. A negative
        // length is nonsensical as a height, so it declines the compound form and
        // stays plain decimal — which the standard parser round-trips.
        if to.symbol == "ft", converted.value >= 0 {
            return Conversion(value: rounded, unit: to.symbol, formatted: feetInches(converted.value))
        }

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
    /// and feet/inches, and — for the compound families (issue #214) — digits
    /// and the superscript squares/cubes ("m2", "km²"), plus the slash of a rate
    /// symbol ("km/h", "m/s"). The amount is captured first and greedily, so a
    /// leading digit run always reads as the number, not as part of the unit.
    private static let pattern = try! NSRegularExpression(
        pattern: #"^\s*(-?\d+(?:\.\d+)?)\s*([\p{L}0-9°"'µ²³/]+)\s+([\p{L}0-9°"'µ²³/]+)\s+([\p{L}0-9°"'µ²³/]+)\s*$"#,
        options: [.caseInsensitive]
    )

    /// Matches a compound imperial length written the way people say heights —
    /// `5'11"` or `5'11` (the closing double-quote optional) — followed by the
    /// connector and target: feet, `'`, inches, optional `"`, connector, target.
    /// Feet+inches only; stone+pounds and pounds+ounces were deliberately skipped
    /// (issue #215). No leading sign — a negative height is nonsensical, so a
    /// negative compound simply declines rather than parsing inconsistently.
    private static let quotePattern = try! NSRegularExpression(
        pattern: #"^\s*(\d+)\s*'\s*(\d+(?:\.\d+)?)\s*"?\s+([\p{L}°"'µ]+)\s+([\p{L}°"'µ]+)\s*$"#,
        options: [.caseInsensitive]
    )

    /// Matches the worded compound form — `5 ft 11 in to cm` — as feet-number,
    /// feet-unit, inches-number, inches-unit, connector, target. The two unit
    /// tokens are captured generically and validated against the registry (they
    /// must resolve to feet and inches), so localized spellings ("5 pieds 11
    /// pouces …") fall out for free. This is also the shape the staged `to ft`
    /// answer ("5 ft 10.9 in") takes, which is what makes the row round-trip.
    private static let wordedPattern = try! NSRegularExpression(
        pattern: #"^\s*(\d+)\s*([\p{L}'µ]+)\s+(\d+(?:\.\d+)?)\s*([\p{L}"'µ]+)\s+([\p{L}°"'µ]+)\s+([\p{L}°"'µ]+)\s*$"#,
        options: [.caseInsensitive]
    )

    private static func parse(_ query: String, tables: [DateKeywordTable]) -> Parsed? {
        let lowered = query.lowercased()
        // Compound imperial input (`5'11" to cm`, `5 ft 11 in to cm`) is a shape
        // the plain `<number> <from> <connector> <to>` pattern can't hold; it is
        // disjoint from that pattern, so trying it first changes nothing else.
        if let compound = parseCompound(lowered, tables: tables) { return compound }
        let range = NSRange(lowered.startIndex..., in: lowered)
        guard let match = pattern.firstMatch(in: lowered, range: range),
              let amountRange = Range(match.range(at: 1), in: lowered),
              let fromRange = Range(match.range(at: 2), in: lowered),
              let connectorRange = Range(match.range(at: 3), in: lowered),
              let toRange = Range(match.range(at: 4), in: lowered),
              let amount = Double(lowered[amountRange]) else { return nil }
        guard DateKeywordTable.accepts(connector: String(lowered[connectorRange]), in: tables) else { return nil }
        return Parsed(amount: amount, from: normalize(String(lowered[fromRange])), to: normalize(String(lowered[toRange])))
    }

    /// Parses a compound feet+inches source (`5'11"`, `5'11`, `5 ft 11 in`) into a
    /// `Parsed` whose amount is the total in feet and whose `from` is the
    /// registered `ft`. Returns `nil` when the text is not a compound length.
    /// The connector is validated against the active tables exactly like the
    /// plain parser (ADR 0036); the worded form's unit tokens must resolve to
    /// feet and inches in the registry.
    private static func parseCompound(_ lowered: String, tables: [DateKeywordTable]) -> Parsed? {
        let range = NSRange(lowered.startIndex..., in: lowered)

        func token(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            guard let r = Range(match.range(at: index), in: lowered) else { return nil }
            return String(lowered[r])
        }

        // Quote form: 5'11" / 5'11 — the leading `'` fixes feet, the bare number inches.
        if let match = quotePattern.firstMatch(in: lowered, range: range),
           let feetText = token(match, 1), let feet = Double(feetText),
           let inchText = token(match, 2), let inches = Double(inchText),
           let connector = token(match, 3), DateKeywordTable.accepts(connector: connector, in: tables),
           let toText = token(match, 4) {
            return Parsed(amount: feet + inches / 12, from: "ft", to: normalize(toText))
        }

        // Worded form: 5 ft 11 in — both unit words must resolve to feet and inches.
        if let match = wordedPattern.firstMatch(in: lowered, range: range),
           let feetText = token(match, 1), let feet = Double(feetText),
           let feetUnit = token(match, 2), registry[normalize(feetUnit)]?.symbol == "ft",
           let inchText = token(match, 3), let inches = Double(inchText),
           let inchUnit = token(match, 4), registry[normalize(inchUnit)]?.symbol == "in",
           let connector = token(match, 5), DateKeywordTable.accepts(connector: connector, in: tables),
           let toText = token(match, 6) {
            return Parsed(amount: feet + inches / 12, from: "ft", to: normalize(toText))
        }

        return nil
    }

    /// The unit-registry normalization: the shared fold (lowercased, diacritics
    /// folded — "mètres" lands on the registered "metres", "kilómetros" on
    /// "kilometros") plus the superscript square/cube folded to a plain digit
    /// ("m²" → "m2"), so the area registry needs only the "m2" spelling and both
    /// reach it. Connectors and base names need only the shared fold; the date
    /// grammar's fuller normalization additionally straightens apostrophes and
    /// strips trailing periods, which no unit token carries.
    private static func normalize(_ token: String) -> String {
        DateKeywordTable.folded(
            token
                .replacingOccurrences(of: "²", with: "2")
                .replacingOccurrences(of: "³", with: "3")
        )
    }

    // MARK: - Unit registry

    /// One recognised unit: the Foundation `Dimension` it maps to, the `family`
    /// that gates cross-family conversions, and the `symbol` shown in results.
    private struct UnitDef {
        let unit: Dimension
        let family: String
        let symbol: String
    }

    /// The handful of units Foundation's dimensions omit (issue #214), defined as
    /// linear converters on the *same base unit* as the family's built-ins so
    /// `Measurement` converts them alongside the standard rows. `coefficient` is
    /// the base-unit count per one of this unit: `atm` in pascals, `day`/`week`
    /// in seconds, `Wh` in joules.
    private static let atmospheres = UnitPressure(symbol: "atm", converter: UnitConverterLinear(coefficient: 101_325))
    private static let days = UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86_400))
    private static let weeks = UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604_800))
    private static let wattHours = UnitEnergy(symbol: "Wh", converter: UnitConverterLinear(coefficient: 3_600))

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

        // The six new families (issue #214) — pure registry growth, no parser
        // change beyond the compound-symbol tokens the pattern now accepts.
        // Superscript spellings ("m²") fold to their digit form ("m2") in
        // `normalize`, so each area row needs only the digit spelling.

        // Area
        add(["mm2", "sqmm"], UnitArea.squareMillimeters, "area", "mm²")
        add(["cm2", "sqcm"], UnitArea.squareCentimeters, "area", "cm²")
        add(["m2", "sqm", "squaremeter", "squaremeters", "squaremetre", "squaremetres"], UnitArea.squareMeters, "area", "m²")
        add(["km2", "sqkm", "squarekilometer", "squarekilometers"], UnitArea.squareKilometers, "area", "km²")
        add(["in2", "sqin", "squareinch", "squareinches"], UnitArea.squareInches, "area", "in²")
        add(["ft2", "sqft", "squarefoot", "squarefeet"], UnitArea.squareFeet, "area", "ft²")
        add(["yd2", "sqyd", "squareyard", "squareyards"], UnitArea.squareYards, "area", "yd²")
        add(["mi2", "sqmi", "squaremile", "squaremiles"], UnitArea.squareMiles, "area", "mi²")
        add(["acre", "acres"], UnitArea.acres, "area", "acre")
        add(["ha", "hectare", "hectares"], UnitArea.hectares, "area", "ha")

        // Speed
        add(["m/s", "mps", "meterspersecond"], UnitSpeed.metersPerSecond, "speed", "m/s")
        add(["km/h", "kmh", "kph", "kilometersperhour"], UnitSpeed.kilometersPerHour, "speed", "km/h")
        add(["mph", "mi/h", "milesperhour"], UnitSpeed.milesPerHour, "speed", "mph")
        add(["kn", "kt", "kts", "knot", "knots"], UnitSpeed.knots, "speed", "kn")

        // Data storage — decimal by default (1 GB = 1000 MB); binary reachable
        // only by the explicit -ib spelling (1 GiB = 1024 MiB). Both spellings
        // coexist as distinct rows with distinct symbols.
        add(["b", "byte", "bytes"], UnitInformationStorage.bytes, "information", "B")
        add(["bit", "bits"], UnitInformationStorage.bits, "information", "bit")
        add(["kb", "kilobyte", "kilobytes"], UnitInformationStorage.kilobytes, "information", "KB")
        add(["mb", "megabyte", "megabytes"], UnitInformationStorage.megabytes, "information", "MB")
        add(["gb", "gigabyte", "gigabytes"], UnitInformationStorage.gigabytes, "information", "GB")
        add(["tb", "terabyte", "terabytes"], UnitInformationStorage.terabytes, "information", "TB")
        add(["kib", "kibibyte", "kibibytes"], UnitInformationStorage.kibibytes, "information", "KiB")
        add(["mib", "mebibyte", "mebibytes"], UnitInformationStorage.mebibytes, "information", "MiB")
        add(["gib", "gibibyte", "gibibytes"], UnitInformationStorage.gibibytes, "information", "GiB")
        add(["tib", "tebibyte", "tebibytes"], UnitInformationStorage.tebibytes, "information", "TiB")

        // Energy — Wh is a custom unit (Foundation's UnitEnergy omits it).
        add(["j", "joule", "joules"], UnitEnergy.joules, "energy", "J")
        add(["kj", "kilojoule", "kilojoules"], UnitEnergy.kilojoules, "energy", "kJ")
        add(["cal", "calorie", "calories"], UnitEnergy.calories, "energy", "cal")
        add(["kcal", "kilocalorie", "kilocalories"], UnitEnergy.kilocalories, "energy", "kcal")
        add(["wh", "watthour", "watthours"], wattHours, "energy", "Wh")
        add(["kwh", "kilowatthour", "kilowatthours"], UnitEnergy.kilowattHours, "energy", "kWh")

        // Pressure — atm is a custom unit (Foundation's UnitPressure omits it).
        add(["pa", "pascal", "pascals"], UnitPressure.newtonsPerMetersSquared, "pressure", "Pa")
        add(["hpa", "hectopascal", "hectopascals"], UnitPressure.hectopascals, "pressure", "hPa")
        add(["kpa", "kilopascal", "kilopascals"], UnitPressure.kilopascals, "pressure", "kPa")
        add(["bar", "bars"], UnitPressure.bars, "pressure", "bar")
        add(["mbar", "millibar", "millibars"], UnitPressure.millibars, "pressure", "mbar")
        add(["psi"], UnitPressure.poundsForcePerSquareInch, "pressure", "psi")
        add(["atm", "atmosphere", "atmospheres"], atmospheres, "pressure", "atm")
        add(["mmhg"], UnitPressure.millimetersOfMercury, "pressure", "mmHg")
        add(["inhg"], UnitPressure.inchesOfMercury, "pressure", "inHg")

        // Duration — a magnitude conversion (deliberately Units, not Date & time).
        // Days and weeks are custom units (Foundation's UnitDuration omits them).
        // Minutes take "min" — never "m", which is metres.
        add(["s", "sec", "secs", "second", "seconds"], UnitDuration.seconds, "duration", "s")
        add(["min", "mins", "minute", "minutes"], UnitDuration.minutes, "duration", "min")
        add(["h", "hr", "hrs", "hour", "hours"], UnitDuration.hours, "duration", "h")
        add(["d", "day", "days"], days, "duration", "d")
        add(["wk", "wks", "week", "weeks"], weeks, "duration", "wk")

        return map
    }()

    // MARK: - Formatting

    /// Rounds a converted value to four fractional digits — enough precision for
    /// everyday conversions without a wall of float noise. Display formatting is
    /// shared with the Calculator via `NumberFormat`.
    private static func round(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }

    /// Renders a non-negative decimal-feet value as compound "`<feet> ft <inches>
    /// in`", inches to one decimal (issue #215). Inches rounded to a full 12 carry
    /// into the feet, so 5.9999 ft reads "6 ft 0 in", never "5 ft 12 in". Whole
    /// feet keep the "`… 0 in`" tail so the string still re-parses as compound
    /// input. The caller only reaches here for a non-negative value.
    private static func feetInches(_ feet: Double) -> String {
        var wholeFeet = feet.rounded(.down)
        var inches = ((feet - wholeFeet) * 12 * 10).rounded() / 10
        if inches >= 12 {
            inches -= 12
            wholeFeet += 1
        }
        let feetText = NumberFormat.string(wholeFeet, maxFractionDigits: 0)
        let inchesText = NumberFormat.string(inches, maxFractionDigits: 1)
        return "\(feetText) ft \(inchesText) in"
    }
}
