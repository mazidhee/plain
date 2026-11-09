import Foundation

/// Where the sun and moon really are right now, for the window and the beach. The place comes from
/// the Mac's time zone (the zone's city in /usr/share/zoneinfo/zone.tab), so no location permission
/// is needed and it's close enough for sunrise and sunset to land within a few minutes.
struct Sky: Equatable {
    /// A body in the sky: `x` 0 (morning side) to 1 (evening side), `alt` 0 (horizon) to 1 (high).
    struct Spot: Equatable { var x: Double; var alt: Double }

    var period: DayPeriod
    /// Nil when below the horizon.
    var sun: Spot?
    var moon: Spot?
    /// 0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter.
    var moonPhase: Double

    /// The fixed look each period had before the sky followed the real sun (snapshots and tests).
    static func typical(_ p: DayPeriod) -> Sky {
        switch p {
        case .dawn: return Sky(period: p, sun: Spot(x: 0.12, alt: 0.08), moon: nil, moonPhase: 0.35)
        case .golden: return Sky(period: p, sun: Spot(x: 0.85, alt: 0.12), moon: nil, moonPhase: 0.35)
        case .morning, .day: return Sky(period: p, sun: Spot(x: 0.7, alt: 0.85), moon: nil, moonPhase: 0.35)
        case .dusk, .night: return Sky(period: p, sun: nil, moon: Spot(x: 0.72, alt: 0.8), moonPhase: 0.35)
        }
    }

    static func at(_ date: Date, place: Place = .current) -> Sky {
        let s = Solar.sun(at: date, lat: place.lat, lon: place.lon)
        let phase = Solar.moonPhase(at: date)
        // The moon trails the sun by its age: full moon rises at sunset, a crescent hugs the sun.
        let moonHA = s.hourAngle - 360 * phase
        let moonElev = Solar.elevation(lat: place.lat, dec: 0, hourAngle: moonHA)
        let p = period(elevation: s.elevation, rising: s.hourAngle < 0)
        func spot(_ ha: Double, _ elev: Double) -> Spot? {
            guard elev > -1 else { return nil }
            return Spot(x: min(1, max(0, 0.5 + wrap(ha) / 180)), alt: min(1, max(0, elev / 60)))
        }
        // A thin crescent next to the sun is lost in daylight.
        let moon = s.elevation < 4 || phase > 0.2 && phase < 0.8 ? spot(moonHA, moonElev) : nil
        return Sky(period: p, sun: spot(s.hourAngle, s.elevation), moon: moon, moonPhase: phase)
    }

    /// The period from the sun's height: golden hour under 12°, twilight to 8° below the horizon.
    static func period(elevation e: Double, rising: Bool) -> DayPeriod {
        if e < -8 { return .night }
        if rising {
            if e < 3 { return .dawn }
            return e < 30 ? .morning : .day
        }
        if e < 0 { return .dusk }
        return e < 12 ? .golden : .day
    }

    /// Degrees into -180...180.
    static func wrap(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: 360)
        if x > 180 { x -= 360 }
        if x < -180 { x += 360 }
        return x
    }
}

/// A place on Earth, in degrees (north and east positive).
struct Place: Equatable {
    var lat: Double
    var lon: Double

    static let current: Place = {
        if let p = ProcessInfo.processInfo.environment["PLAIN_PLACE"].flatMap(parse(latLon:)) { return p }
        return zone(TimeZone.current.identifier) ?? Place(lat: 30, lon: Double(TimeZone.current.secondsFromGMT()) / 240)
    }()

