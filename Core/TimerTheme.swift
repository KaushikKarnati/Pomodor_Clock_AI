import Foundation

/// Selectable timer objects. Raw values are persisted in settings; never rename them.
enum TimerObjectID: String, Codable, CaseIterable, Identifiable, Sendable {
    case tomato, apple, lemon, egg, hourglass, alarmClock
    var id: String { rawValue }
}

enum SoundRole: String, CaseIterable, Sendable { case wind, tick, alarm }

/// A selectable sound. `files` are bundle resource names without the `.wav` extension:
/// winding and alarm sounds use one file, ticking uses an odd/even pair, and None uses none.
struct SoundOption: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let files: [String]
}

enum SoundCatalog {
    static let classic = "classic"
    static let none = "none"

    static let wind: [SoundOption] = [
        .init(id: "classic", name: "Classic ratchet", files: ["ratchet"]),
        .init(id: "felt", name: "Felt", files: ["wind-felt"]),
        .init(id: "wooden", name: "Wooden", files: ["wind-wooden"]),
        .init(id: "chrome", name: "Chrome spring", files: ["wind-chrome"]),
        .init(id: "sand", name: "Sand pour", files: ["wind-sand"]),
        .init(id: "mainspring", name: "Mainspring", files: ["wind-mainspring"]),
        .init(id: "brass", name: "Brass", files: ["wind-brass"]),
        .init(id: "deep", name: "Deep wood", files: ["wind-deep"]),
    ]
    static let tick: [SoundOption] = [
        .init(id: "none", name: "None", files: []),
        .init(id: "classic", name: "Classic", files: ["tickOdd", "tickEven"]),
        .init(id: "felt", name: "Felt", files: ["tick-felt-odd", "tick-felt-even"]),
        .init(id: "woodblock", name: "Woodblock", files: ["tick-woodblock-odd", "tick-woodblock-even"]),
        .init(id: "chrome", name: "Chrome egg", files: ["tick-chrome-odd", "tick-chrome-even"]),
        .init(id: "sand", name: "Sand patter", files: ["tick-sand-odd", "tick-sand-even"]),
        .init(id: "twinBell", name: "Twin-bell clock", files: ["tick-twinBell-odd", "tick-twinBell-even"]),
        .init(id: "grandfather", name: "Grandfather", files: ["tick-grandfather-odd", "tick-grandfather-even"]),
        .init(id: "brass", name: "Brass", files: ["tick-brass-odd", "tick-brass-even"]),
    ]
    static let alarm: [SoundOption] = [
        .init(id: "classic", name: "Classic bell", files: ["bell"]),
        .init(id: "marimba", name: "Marimba", files: ["alarm-marimba"]),
        .init(id: "templeBlocks", name: "Temple blocks", files: ["alarm-templeBlocks"]),
        .init(id: "eggBell", name: "Egg timer bell", files: ["alarm-eggBell"]),
        .init(id: "glassChime", name: "Glass chime", files: ["alarm-glassChime"]),
        .init(id: "twinBells", name: "Twin bells", files: ["alarm-twinBells"]),
        .init(id: "gong", name: "Gong", files: ["alarm-gong"]),
        .init(id: "handbell", name: "Handbell", files: ["alarm-handbell"]),
        .init(id: "bowl", name: "Singing bowl", files: ["alarm-bowl"]),
    ]

    static func options(for role: SoundRole) -> [SoundOption] {
        switch role {
        case .wind: wind
        case .tick: tick
        case .alarm: alarm
        }
    }

    /// Unknown or removed ids fall back to Classic so old or damaged settings never fail to load.
    static func option(_ id: String, for role: SoundRole) -> SoundOption {
        let options = options(for: role)
        return options.first { $0.id == id } ?? options.first { $0.id == classic }!
    }

    static func isKnown(_ id: String, for role: SoundRole) -> Bool {
        options(for: role).contains { $0.id == id }
    }

    static var allFiles: Set<String> { Set(SoundRole.allCases.flatMap { options(for: $0).flatMap(\.files) }) }
}

/// The resolved files the audio player loads for the current settings.
struct SoundSelection: Equatable, Sendable {
    var wind: String
    var tickOdd: String?
    var tickEven: String?
    var alarm: String
}

/// Where the rotating minute band sits on a twist timer, in the artwork's 680-unit frame.
/// Measured from each artwork's seam; see Tools/objects/README.md.
struct BandGeometry: Equatable, Sendable {
    var cx: Double, cy: Double, rx: Double, ry: Double
    /// Tick and numeral size relative to the tomato.
    var scale: Double
    /// Dark markings for light objects (lemon, chrome) where white would not be legible.
    var darkInk: Bool
}

/// A 60-minute dial printed on a clock face, in the artwork's 680-unit frame.
struct FaceGeometry: Equatable, Sendable {
    var cx: Double, cy: Double, radius: Double
}

enum TimerObjectStyle: Equatable, Sendable {
    case twist(BandGeometry)
    case hourglass
    case clockFace(FaceGeometry)
}

struct GlowColor: Equatable, Sendable {
    var red: Double, green: Double, blue: Double
}

