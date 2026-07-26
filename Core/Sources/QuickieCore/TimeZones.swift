import Foundation

/// The offline time-zone registry behind the Date & time **timezone conversion**
/// family (issue #212; CONTEXT.md → Date & time) — the "PST" and "tokyo" of
/// "9am PST in tokyo". The same alias-table shape as the unit registry
/// (`Units`): every accepted spelling keyed, lowercased and diacritic-folded,
/// to a **system time-zone identifier** — the registry only names zones; the
/// system supplies the offset math, DST included.
///
/// One registry serves every language (city names are not per-language table
/// entries — a city is a place, not a keyword), so the multilingual spellings
/// ("tokio", "londres", "nueva york") sit beside the English ones, exactly as
/// the unit registry holds "pieds" beside "feet". Only the *connector* word
/// ("in"/"à"/"en") is per-language table data (ADR 0036).
///
/// An abbreviation names its **region's zone, not a fixed offset**: "9am PST"
/// in July means 9am Los Angeles time — PDT — because that is what people mean;
/// a literal UTC−8 answer in summer would be an hour of silent wrongness.
public enum TimeZones {

    /// Resolves an accepted city name or zone abbreviation to its system time
    /// zone, or `nil` when the name is not registered — how the grammar
    /// declines a non-zone word. Lookup folds case and diacritics ("Zürich",
    /// "SÃO PAULO"), matching the registry's stored spellings.
    public static func timeZone(for name: String) -> TimeZone? {
        registry[normalize(name)].flatMap(TimeZone.init(identifier:))
    }

    /// The registry/lookup normalization — lowercased with diacritics folded,
    /// the same fold the unit registry applies, so "Zürich" lands on "zurich"
    /// and "São Paulo" on "sao paulo".
    private static func normalize(_ name: String) -> String {
        name.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
    }

