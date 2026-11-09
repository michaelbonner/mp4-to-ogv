import AppKit
import AVFoundation
import SwiftUI

@main
struct MP4ToOGVApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().frame(minWidth: 680, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
    }
}

struct ConversionJob: Identifiable {
    enum Status: Equatable { case waiting, converting, thumbnail, complete, failed(String), cancelled }
    let id = UUID()
    let sourceURL: URL
    var progress = 0.0
    var status: Status = .waiting
}

@MainActor
final class ConverterViewModel: ObservableObject {
    @Published private(set) var jobs: [ConversionJob] = []
    @Published var outputDirectory: URL?
    @Published private(set) var isConverting = false
    @Published private(set) var ffmpegAvailable = false
    @Published var notice = "Choose MP4 files to begin."
    private var conversionTask: Task<Void, Never>?

    init() {
        ffmpegAvailable = Self.ffmpegURL() != nil
        if !ffmpegAvailable { notice = "FFmpeg is required. Install it with Homebrew: brew install ffmpeg" }
    }

    deinit { conversionTask?.cancel() }

    func addFiles(_ urls: [URL]) {
        let mp4s = urls.filter { $0.pathExtension.lowercased() == "mp4" }
        guard !mp4s.isEmpty else { notice = "Please choose MP4 files."; return }
        let existing = Set(jobs.map(\.sourceURL))
        jobs.append(contentsOf: mp4s.filter { !existing.contains($0) }.map { ConversionJob(sourceURL: $0) })
        notice = "\(jobs.count) file\(jobs.count == 1 ? "" : "s") queued."
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { addFiles(panel.urls) }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url { outputDirectory = url; notice = "Output folder: \(url.lastPathComponent)" }
    }

    func removeJobs(at offsets: IndexSet) { guard !isConverting else { return }; jobs.remove(atOffsets: offsets) }
    func clearCompleted() { guard !isConverting else { return }; jobs.removeAll { $0.status == .complete || $0.status == .cancelled || isFailure($0.status) } }

    func convert() {
        guard !isConverting, let outputDirectory else { if outputDirectory == nil { notice = "Choose an output folder first." }; return }
        guard let ffmpeg = Self.ffmpegURL() else { ffmpegAvailable = false; notice = "FFmpeg was not found. Install it with: brew install ffmpeg"; return }
        guard let profile = Self.encoderProfile(for: ffmpeg) else {
            notice = "Your FFmpeg needs either libtheora or libvpx to create OGV video."
            return
        }
        let queuedIDs = jobs.filter { $0.status == .waiting }.map(\.id)
        guard !queuedIDs.isEmpty else { return }
        isConverting = true
        notice = "Converting \(queuedIDs.count) file\(queuedIDs.count == 1 ? "" : "s") with \(profile.displayName)…"
        conversionTask = Task { [weak self] in
            for id in queuedIDs {
                guard !Task.isCancelled, let self else { break }
                await self.convert(id: id, ffmpeg: ffmpeg, profile: profile, outputDirectory: outputDirectory)
            }
            guard let self else { return }
            self.isConverting = false
            self.conversionTask = nil
            self.notice = Task.isCancelled ? "Conversion cancelled." : "Conversion finished."
        }
    }

    func cancel() { conversionTask?.cancel() }
    func revealOutput() { if let outputDirectory { NSWorkspace.shared.activateFileViewerSelecting([outputDirectory]) } }

    private func convert(id: UUID, ffmpeg: URL, profile: EncoderProfile, outputDirectory: URL) async {
        guard let sourceURL = jobs.first(where: { $0.id == id })?.sourceURL else { return }
        update(id) { $0.status = .converting; $0.progress = 0 }
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let ogvURL = outputDirectory.appendingPathComponent(stem + ".ogv")
        let thumbnailURL = outputDirectory.appendingPathComponent(stem + "-thumbnail.jpg")
        let duration = max((try? await assetDuration(sourceURL)) ?? 1, 1)
        do {
            try await runFFmpeg(ffmpeg, arguments: ["-y", "-i", sourceURL.path] + profile.arguments + [ogvURL.path], duration: duration) { [weak self] progress in
                Task { @MainActor in self?.update(id) { $0.progress = progress * 0.9 } }
            }
            try Task.checkCancellation()
            update(id) { $0.status = .thumbnail; $0.progress = 0.9 }
            try await runFFmpeg(ffmpeg, arguments: ["-y", "-ss", "0", "-i", sourceURL.path, "-frames:v", "1", thumbnailURL.path], duration: 1) { _ in }
            update(id) { $0.status = .complete; $0.progress = 1 }
        } catch {
            if Task.isCancelled {
                update(id) { $0.status = .cancelled }
            } else {
                update(id) { $0.status = .failed(error.localizedDescription) }
            }
        }
    }