    /// The city a time zone is named after, from the system's zone table.
    static func zone(_ id: String, table: String? = nil) -> Place? {
        guard let text = table ?? (try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8)) else { return nil }
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let cols = line.split(separator: "\t")
            if cols.count >= 3, cols[2] == id { return parse(iso6709: String(cols[1])) }
        }
        return nil
    }

    /// "+0627+00324" or "+404251-0740023" (±DDMM[SS]±DDDMM[SS]).
    static func parse(iso6709 s: String) -> Place? {
        guard let split = s.dropFirst().firstIndex(where: { $0 == "+" || $0 == "-" }) else { return nil }
        func deg(_ part: Substring, _ degDigits: Int) -> Double? {
            let sign: Double = part.first == "-" ? -1 : 1
            let d = Array(part.dropFirst())
            guard d.count >= degDigits + 2, let dd = Double(String(d[0..<degDigits])), let mm = Double(String(d[degDigits..<degDigits + 2])) else { return nil }
            let ss = d.count >= degDigits + 4 ? Double(String(d[(degDigits + 2)..<(degDigits + 4)])) ?? 0 : 0
            return sign * (dd + mm / 60 + ss / 3600)
        }
        guard let lat = deg(s[s.startIndex..<split], 2), let lon = deg(s[split...], 3) else { return nil }
        return Place(lat: lat, lon: lon)
    }

    /// "6.45,3.4" for PLAIN_PLACE.
    static func parse(latLon s: String) -> Place? {
        let parts = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return parts.count == 2 ? Place(lat: parts[0], lon: parts[1]) : nil
    }
}

/// The sun's position (the NOAA low-precision formulas, good to about a minute) and the moon's phase.
enum Solar {
    struct Sun { var elevation: Double; var hourAngle: Double; var declination: Double }

    private static let rad = Double.pi / 180

    static func julianDay(_ date: Date) -> Double { date.timeIntervalSince1970 / 86_400 + 2_440_587.5 }

    static func sun(at date: Date, lat: Double, lon: Double) -> Sun {
        let n = julianDay(date) - 2_451_545.0
        let L = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
        let g = (357.528 + 0.9856003 * n) * rad
        let lambda = (L + 1.915 * sin(g) + 0.020 * sin(2 * g)) * rad
        let eps = (23.439 - 0.0000004 * n) * rad
        let ra = atan2(cos(eps) * sin(lambda), cos(lambda)) / rad
        let dec = asin(sin(eps) * sin(lambda)) / rad
        let gmst = (18.697374558 + 24.06570982441908 * n).truncatingRemainder(dividingBy: 24)
        let ha = Sky.wrap(gmst * 15 + lon - ra)
        return Sun(elevation: elevation(lat: lat, dec: dec, hourAngle: ha), hourAngle: ha, declination: dec)
    }

    static func elevation(lat: Double, dec: Double, hourAngle: Double) -> Double {
        asin(sin(lat * rad) * sin(dec * rad) + cos(lat * rad) * cos(dec * rad) * cos(hourAngle * rad)) / rad
    }

    /// Age of the moon as a fraction of a lunation, from the new moon of 6 Jan 2000.
    static func moonPhase(at date: Date) -> Double {
        let synodic = 29.530588853
        let age = (julianDay(date) - 2_451_550.1).truncatingRemainder(dividingBy: synodic)
        return (age < 0 ? age + synodic : age) / synodic
    }

    /// Lit share of the disc, 0...1.
    static func illumination(_ phase: Double) -> Double { (1 - cos(2 * .pi * phase)) / 2 }

    /// The next sunrise or sunset after `date`, found by stepping minute by minute (for display).
    static func nextCrossing(after date: Date, place: Place = .current, rising: Bool) -> Date? {
        var t = date
        var prev = sun(at: t, lat: place.lat, lon: place.lon).elevation
        for _ in 0..<(36 * 60) {
            t = t.addingTimeInterval(60)
            let e = sun(at: t, lat: place.lat, lon: place.lon).elevation
            // -0.83° allows for refraction and the sun's radius, like published times.
            if rising ? (prev < -0.83 && e >= -0.83) : (prev > -0.83 && e <= -0.83) { return t }
            prev = e
        }
        return nil
    }
}