    /// Every accepted spelling, keyed (pre-folded) to its system time-zone
    /// identifier. New cities and abbreviations are added here, not in the
    /// parser. Internal so the suite can assert every identifier resolves on
    /// the platform under test.
    static let registry: [String: String] = {
        var map: [String: String] = [:]

        func add(_ aliases: [String], _ identifier: String) {
            for alias in aliases { map[alias] = identifier }
        }

        // Zone abbreviations — each mapped to a representative region so the
        // system's own DST rules answer ("pst" and "pdt" are both Los Angeles).
        add(["utc"], "UTC")
        add(["gmt"], "GMT")
        add(["pt", "pst", "pdt"], "America/Los_Angeles")
        add(["mt", "mst", "mdt"], "America/Denver")
        add(["ct", "cst", "cdt"], "America/Chicago")
        add(["et", "est", "edt"], "America/New_York")
        add(["akst", "akdt"], "America/Anchorage")
        add(["hst"], "Pacific/Honolulu")
        add(["ast", "adt"], "America/Halifax")
        add(["bst"], "Europe/London")
        add(["wet", "west"], "Europe/Lisbon")
        add(["cet", "cest"], "Europe/Paris")
        add(["eet", "eest"], "Europe/Athens")
        add(["msk"], "Europe/Moscow")
        add(["gst"], "Asia/Dubai")
        add(["ist"], "Asia/Kolkata")
        add(["pkt"], "Asia/Karachi")
        add(["ict"], "Asia/Bangkok")
        add(["wib"], "Asia/Jakarta")
        add(["sgt"], "Asia/Singapore")
        add(["hkt"], "Asia/Hong_Kong")
        add(["kst"], "Asia/Seoul")
        add(["jst"], "Asia/Tokyo")
        add(["awst"], "Australia/Perth")
        add(["acst", "acdt"], "Australia/Adelaide")
        add(["aest", "aedt"], "Australia/Sydney")
        add(["nzst", "nzdt"], "Pacific/Auckland")
        add(["brt"], "America/Sao_Paulo")
        add(["wat"], "Africa/Lagos")
        add(["eat"], "Africa/Nairobi")
        add(["sast"], "Africa/Johannesburg")

        // North America
        add(["los angeles", "la", "san francisco", "sf", "seattle", "san diego", "portland", "las vegas"], "America/Los_Angeles")
        add(["denver", "salt lake city"], "America/Denver")
        add(["phoenix"], "America/Phoenix")
        add(["chicago", "houston", "dallas", "austin", "minneapolis"], "America/Chicago")
        add(["new york", "new york city", "nyc", "nueva york", "boston", "miami", "atlanta", "philadelphia", "detroit", "washington", "washington dc", "dc"], "America/New_York")
        add(["toronto", "montreal", "ottawa"], "America/Toronto")
        add(["vancouver"], "America/Vancouver")
        add(["calgary", "edmonton"], "America/Edmonton")
        add(["halifax"], "America/Halifax")
        add(["anchorage"], "America/Anchorage")
        add(["honolulu", "hawaii"], "Pacific/Honolulu")
        add(["mexico city", "ciudad de mexico", "cdmx"], "America/Mexico_City")

        // South America
        add(["sao paulo", "rio", "rio de janeiro", "brasilia"], "America/Sao_Paulo")
        add(["buenos aires"], "America/Argentina/Buenos_Aires")
        add(["santiago"], "America/Santiago")
        add(["lima"], "America/Lima")
        add(["bogota"], "America/Bogota")
        add(["caracas"], "America/Caracas")

        // Europe
        add(["london", "londres"], "Europe/London")
        add(["dublin"], "Europe/Dublin")
        add(["lisbon", "lisboa", "lissabon", "lisbonne"], "Europe/Lisbon")
        add(["paris"], "Europe/Paris")
        add(["berlin", "munich", "munchen", "frankfurt", "hamburg", "cologne", "koln"], "Europe/Berlin")
        add(["madrid", "barcelona"], "Europe/Madrid")
        add(["rome", "roma", "rom", "milan", "milano", "mailand"], "Europe/Rome")
        add(["amsterdam"], "Europe/Amsterdam")
        add(["brussels", "bruxelles", "brussel"], "Europe/Brussels")
        add(["zurich", "geneva", "geneve", "genf", "ginebra"], "Europe/Zurich")
        add(["vienna", "wien", "vienne", "viena"], "Europe/Vienna")
        add(["stockholm"], "Europe/Stockholm")
        add(["oslo"], "Europe/Oslo")
        add(["copenhagen", "kopenhagen", "copenhague"], "Europe/Copenhagen")
        add(["helsinki"], "Europe/Helsinki")
        add(["warsaw", "warschau", "varsovie", "varsovia", "warszawa"], "Europe/Warsaw")
        add(["prague", "praga", "prag", "praha"], "Europe/Prague")
        add(["budapest"], "Europe/Budapest")
        add(["athens", "athenes", "atenas", "athen"], "Europe/Athens")
        add(["bucharest"], "Europe/Bucharest")
        // "Europe/Kiev" is the permanent backward link — it resolves on older
        // ICU/tzdata where the renamed "Europe/Kyiv" may not; same zone.
        add(["kyiv", "kiev"], "Europe/Kiev")
        add(["moscow", "moscou", "moskau", "moscu", "moskva"], "Europe/Moscow")
        add(["istanbul", "estambul"], "Europe/Istanbul")

        // Middle East & Africa
        add(["dubai", "abu dhabi"], "Asia/Dubai")
        add(["riyadh"], "Asia/Riyadh")
        add(["doha"], "Asia/Qatar")
        add(["tel aviv", "jerusalem"], "Asia/Jerusalem")
        add(["cairo", "le caire", "el cairo", "kairo"], "Africa/Cairo")
        add(["johannesburg", "cape town"], "Africa/Johannesburg")
        add(["lagos"], "Africa/Lagos")
        add(["nairobi"], "Africa/Nairobi")
        add(["casablanca"], "Africa/Casablanca")

        // Asia
        add(["mumbai", "bombay", "delhi", "new delhi", "bangalore", "bengaluru", "kolkata", "calcutta", "chennai", "hyderabad"], "Asia/Kolkata")
        add(["karachi"], "Asia/Karachi")
        add(["dhaka"], "Asia/Dhaka")
        add(["colombo"], "Asia/Colombo")
        add(["kathmandu"], "Asia/Kathmandu")
        add(["bangkok"], "Asia/Bangkok")
        add(["hanoi", "ho chi minh", "saigon"], "Asia/Ho_Chi_Minh")
        add(["jakarta"], "Asia/Jakarta")
        add(["singapore", "singapour", "singapur"], "Asia/Singapore")
        add(["kuala lumpur"], "Asia/Kuala_Lumpur")
        add(["manila"], "Asia/Manila")
        add(["hong kong", "hongkong"], "Asia/Hong_Kong")
        add(["taipei"], "Asia/Taipei")
        add(["shanghai", "beijing", "pekin", "peking"], "Asia/Shanghai")
        add(["seoul", "seul"], "Asia/Seoul")
        add(["tokyo", "tokio", "osaka", "kyoto"], "Asia/Tokyo")

        // Oceania
        add(["sydney"], "Australia/Sydney")
        add(["melbourne"], "Australia/Melbourne")
        add(["brisbane"], "Australia/Brisbane")
        add(["adelaide"], "Australia/Adelaide")
        add(["perth"], "Australia/Perth")
        add(["auckland", "wellington"], "Pacific/Auckland")

        return map
    }()
}
