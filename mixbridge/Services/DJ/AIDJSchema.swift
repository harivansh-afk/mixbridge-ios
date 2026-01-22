import Foundation
import MixBridgeDJ

enum AIDJSchemaVersion: Int, Codable, Sendable {
    case v1 = 1
}

enum AIDJJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AIDJJSONValue])
    case array([AIDJJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([String: AIDJJSONValue].self) {
            self = .object(value)
            return
        }
        if let value = try? container.decode([AIDJJSONValue].self) {
            self = .array(value)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct AIDJAnalysis: Codable, Sendable, Equatable {
    let bpm: Double
    let beatOffsetSeconds: Double
    let timeSignatureNumerator: Int?
    let timeSignatureDenominator: Int?
    let confidence: Double
    let analysisVersion: String?
    let analysisDurationMs: Int?
    let features: [String: AIDJJSONValue]?

    init(
        bpm: Double,
        beatOffsetSeconds: Double,
        timeSignatureNumerator: Int? = nil,
        timeSignatureDenominator: Int? = nil,
        confidence: Double,
        analysisVersion: String? = nil,
        analysisDurationMs: Int? = nil,
        features: [String: AIDJJSONValue]? = nil
    ) {
        self.bpm = bpm
        self.beatOffsetSeconds = beatOffsetSeconds
        self.timeSignatureNumerator = timeSignatureNumerator
        self.timeSignatureDenominator = timeSignatureDenominator
        self.confidence = confidence
        self.analysisVersion = analysisVersion
        self.analysisDurationMs = analysisDurationMs
        self.features = features
    }
}

struct AIDJTrackContext: Codable, Sendable, Equatable {
    let id: String
    let title: String?
    let artist: String?
    let album: String?
    let durationSeconds: Double?
    let genre: String?
    let tags: [String]?
    let analysis: AIDJAnalysis?
    let metadata: [String: AIDJJSONValue]?

    init(
        id: String,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        durationSeconds: Double? = nil,
        genre: String? = nil,
        tags: [String]? = nil,
        analysis: AIDJAnalysis? = nil,
        metadata: [String: AIDJJSONValue]? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.genre = genre
        self.tags = tags
        self.analysis = analysis
        self.metadata = metadata
    }
}

struct AIDJMixContext: Codable, Sendable, Equatable {
    let currentTimeSeconds: Double?
    let remainingTimeSeconds: Double?
    let userCrossfadeSeconds: Double?
    let suggestedFadeStartSeconds: Double?
    let suggestedFadeDurationSeconds: Double?
    let fadeCurve: AIDJCrossfadeCurve?
    let preferBarSync: Bool?
    let allowBeatSync: Bool?
    let allowTempoMatch: Bool?
    let allowEQPolish: Bool?
    let isManualSkip: Bool?
    let autoplayEnabled: Bool?
    let metadata: [String: AIDJJSONValue]?
}

struct AIDJMixConstraints: Codable, Sendable, Equatable {
    let minFadeSeconds: Double?
    let maxFadeSeconds: Double?
    let maxTempoAdjustment: Double?
    let minTimingConfidence: Double?
    let minEqGainDb: Double?
    let maxEqGainDb: Double?
    let metadata: [String: AIDJJSONValue]?

    static func fromValidator(_ validator: DJPlanValidator) -> AIDJMixConstraints {
        AIDJMixConstraints(
            minFadeSeconds: validator.minFadeDuration,
            maxFadeSeconds: validator.maxFadeDuration,
            maxTempoAdjustment: validator.maxTempoRate - 1.0,
            minTimingConfidence: validator.minTimingConfidence,
            minEqGainDb: validator.minEQGainDB,
            maxEqGainDb: validator.maxEQGainDB,
            metadata: nil
        )
    }
}

struct AIDJMixPreferences: Codable, Sendable, Equatable {
    let preferEqualPower: Bool?
    let preferBassSwap: Bool?
    let avoidVocalOverlap: Bool?
    let styleTags: [String]?
    let metadata: [String: AIDJJSONValue]?
}

struct AIDJMixPlanRequest: Codable, Sendable, Equatable {
    let schemaVersion: AIDJSchemaVersion
    let outgoing: AIDJTrackContext
    let incoming: AIDJTrackContext
    let context: AIDJMixContext?
    let constraints: AIDJMixConstraints?
    let preferences: AIDJMixPreferences?
    let extensions: [String: AIDJJSONValue]?

    init(
        schemaVersion: AIDJSchemaVersion = .v1,
        outgoing: AIDJTrackContext,
        incoming: AIDJTrackContext,
        context: AIDJMixContext? = nil,
        constraints: AIDJMixConstraints? = nil,
        preferences: AIDJMixPreferences? = nil,
        extensions: [String: AIDJJSONValue]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.outgoing = outgoing
        self.incoming = incoming
        self.context = context
        self.constraints = constraints
        self.preferences = preferences
        self.extensions = extensions
    }
}

enum AIDJCrossfadeCurve: String, Codable, Sendable {
    case equalPower
    case linear
    case constantPower
}

enum AIDJBeatAlignmentMode: String, Codable, Sendable {
    case beat
    case bar
    case none
}

enum AIDJEQBand: String, Codable, Sendable {
    case low
    case mid
    case high
}

struct AIDJEQKeyframe: Codable, Sendable, Equatable {
    let progress: Double
    let gainDB: Double
}

struct AIDJEQCurve: Codable, Sendable, Equatable {
    let band: AIDJEQBand
    let keyframes: [AIDJEQKeyframe]
}

struct AIDJTempoMatch: Codable, Sendable, Equatable {
    let enabled: Bool
    let targetBPM: Double?
    let maxRateAdjustment: Double?
    let preservePitch: Bool?
}

struct AIDJMixPlan: Codable, Sendable, Equatable {
    let fadeDurationSeconds: Double
    let fadeStartSeconds: Double
    let crossfadeCurve: AIDJCrossfadeCurve
    let outgoingEQCurves: [AIDJEQCurve]
    let incomingEQCurves: [AIDJEQCurve]
    let tempoMatch: AIDJTempoMatch
    let beatAlignment: AIDJBeatAlignmentMode
    let isFallback: Bool?

    func toDJTransitionPlan() -> DJTransitionPlan {
        let djCurve: DJCrossfadeCurve
        switch crossfadeCurve {
        case .equalPower:
            djCurve = .equalPower
        case .linear:
            djCurve = .linear
        case .constantPower:
            djCurve = .constantPower
        }

        let djBeatAlignment: DJBeatAlignmentMode
        switch beatAlignment {
        case .beat:
            djBeatAlignment = .beat
        case .bar:
            djBeatAlignment = .bar
        case .none:
            djBeatAlignment = .none
        }

        let tempoConfig = DJTempoMatchConfig(
            enabled: tempoMatch.enabled,
            targetBPM: tempoMatch.targetBPM ?? 0,
            maxRateAdjustment: tempoMatch.maxRateAdjustment ?? 0.08,
            preservePitch: tempoMatch.preservePitch ?? true
        )

        return DJTransitionPlan(
            fadeDurationSeconds: fadeDurationSeconds,
            fadeStartSeconds: fadeStartSeconds,
            crossfadeCurve: djCurve,
            outgoingEQCurves: outgoingEQCurves.map { $0.toDJEQCurve() },
            incomingEQCurves: incomingEQCurves.map { $0.toDJEQCurve() },
            tempoMatch: tempoConfig,
            beatAlignment: djBeatAlignment,
            isFallback: isFallback ?? false
        )
    }

    func validated(
        outgoingTiming: DJTrackTiming?,
        incomingTiming: DJTrackTiming?,
        validator: DJPlanValidator = .default
    ) -> DJPlanValidationResult {
        validator.validate(
            plan: toDJTransitionPlan(),
            outgoingTiming: outgoingTiming,
            incomingTiming: incomingTiming
        )
    }
}

struct AIDJMixPlanResponse: Codable, Sendable, Equatable {
    let schemaVersion: AIDJSchemaVersion
    let plan: AIDJMixPlan
    let confidence: Double?
    let warnings: [String]?
    let debug: [String: AIDJJSONValue]?
}

extension AIDJEQCurve {
    func toDJEQCurve() -> DJEQCurve {
        let band: DJEQBand
        switch self.band {
        case .low:
            band = .low
        case .mid:
            band = .mid
        case .high:
            band = .high
        }

        let keyframes = keyframes.map { DJEQKeyframe(progress: $0.progress, gainDB: $0.gainDB) }
        return DJEQCurve(band: band, keyframes: keyframes)
    }
}

extension AIDJAnalysis {
    init(_ result: DJAnalysisResult) {
        self.init(
            bpm: result.bpm,
            beatOffsetSeconds: result.beatOffsetSeconds,
            timeSignatureNumerator: result.timeSignatureNumerator,
            timeSignatureDenominator: result.timeSignatureDenominator,
            confidence: result.confidence,
            analysisVersion: result.metadata.analysisVersion,
            analysisDurationMs: result.metadata.analysisDurationMs
        )
    }

    func toDJAnalysisResult() -> DJAnalysisResult {
        DJAnalysisResult(
            bpm: bpm,
            beatOffsetSeconds: beatOffsetSeconds,
            timeSignatureNumerator: timeSignatureNumerator,
            timeSignatureDenominator: timeSignatureDenominator,
            confidence: confidence,
            metadata: AnalysisMetadata(
                analysisVersion: analysisVersion ?? AnalysisMetadata.currentVersion,
                analysisDurationMs: analysisDurationMs ?? 0,
                failureReason: nil
            )
        )
    }
}

extension AIDJTrackContext {
    static func from(
        track: Track,
        soundCloudTrack: SoundCloudTrack? = nil,
        analysis: DJAnalysisResult? = nil
    ) -> AIDJTrackContext {
        AIDJTrackContext(
            id: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            durationSeconds: track.duration,
            genre: soundCloudTrack?.genre ?? track.album,
            tags: nil,
            analysis: analysis.map { AIDJAnalysis($0) },
            metadata: nil
        )
    }
}
