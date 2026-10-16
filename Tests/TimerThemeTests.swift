import XCTest
@testable import FocusCore

final class TimerThemeTests: XCTestCase {
    private let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    func testLegacySettingsDecodeToTomatoAndClassicSounds() throws {
        let data = Data(#"{"voice":false,"tick":false,"haptics":true,"auto":true}"#.utf8)
        let settings = try JSONDecoder().decode(FocusSettings.self, from: data)
        XCTAssertEqual(settings.object, .tomato)
        XCTAssertEqual(settings.windSound, "classic")
        XCTAssertEqual(settings.alarmSound, "classic")
        XCTAssertEqual(settings.effectiveTickSound, "none")
        XCTAssertNil(settings.soundSelection.tickOdd)
        XCTAssertEqual(settings.soundSelection.alarm, "bell")
    }

    func testUnknownOrMistypedAppearanceValuesNeverFailTheLoad() throws {
        let data = Data(#"{"object":"rocket","windSound":42,"tickSound":"gone","alarmSound":"none"}"#.utf8)
        let settings = try JSONDecoder().decode(FocusSettings.self, from: data)
        XCTAssertEqual(settings.object, .tomato)
        XCTAssertEqual(settings.windSound, "classic")
        XCTAssertEqual(settings.tickSound, "classic")
        XCTAssertEqual(settings.alarmSound, "classic")
        XCTAssertTrue(settings.tick)
    }

    func testStoredNoneTickTurnsTickingOff() throws {
        let data = Data(#"{"tickSound":"none"}"#.utf8)
        let settings = try JSONDecoder().decode(FocusSettings.self, from: data)
        XCTAssertFalse(settings.tick)
        XCTAssertEqual(settings.effectiveTickSound, "none")
    }

    func testAppearanceRoundTrips() throws {
        var settings = FocusSettings()
        settings.selectObject(.hourglass)
        settings.setSound("gong", for: .alarm)
        settings.setSound("none", for: .tick)
        let decoded = try JSONDecoder().decode(FocusSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.object, .hourglass)
        XCTAssertEqual(decoded.windSound, "sand")
        XCTAssertEqual(decoded.alarmSound, "gong")
        XCTAssertFalse(decoded.tick)
        XCTAssertEqual(decoded.tickSound, "sand", "None keeps the last tick sound for when ticking returns")
    }

    func testSelectingObjectAppliesMatchingSoundsButKeepsTickingOff() {
        var settings = FocusSettings(tick: false)
        settings.selectObject(.egg)
        XCTAssertEqual(settings.windSound, "chrome")
        XCTAssertEqual(settings.alarmSound, "eggBell")
        XCTAssertFalse(settings.tick)
        settings.setSound("woodblock", for: .tick)
        XCTAssertTrue(settings.tick)
        XCTAssertEqual(settings.soundSelection, SoundSelection(wind: "wind-chrome", tickOdd: "tick-woodblock-odd", tickEven: "tick-woodblock-even", alarm: "alarm-eggBell"))
    }

    func testUnknownSoundSelectionIsIgnored() {
        var settings = FocusSettings()
        settings.setSound("kazoo", for: .alarm)
        settings.setSound("none", for: .wind)
        XCTAssertEqual(settings.alarmSound, "classic")
        XCTAssertEqual(settings.windSound, "classic")
    }

    func testCatalogIdsAreUniqueAndObjectDefaultsExist() {
        for role in SoundRole.allCases {
            let ids = SoundCatalog.options(for: role).map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "\(role)")
            XCTAssertTrue(ids.contains("classic"), "\(role)")
        }
        XCTAssertEqual(TimerObjectInfo.all.map(\.id), TimerObjectID.allCases)
        for info in TimerObjectInfo.all {
            XCTAssertTrue(SoundCatalog.isKnown(info.windSound, for: .wind), info.name)
            XCTAssertTrue(SoundCatalog.isKnown(info.tickSound, for: .tick), info.name)
            XCTAssertTrue(SoundCatalog.isKnown(info.alarmSound, for: .alarm), info.name)
            XCTAssertNotEqual(info.tickSound, "none", info.name)
        }
        for option in SoundCatalog.tick where option.id != "none" { XCTAssertEqual(option.files.count, 2, option.id) }
        for option in SoundCatalog.wind + SoundCatalog.alarm { XCTAssertEqual(option.files.count, 1, option.id) }
    }

    func testEverySoundFileIsBundledAsValidNotificationAudio() throws {
        for name in SoundCatalog.allFiles {
            let candidates = [repo.appendingPathComponent("Resources/\(name).wav"), repo.appendingPathComponent("Resources/Sounds/\(name).wav")]
            let url = try XCTUnwrap(candidates.first { FileManager.default.fileExists(atPath: $0.path) }, "missing \(name).wav")
            let data = try Data(contentsOf: url)
            XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF", name)
            XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE", name)
            // 48 kHz mono 16-bit PCM: bytes 44+ are samples; notification sounds must be under 30 s.
            let seconds = Double(data.count - 44) / (48_000 * 2)
            XCTAssertLessThan(seconds, 30, name)
        }
    }

    func testEveryAlarmIsRegisteredInTheXcodeProject() throws {
        let project = try String(contentsOf: repo.appendingPathComponent("FocusTalk.xcodeproj/project.pbxproj"), encoding: .utf8)
        for name in SoundCatalog.allFiles {
            XCTAssertTrue(project.contains("\(name).wav in Resources"), "\(name).wav is not in the app's Resources phase")
        }
        XCTAssertTrue(project.contains("Core/TimerTheme.swift in Sources"))
        XCTAssertTrue(project.contains("Widget/Assets.xcassets in Resources"))
    }

    func testEveryArtworkAndMiniExistsInItsAssetCatalog() {
        let app = repo.appendingPathComponent("Resources/Assets.xcassets")
        let widget = repo.appendingPathComponent("Widget/Assets.xcassets")
        var names = TimerObjectInfo.all.map(\.artwork) + TimerObjectInfo.hourglassLayers
        names = Array(Set(names))
        for name in names {
            XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("\(name).imageset/Contents.json").path), name)
        }
        for info in TimerObjectInfo.all {
            XCTAssertTrue(FileManager.default.fileExists(atPath: widget.appendingPathComponent("\(info.mini).imageset/Contents.json").path), info.mini)
            // Settings picker thumbnails live in the app catalog (the widget catalog is not in the app).
            XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("thumb-\(info.id.rawValue).imageset/Contents.json").path), info.name)
        }
    }

    /// ActivityKit may refuse to start an activity whose images are larger than the presentation they
    /// appear in: 80 pt minis for the Lock Screen card, 24 pt for the Dynamic Island's compact/minimal.
    func testLiveActivityMinisStayWithinTheirPresentationSize() throws {
        let widget = repo.appendingPathComponent("Widget/Assets.xcassets")
        for info in TimerObjectInfo.all {
            for (asset, points) in [(info.mini, 80), (info.mini + "-small", 24)] {
                for scale in [2, 3] {
                    let png = try Data(contentsOf: widget.appendingPathComponent("\(asset).imageset/\(asset)@\(scale)x.png"))
                    // IHDR: width and height are big-endian UInt32s at bytes 16 and 20.
                    let size = [16, 20].map { offset in png[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) } }
                    XCTAssertEqual(size, [points * scale, points * scale], "\(asset)@\(scale)x")
                }
            }
        }
    }

    func testDialGeometryStaysInsideTheArtworkFrame() {
        for info in TimerObjectInfo.all {
            switch info.style {
            case .twist(let band):
                XCTAssertGreaterThan(band.cx - band.rx, 0, info.name)
                XCTAssertLessThan(band.cx + band.rx, 680, info.name)
                XCTAssertGreaterThan(band.cy - 60 * band.scale, 0, info.name)
                XCTAssertLessThan(band.cy + band.ry, 680, info.name)
                XCTAssertGreaterThan(band.ry, 0, info.name)
            case .clockFace(let face):
                XCTAssertGreaterThan(face.cx - face.radius, 0, info.name)
                XCTAssertLessThan(face.cy + face.radius, 680, info.name)
            case .hourglass:
                break
            }
        }
    }

    func testLegacyPlanWithBudgetBelowTotalIsRepairedOnlyWithinEightHours() throws {
        let legacy = FocusPlan(blocks: [.init(title: "Focus", minutes: 30)], budgetMinutes: 25)
        XCTAssertThrowsError(try legacy.validated())
        XCTAssertEqual(try legacy.repairingBudget().validated().budgetMinutes, 30)
        let tooLong = FocusPlan(blocks: (0..<5).map { .init(title: "B\($0)", minutes: 100) }, budgetMinutes: 480)
        XCTAssertThrowsError(try tooLong.repairingBudget().validated())
    }
}
