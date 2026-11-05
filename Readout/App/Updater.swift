import AppKit
import Foundation
import os
import Security

@MainActor
final class Updater {
    struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft, prerelease, assets
        }

        var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
    }

    struct PreparedUpdate {
        let version: String
        let app: URL
    }

    enum UpdateError: Error, CustomStringConvertible {
        case missingAsset(String)
        case checksum
        case unpack
        case signature(OSStatus)
        case identity(String)

        var description: String {
            switch self {
            case .missingAsset(let name): "the release has no \(name)"
            case .checksum: "the download's SHA-256 doesn't match"
            case .unpack: "the download couldn't be unpacked"
            case .signature(let status): "the new app isn't signed by the same certificate (\(status))"
            case .identity(let detail): "the new app doesn't look like Readout: \(detail)"
            }
        }
    }

    static let shared = Updater()
    static let relaunchArgument = "--updated-from"

    private static let log = Logger(subsystem: "dev.readout.Readout", category: "updates")
    private static let feed = URL(string: "https://api.github.com/repos/MuhammadAmas/Readout/releases/latest")!

    private let firstCheckDelay: TimeInterval = 60
    private let checkInterval: TimeInterval = 6 * 60 * 60
    private var timer: Timer?
    private var isChecking = false
    private var pending: PreparedUpdate?
    private var waitTimer: Timer?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Preferences.automaticUpdates)
    }

    func start() {
        guard canReplaceItself else {
            Self.log.info("Automatic updates are off for this copy: \(Bundle.main.bundlePath, privacy: .public) is not an installed app")
            return
        }
        timer?.invalidate()
        let delay = ProcessInfo.processInfo.environment["READOUT_UPDATE_FEED"] == nil ? firstCheckDelay : 3
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.checkInBackground() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkInBackground() }
        }
    }

    var canReplaceItself: Bool {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else { return false }
        let parent = bundle.deletingLastPathComponent()
        let applications = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        guard applications.contains(where: { $0.standardizedFileURL.path == parent.standardizedFileURL.path }) else { return false }
        return FileManager.default.isWritableFile(atPath: parent.path)
    }

    func checkInBackground() {
        guard isEnabled, !isChecking, pending == nil else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                if let update = try await prepareUpdate() {
                    pending = update
                    installWhenIdle()
                }
            } catch {
                Self.log.error("Update check failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func prepareUpdate() async throws -> PreparedUpdate? {
        let feed = ProcessInfo.processInfo.environment["READOUT_UPDATE_FEED"].flatMap(URL.init(string:)) ?? Self.feed
        let release = try JSONDecoder().decode(Release.self, from: try await data(from: feed))
        guard release.draft != true, release.prerelease != true else { return nil }
        guard Self.isVersion(release.version, newerThan: currentVersion) else {
            Self.log.info("Readout \(self.currentVersion, privacy: .public) is up to date (latest is \(release.version, privacy: .public))")
            return nil
        }
        Self.log.info("Readout \(release.version, privacy: .public) is available; downloading")

        guard let zip = release.assets.first(where: { $0.name == "Readout.zip" }) else { throw UpdateError.missingAsset("Readout.zip") }
        guard let checksum = release.assets.first(where: { $0.name == "Readout.zip.sha256" }) else { throw UpdateError.missingAsset("Readout.zip.sha256") }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ReadoutUpdate-\(release.version)", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let archive = folder.appendingPathComponent("Readout.zip")
        try await data(from: zip.browserDownloadURL).write(to: archive)
        let expected = String(decoding: try await data(from: checksum.browserDownloadURL), as: UTF8.self)
            .split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        guard try await Self.sha256(of: archive) == expected.lowercased() else { throw UpdateError.checksum }

        let unpacked = folder.appendingPathComponent("unpacked", isDirectory: true)
        guard try await Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path]) == 0 else { throw UpdateError.unpack }
        let app = unpacked.appendingPathComponent("Readout.app", isDirectory: true)

        try verify(app, expectedVersion: release.version)
        Self.log.info("Readout \(release.version, privacy: .public) downloaded and verified")
        return PreparedUpdate(version: release.version, app: app)
    }

    private func verify(_ app: URL, expectedVersion: String) throws {
        guard let bundle = Bundle(url: app) else { throw UpdateError.identity("no app bundle") }
        guard bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.identity("bundle identifier \(bundle.bundleIdentifier ?? "none")")
        }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard version == expectedVersion else { throw UpdateError.identity("version \(version ?? "none")") }

        var running: SecCode?
        var runningStatic: SecStaticCode?
        var requirement: SecRequirement?
        var candidate: SecStaticCode?
        var status = SecCodeCopySelf([], &running)
        if status == errSecSuccess, let running {
            status = SecCodeCopyStaticCode(running, [], &runningStatic)
        }
        if status == errSecSuccess, let runningStatic {
            status = SecCodeCopyDesignatedRequirement(runningStatic, [], &requirement)
        }
        if status == errSecSuccess {
            status = SecStaticCodeCreateWithPath(app as CFURL, [], &candidate)
        }
        if status == errSecSuccess, let candidate, let requirement {
            let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
            status = SecStaticCodeCheckValidity(candidate, flags, requirement)
        }
        guard status == errSecSuccess else { throw UpdateError.signature(status) }
    }

    private func installWhenIdle() {
        guard let pending else { return }
        if AppModel.shared.queue.isActive || AppModel.shared.previewQueue.isActive {
            guard waitTimer == nil else { return }
            Self.log.info("Readout \(pending.version, privacy: .public) will install when reading finishes")
            waitTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !AppModel.shared.queue.isActive, !AppModel.shared.previewQueue.isActive else { return }
                    self.waitTimer?.invalidate()
                    self.waitTimer = nil
                    self.install(pending)
                }
            }
            return
        }
        install(pending)
    }

    private func install(_ update: PreparedUpdate) {
        let target = Bundle.main.bundleURL
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        target=\(Self.quoted(target.path))
        backup="$target.previous"
        rm -rf "$backup"
        if mv "$target" "$backup" && /usr/bin/ditto \(Self.quoted(update.app.path)) "$target"; then
            rm -rf "$backup"
        else
            rm -rf "$target"
            mv "$backup" "$target"
        fi
        /usr/bin/open "$target" --args \(Self.relaunchArgument) \(Self.quoted(currentVersion))
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        do {
            try process.run()
        } catch {
            Self.log.error("Could not start the installer: \(error.localizedDescription, privacy: .public)")
            return
        }
        Self.log.info("Installing Readout \(update.version, privacy: .public) and relaunching")
        NSApp.terminate(nil)
    }

    private func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("Readout/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    nonisolated private static func sha256(of file: URL) async throws -> String {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", file.path]
        process.standardOutput = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: output, as: UTF8.self).split(separator: " ").first.map(String.init) ?? ""
    }

    nonisolated private static func run(_ executable: String, _ arguments: [String]) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
