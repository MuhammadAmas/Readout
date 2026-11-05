import CSherpaOnnx
import Darwin
import Foundation

final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

final class KokoroSynthesizer {
    enum LoadError: Error, CustomStringConvertible {
        case notInstalled
        case library(String)
        case symbol(String)
        case model

        var description: String {
            switch self {
            case .notInstalled: "the neural voice files are not installed"
            case .library(let message): "could not open the sherpa-onnx runtime: \(message)"
            case .symbol(let name): "the sherpa-onnx runtime has no \(name)"
            case .model: "sherpa-onnx could not load the Kokoro model"
            }
        }
    }

    private typealias Create = @convention(c) (UnsafePointer<SherpaOnnxOfflineTtsConfig>?) -> OpaquePointer?
    private typealias Destroy = @convention(c) (OpaquePointer?) -> Void
    private typealias SampleRate = @convention(c) (OpaquePointer?) -> Int32
    private typealias Generate = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        UnsafePointer<SherpaOnnxGenerationConfig>?,
        SherpaOnnxGeneratedAudioProgressCallbackWithArg?,
        UnsafeMutableRawPointer?
    ) -> UnsafePointer<SherpaOnnxGeneratedAudio>?
    private typealias DestroyAudio = @convention(c) (UnsafePointer<SherpaOnnxGeneratedAudio>?) -> Void

    private struct Library {
        let create: Create
        let destroy: Destroy
        let sampleRate: SampleRate
        let generate: Generate
        let destroyAudio: DestroyAudio

        static let shared: Result<Library, LoadError> = {
            do {
                return .success(try open())
            } catch let error as LoadError {
                return .failure(error)
            } catch {
                return .failure(.library(error.localizedDescription))
            }
        }()

        private static func open() throws -> Library {
            guard let handle = dlopen(NeuralVoiceInstallation.runtimeLibrary.path, RTLD_NOW | RTLD_LOCAL) else {
                throw LoadError.library(dlerror().map { String(cString: $0) } ?? "unknown error")
            }
            func symbol<T>(_ name: String, as type: T.Type) throws -> T {
                guard let pointer = dlsym(handle, name) else { throw LoadError.symbol(name) }
                return unsafeBitCast(pointer, to: type)
            }
            return Library(
                create: try symbol("SherpaOnnxCreateOfflineTts", as: Create.self),
                destroy: try symbol("SherpaOnnxDestroyOfflineTts", as: Destroy.self),
                sampleRate: try symbol("SherpaOnnxOfflineTtsSampleRate", as: SampleRate.self),
                generate: try symbol("SherpaOnnxOfflineTtsGenerateWithConfig", as: Generate.self),
                destroyAudio: try symbol("SherpaOnnxDestroyOfflineTtsGeneratedAudio", as: DestroyAudio.self)
            )
        }
    }

    private static let progress: SherpaOnnxGeneratedAudioProgressCallbackWithArg = { _, _, _, argument in
        guard let argument else { return 1 }
        return Unmanaged<CancelToken>.fromOpaque(argument).takeUnretainedValue().isCancelled ? 0 : 1
    }

    let accent: KokoroVoice.Accent
    let sampleRate: Double

    private let library: Library
    private let handle: OpaquePointer
    private let strings: [UnsafeMutablePointer<CChar>]

    init(accent: KokoroVoice.Accent, threads: Int) throws {
        guard NeuralVoiceInstallation.isInstalled else { throw LoadError.notInstalled }
        let library = try Library.shared.get()
        let directory = NeuralVoiceInstallation.modelDirectory

        var strings: [UnsafeMutablePointer<CChar>] = []
        func string(_ value: String) -> UnsafePointer<CChar> {
            let pointer = strdup(value)!
            strings.append(pointer)
            return UnsafePointer(pointer)
        }

        var config = SherpaOnnxOfflineTtsConfig()
        config.model.kokoro.model = string(directory.appendingPathComponent("model.onnx").path)
        config.model.kokoro.voices = string(directory.appendingPathComponent("voices.bin").path)
        config.model.kokoro.tokens = string(directory.appendingPathComponent("tokens.txt").path)
        config.model.kokoro.data_dir = string(directory.appendingPathComponent("espeak-ng-data").path)
        config.model.kokoro.lexicon = string(directory.appendingPathComponent(accent.lexicon).path)
        config.model.kokoro.lang = string(accent.espeakLanguage)
        config.model.kokoro.length_scale = 1
        config.model.num_threads = Int32(threads)
        config.model.provider = string("cpu")
        config.model.debug = 0
        config.max_num_sentences = 1
        config.silence_scale = 0.2

        guard let handle = withUnsafePointer(to: &config, { library.create($0) }) else {
            strings.forEach { free($0) }
            throw LoadError.model
        }
        self.accent = accent
        self.library = library
        self.handle = handle
        self.strings = strings
        sampleRate = Double(library.sampleRate(handle))
    }

    deinit {
        library.destroy(handle)
        strings.forEach { free($0) }
    }

    func synthesize(_ text: String, speakerID: Int32, speed: Float, cancel: CancelToken) -> [Float]? {
        var generation = SherpaOnnxGenerationConfig()
        generation.sid = speakerID
        generation.speed = speed
        generation.silence_scale = 0.2
        let token = Unmanaged.passUnretained(cancel).toOpaque()
        let audio = text.withCString { characters in
            withUnsafePointer(to: &generation) { configuration in
                library.generate(handle, characters, configuration, Self.progress, token)
            }
        }
        guard let audio else { return nil }
        defer { library.destroyAudio(audio) }
        guard !cancel.isCancelled else { return nil }
        let count = Int(audio.pointee.n)
        guard count > 0, let samples = audio.pointee.samples else { return [] }
        return Array(UnsafeBufferPointer(start: samples, count: count))
    }
}

