import Foundation

public struct SpeechVoiceSettings: Equatable, Sendable {
    public static let rateRange: ClosedRange<Double> = 0.5...2.0

    public var voiceIdentifier: String?
    public var rateMultiplier: Double
    public var volume: Float

    public init(voiceIdentifier: String? = nil, rateMultiplier: Double = 1.0, volume: Float = 1.0) {
        self.voiceIdentifier = voiceIdentifier
        self.rateMultiplier = min(max(rateMultiplier, Self.rateRange.lowerBound), Self.rateRange.upperBound)
        self.volume = volume
    }
}

public struct SpeechRequest: Equatable, Sendable {
    public let id: Int
    public let sentenceIndex: Int
    public let text: String
    public let settings: SpeechVoiceSettings

    public init(id: Int, sentenceIndex: Int, text: String, settings: SpeechVoiceSettings) {
        self.id = id
        self.sentenceIndex = sentenceIndex
        self.text = text
        self.settings = settings
    }
}

@MainActor
public protocol SpeechEngine: AnyObject {
    var delegate: (any SpeechEngineDelegate)? { get set }
    func speak(_ request: SpeechRequest)
    func pause()
    func resume()
    func stop()
}

@MainActor
public protocol SpeechEngineDelegate: AnyObject {
    func speechEngine(_ engine: any SpeechEngine, didStart request: SpeechRequest)
    func speechEngine(_ engine: any SpeechEngine, willSpeak range: NSRange, of request: SpeechRequest)
    func speechEngine(_ engine: any SpeechEngine, didFinish request: SpeechRequest)
}
