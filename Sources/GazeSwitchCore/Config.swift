import Foundation

public enum ScrollMode: String, Codable, CaseIterable {
    case hands, eyes, both, off

    public var usesHands: Bool { self == .hands || self == .both }
    public var usesEyes: Bool { self == .eyes || self == .both }
}

/// Settings read from config.json. Missing keys fall back to the defaults below.
public struct Config: Codable, Equatable {
    /// Part of a camera's name, such as "FaceTime". Nil picks the built-in camera.
    public var camera: String?
    public var hotkey = "ctrl+option+cmd+g"
    /// Hold an open palm up to the camera to turn gaze-switch on or off.
    public var gestureToggle = true
    public var scrollMode = ScrollMode.hands
    public var startEnabled = true
    public var sounds = true
    public var showGaze = false
    /// How long you must look at a window before it activates.
    public var dwellMs = 350.0
    /// How far past a screen's edge a look still counts, as a share of the screen's size.
    public var awayMargin = 0.2
    public var handScrollSpeed = 1.0
    public var invertHandScroll = false
    public var eyeScrollSpeed = 1.0
    /// The height of the edge bands that trigger eye scrolling, as a share of the window's height.
    public var eyeScrollEdge = 0.18
    public var eyeScrollDwellMs = 600.0

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        camera = try c.decodeIfPresent(String.self, forKey: .camera) ?? d.camera
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? d.hotkey
        gestureToggle = try c.decodeIfPresent(Bool.self, forKey: .gestureToggle) ?? d.gestureToggle
        scrollMode = try c.decodeIfPresent(ScrollMode.self, forKey: .scrollMode) ?? d.scrollMode
        startEnabled = try c.decodeIfPresent(Bool.self, forKey: .startEnabled) ?? d.startEnabled
        sounds = try c.decodeIfPresent(Bool.self, forKey: .sounds) ?? d.sounds
        showGaze = try c.decodeIfPresent(Bool.self, forKey: .showGaze) ?? d.showGaze
        dwellMs = try c.decodeIfPresent(Double.self, forKey: .dwellMs) ?? d.dwellMs
        awayMargin = try c.decodeIfPresent(Double.self, forKey: .awayMargin) ?? d.awayMargin
        handScrollSpeed = try c.decodeIfPresent(Double.self, forKey: .handScrollSpeed) ?? d.handScrollSpeed
        invertHandScroll = try c.decodeIfPresent(Bool.self, forKey: .invertHandScroll) ?? d.invertHandScroll
        eyeScrollSpeed = try c.decodeIfPresent(Double.self, forKey: .eyeScrollSpeed) ?? d.eyeScrollSpeed
        eyeScrollEdge = try c.decodeIfPresent(Double.self, forKey: .eyeScrollEdge) ?? d.eyeScrollEdge
        eyeScrollDwellMs = try c.decodeIfPresent(Double.self, forKey: .eyeScrollDwellMs) ?? d.eyeScrollDwellMs
    }
}

/// Settings and calibration live in ~/Library/Application Support/gaze-switch.
public enum Storage {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/gaze-switch", isDirectory: true)
    }

    public static var configURL: URL { directory.appendingPathComponent("config.json") }
    public static var calibrationURL: URL { directory.appendingPathComponent("calibration.json") }

    /// Writes a config file with the defaults the first time, so there is something to edit.
    public static func loadConfig() throws -> Config {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            let config = Config()
            try save(config, to: configURL)
            return config
        }
        return try JSONDecoder().decode(Config.self, from: Data(contentsOf: configURL))
    }

    public static func saveConfig(_ config: Config) throws {
        try save(config, to: configURL)
    }

    public static func loadCalibration() throws -> GazeModel? {
        guard FileManager.default.fileExists(atPath: calibrationURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GazeModel.self, from: Data(contentsOf: calibrationURL))
    }

    public static func saveCalibration(_ model: GazeModel) throws {
        try save(model, to: calibrationURL)
    }

    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