final class KokoroWorker: @unchecked Sendable {
    static let shared = KokoroWorker()

    private let queue = DispatchQueue(label: "dev.readout.kokoro", qos: .userInitiated)
    private let threads = max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2))
    private let idleUnloadDelay: TimeInterval = 15 * 60
    private var synthesizer: KokoroSynthesizer?
    private var unloadWork: DispatchWorkItem?
    private let stateLock = NSLock()
    private var isShuttingDown = false

    private var acceptsWork: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return !isShuttingDown
    }

    func shutDown(timeout: TimeInterval) {
        stateLock.lock()
        isShuttingDown = true
        stateLock.unlock()
        let idle = DispatchSemaphore(value: 0)
        queue.async { idle.signal() }
        if idle.wait(timeout: .now() + timeout) == .timedOut {
            Log.speech.error("Kokoro was still busy \(Int(timeout), privacy: .public) s after quitting began")
        }
    }

    func preload(_ accent: KokoroVoice.Accent) {
        queue.async {
            guard self.acceptsWork else { return }
            _ = self.loadedSynthesizer(for: accent)
            self.scheduleUnload()
        }
    }

    func render(
        _ pieces: [String],
        voice: KokoroVoice,
        speed: Float,
        token: CancelToken,
        deliver: @escaping @Sendable (_ index: Int, _ samples: [Float]?, _ sampleRate: Double) -> Void
    ) {
        queue.async {
            guard !token.isCancelled, self.acceptsWork else { return }
            self.unloadWork?.cancel()
            guard let synthesizer = self.loadedSynthesizer(for: voice.accent) else {
                for index in pieces.indices { deliver(index, nil, 24_000) }
                return
            }
            for (index, piece) in pieces.enumerated() {
                guard !token.isCancelled, self.acceptsWork else { return }
                let started = Date()
                let samples = synthesizer.synthesize(piece, speakerID: voice.speakerID, speed: speed, cancel: token)
                guard !token.isCancelled else { return }
                Log.speech.debug("Kokoro rendered \(piece.count, privacy: .public) characters in \(Int(Date().timeIntervalSince(started) * 1000), privacy: .public) ms")
                deliver(index, samples, synthesizer.sampleRate)
            }
            self.scheduleUnload()
        }
    }

    private func loadedSynthesizer(for accent: KokoroVoice.Accent) -> KokoroSynthesizer? {
        if let synthesizer, synthesizer.accent == accent {
            return synthesizer
        }
        synthesizer = nil
        let started = Date()
        do {
            synthesizer = try KokoroSynthesizer(accent: accent, threads: threads)
            Log.speech.info("Kokoro loaded (\(accent.language, privacy: .public), \(self.threads, privacy: .public) threads) in \(Int(Date().timeIntervalSince(started) * 1000), privacy: .public) ms")
        } catch {
            Log.speech.error("Kokoro failed to load: \(String(describing: error), privacy: .public)")
        }
        return synthesizer
    }

    private func scheduleUnload() {
        unloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.synthesizer = nil
            Log.speech.info("Kokoro unloaded after being idle")
        }
        unloadWork = work
        queue.asyncAfter(deadline: .now() + idleUnloadDelay, execute: work)
    }
}