struct TimerObjectInfo: Identifiable, Equatable, Sendable {
    let id: TimerObjectID
    let name: String
    /// Main asset name. The hourglass is drawn from layered `hourglass-*` assets instead.
    let artwork: String
    /// Small asset in the widget extension's catalog, shown in the Live Activity.
    let mini: String
    let style: TimerObjectStyle
    let focusGlow: GlowColor
    let breakGlow: GlowColor
    let windSound: String
    let tickSound: String
    let alarmSound: String

    static let tomatoBand = BandGeometry(cx: 341.5, cy: 361.8, rx: 282, ry: 83.1, scale: 1, darkInk: false)
    static let hourglassLayers = ["hourglass-base", "hourglass-sand-top", "hourglass-pile", "hourglass-stream", "hourglass-bottom-mask"]

    private static let focusRed = GlowColor(red: 1, green: 72 / 255, blue: 50 / 255)
    private static let breakGreen = GlowColor(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
    private static let breakTeal = GlowColor(red: 64 / 255, green: 200 / 255, blue: 224 / 255)

    static let all: [TimerObjectInfo] = [
        .init(id: .tomato, name: "Tomato", artwork: "tomato", mini: "mini-tomato", style: .twist(tomatoBand),
              focusGlow: focusRed, breakGlow: breakGreen, windSound: "classic", tickSound: "classic", alarmSound: "classic"),
        .init(id: .apple, name: "Apple", artwork: "object-apple", mini: "mini-apple",
              style: .twist(BandGeometry(cx: 338, cy: 408.7, rx: 269.3, ry: 45.2, scale: 0.955, darkInk: false)),
              focusGlow: GlowColor(red: 120 / 255, green: 200 / 255, blue: 60 / 255), breakGlow: breakTeal,
              windSound: "wooden", tickSound: "woodblock", alarmSound: "templeBlocks"),
        .init(id: .lemon, name: "Lemon", artwork: "object-lemon", mini: "mini-lemon",
              style: .twist(BandGeometry(cx: 339.5, cy: 407.4, rx: 206.9, ry: 23.9, scale: 0.734, darkInk: true)),
              focusGlow: GlowColor(red: 1, green: 214 / 255, blue: 10 / 255), breakGlow: breakGreen,
              windSound: "felt", tickSound: "felt", alarmSound: "marimba"),
        .init(id: .egg, name: "Chrome egg", artwork: "object-egg", mini: "mini-egg",
              style: .twist(BandGeometry(cx: 339.5, cy: 389.9, rx: 217.2, ry: 36.2, scale: 0.77, darkInk: true)),
              focusGlow: GlowColor(red: 200 / 255, green: 210 / 255, blue: 225 / 255), breakGlow: breakGreen,
              windSound: "chrome", tickSound: "chrome", alarmSound: "eggBell"),
        .init(id: .hourglass, name: "Hourglass", artwork: "hourglass-base", mini: "mini-hourglass", style: .hourglass,
              focusGlow: GlowColor(red: 1, green: 176 / 255, blue: 90 / 255), breakGlow: breakGreen,
              windSound: "sand", tickSound: "sand", alarmSound: "glassChime"),
        .init(id: .alarmClock, name: "Alarm clock", artwork: "object-alarmClock", mini: "mini-alarmClock",
              style: .clockFace(FaceGeometry(cx: 337.5, cy: 401, radius: 176)),
              focusGlow: focusRed, breakGlow: breakGreen,
              windSound: "mainspring", tickSound: "twinBell", alarmSound: "twinBells"),
    ]

    static func info(_ id: TimerObjectID) -> TimerObjectInfo {
        all.first { $0.id == id }!
    }
}

extension FocusSettings {
    var timerObject: TimerObjectInfo { TimerObjectInfo.info(object) }

    /// The tick option shown in the picker: None when ticking is switched off.
    var effectiveTickSound: String { tick ? tickSound : SoundCatalog.none }

    func soundID(for role: SoundRole) -> String {
        switch role {
        case .wind: windSound
        case .tick: effectiveTickSound
        case .alarm: alarmSound
        }
    }

    var soundSelection: SoundSelection {
        let tickFiles = SoundCatalog.option(effectiveTickSound, for: .tick).files
        return SoundSelection(wind: SoundCatalog.option(windSound, for: .wind).files[0],
                              tickOdd: tickFiles.first, tickEven: tickFiles.last,
                              alarm: SoundCatalog.option(alarmSound, for: .alarm).files[0])
    }

    /// Choosing a sound for one role. Choosing None for ticking keeps the last tick sound for later.
    mutating func setSound(_ id: String, for role: SoundRole) {
        guard SoundCatalog.isKnown(id, for: role) else { return }
        switch role {
        case .wind: windSound = id
        case .alarm: alarmSound = id
        case .tick:
            if id == SoundCatalog.none { tick = false } else { tick = true; tickSound = id }
        }
    }

    /// Choosing an object also picks its matching sounds; each can still be changed afterwards.
    /// Ticking stays off if the person turned it off.
    mutating func selectObject(_ id: TimerObjectID) {
        let info = TimerObjectInfo.info(id)
        object = id
        windSound = info.windSound
        tickSound = info.tickSound
        alarmSound = info.alarmSound
    }
}