    private func update(_ id: UUID, change: (inout ConversionJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    private func assetDuration(_ url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return duration.seconds.isFinite ? duration.seconds : 1
    }

    private static func ffmpegURL() -> URL? {
        let bundled = Bundle.main.url(forResource: "ffmpeg", withExtension: nil, subdirectory: "FFmpeg")
        let systemCandidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"].map(URL.init(fileURLWithPath:))
        return ([bundled].compactMap { $0 } + systemCandidates).first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    private static func encoderProfile(for ffmpeg: URL) -> EncoderProfile? {
        let output = ProcessRunner.output(executable: ffmpeg, arguments: ["-hide_banner", "-encoders"])
        let video: (String, String, [String])? = output.contains("libtheora")
            ? ("libtheora", "Theora", ["-c:v", "libtheora", "-qscale:v", "5"])
            : output.contains("libvpx")
                ? ("libvpx", "VP8", ["-c:v", "libvpx", "-b:v", "1M"])
                : nil
        guard let video else { return nil }
        let audio = output.contains("libvorbis")
            ? ["-c:a", "libvorbis", "-b:a", "128k"]
            : ["-c:a", "vorbis", "-strict", "-2", "-b:a", "128k"]
        return EncoderProfile(displayName: video.1, arguments: video.2 + audio)
    }

    private func isFailure(_ status: ConversionJob.Status) -> Bool { if case .failed = status { return true }; return false }
}

private struct EncoderProfile: Sendable {
    let displayName: String
    let arguments: [String]
}

private enum ProcessRunner {
    static func output(executable: URL, arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

private func runFFmpeg(_ executable: URL, arguments: [String], duration: Double, progress: @escaping @Sendable (Double) -> Void) async throws {
    let process = Process()
    process.executableURL = executable
    process.arguments = ["-hide_banner", "-nostdin", "-progress", "pipe:2"] + arguments
    let pipe = Pipe()
    process.standardError = pipe
    process.standardOutput = Pipe()
    let output = StringBuffer()
    pipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
        output.append(text)
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("out_time_ms=") {
            if let microseconds = Double(line.dropFirst("out_time_ms=".count)) { progress(min(microseconds / 1_000_000 / duration, 0.99)) }
        }
    }
    try process.run()
    try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { completed in
                pipe.fileHandleForReading.readabilityHandler = nil
                completed.terminationStatus == 0 ? continuation.resume() : continuation.resume(throwing: ConversionError.failed(output.value))
            }
        }
    } onCancel: { if process.isRunning { process.terminate() } }
    try Task.checkCancellation()
}

private final class StringBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""
    func append(_ string: String) { lock.lock(); storage += string; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return storage }
}

private enum ConversionError: LocalizedError {
    case failed(String)
    var errorDescription: String? { switch self { case .failed(let output): return output.split(separator: "\n").suffix(1).first.map(String.init) ?? "FFmpeg failed." } }
}

struct ContentView: View {
    @StateObject private var model = ConverterViewModel()
    @StateObject private var dropTarget = DropTarget()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MP4 to OGV").font(.largeTitle.bold())
                Text("Convert MP4 videos and make first-frame thumbnails locally.").foregroundStyle(.secondary)
            }
            HStack {
                Button("Add MP4 Files…", action: model.chooseFiles).keyboardShortcut("o", modifiers: .command)
                Button("Choose Output Folder…", action: model.chooseOutputDirectory)
                Spacer()
                if let folder = model.outputDirectory { Label(folder.path, systemImage: "folder").lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary) }
            }
            dropZone
            List { ForEach(model.jobs) { job in JobRow(job: job) }.onDelete(perform: model.removeJobs) }
                .overlay { if model.jobs.isEmpty { ContentUnavailableView("No files queued", systemImage: "film", description: Text("Add MP4 files or drop them above.")) } }
            HStack {
                Text(model.notice).font(.callout).foregroundStyle(model.ffmpegAvailable ? Color.secondary : Color.red)
                Spacer()
                Button("Clear Finished", action: model.clearCompleted).disabled(model.isConverting || model.jobs.isEmpty)
                Button("Reveal Output", action: model.revealOutput).disabled(model.outputDirectory == nil)
                if model.isConverting { Button("Cancel", role: .destructive, action: model.cancel) }
                else { Button("Convert", action: model.convert).buttonStyle(.borderedProminent).disabled(model.jobs.allSatisfy { $0.status != .waiting } || model.outputDirectory == nil || !model.ffmpegAvailable) }
            }
        }.padding(24)
    }

    private var dropZone: some View {
        VStack(spacing: 8) { Image(systemName: "arrow.down.to.line.compact").font(.title2); Text("Drop MP4 files here").fontWeight(.medium) }
            .frame(maxWidth: .infinity).padding(18)
            .background(dropTarget.isTargeted ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onDrop(of: [.fileURL], isTargeted: $dropTarget.isTargeted) { providers in
                for provider in providers {
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                        guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                        Task { @MainActor in model.addFiles([url]) }
                    }
                }
                return true
            }
    }
}

private final class DropTarget: ObservableObject {
    @Published var isTargeted = false
}

private struct JobRow: View {
    let job: ConversionJob
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(job.sourceURL.lastPathComponent).lineLimit(1); Spacer(); Text(label).foregroundStyle(color) }
            if job.status == .converting || job.status == .thumbnail { ProgressView(value: job.progress) }
            if case .failed(let message) = job.status { Text(message).font(.caption).foregroundStyle(.red).lineLimit(2) }
        }.padding(.vertical, 3)
    }
    private var label: String { switch job.status { case .waiting: "Waiting"; case .converting: "Converting \(Int(job.progress * 100))%"; case .thumbnail: "Making thumbnail"; case .complete: "Complete"; case .failed: "Failed"; case .cancelled: "Cancelled" } }
    private var color: Color { switch job.status { case .complete: .green; case .failed: .red; case .cancelled: .orange; default: .secondary } }
}
