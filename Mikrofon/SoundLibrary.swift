import AVFAudio
import Foundation

struct SoundClip: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let fileName: String
}

@MainActor
final class SoundLibrary: ObservableObject {
    @Published private(set) var sounds: [SoundClip] = []
    @Published private(set) var backingTrackURL: URL?
    @Published private(set) var backingTrackName: String?

    private let fileManager = FileManager.default
    private let baseDirectory: URL
    private let soundsDirectory: URL
    private let backingDirectory: URL

    private let soundsKey = "liveMic.soundboard.v1"
    private let backingFileKey = "liveMic.backing.file.v1"
    private let backingNameKey = "liveMic.backing.name.v1"

    init() {
        let appSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!

        baseDirectory = appSupport.appendingPathComponent("LiveMic", isDirectory: true)
        soundsDirectory = baseDirectory.appendingPathComponent("Sounds", isDirectory: true)
        backingDirectory = baseDirectory.appendingPathComponent("Backing", isDirectory: true)

        try? fileManager.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: backingDirectory, withIntermediateDirectories: true)

        loadSounds()
        loadBackingTrack()
    }

    func url(for sound: SoundClip) -> URL {
        soundsDirectory.appendingPathComponent(sound.fileName)
    }

    @discardableResult
    func importSound(from sourceURL: URL) throws -> SoundClip {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scoped { sourceURL.stopAccessingSecurityScopedResource() }
        }

        try validatePlayableAudio(at: sourceURL)

        let id = UUID()
        let fileName = storedFileName(id: id, sourceURL: sourceURL)
        let destination = soundsDirectory.appendingPathComponent(fileName)

        try replaceCopy(from: sourceURL, to: destination)

        let original = sourceURL.deletingPathExtension().lastPathComponent
        let clip = SoundClip(
            id: id,
            name: original.isEmpty ? "Sound" : original,
            fileName: fileName
        )

        sounds.append(clip)
        saveSounds()
        return clip
    }

    func rename(_ sound: SoundClip, to newName: String) {
        let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              let index = sounds.firstIndex(where: { $0.id == sound.id }) else { return }

        sounds[index].name = cleanName
        saveSounds()
    }

    func delete(_ sound: SoundClip) {
        try? fileManager.removeItem(at: url(for: sound))
        sounds.removeAll { $0.id == sound.id }
        saveSounds()
    }

    func importBackingTrack(from sourceURL: URL) throws {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scoped { sourceURL.stopAccessingSecurityScopedResource() }
        }

        try validatePlayableAudio(at: sourceURL)

        if let oldFiles = try? fileManager.contentsOfDirectory(
            at: backingDirectory,
            includingPropertiesForKeys: nil
        ) {
            for oldFile in oldFiles {
                try? fileManager.removeItem(at: oldFile)
            }
        }

        let id = UUID()
        let fileName = "backing-" + storedFileName(id: id, sourceURL: sourceURL)
        let destination = backingDirectory.appendingPathComponent(fileName)

        try replaceCopy(from: sourceURL, to: destination)

        backingTrackURL = destination
        backingTrackName = sourceURL.deletingPathExtension().lastPathComponent
        UserDefaults.standard.set(fileName, forKey: backingFileKey)
        UserDefaults.standard.set(backingTrackName, forKey: backingNameKey)
    }

    func clearBackingTrack() {
        if let backingTrackURL {
            try? fileManager.removeItem(at: backingTrackURL)
        }

        backingTrackURL = nil
        backingTrackName = nil
        UserDefaults.standard.removeObject(forKey: backingFileKey)
        UserDefaults.standard.removeObject(forKey: backingNameKey)
    }

    private func validatePlayableAudio(at url: URL) throws {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            guard player.prepareToPlay(), player.duration > 0 else {
                throw unsupportedAudioError()
            }
        } catch {
            throw unsupportedAudioError()
        }
    }

    private func unsupportedAudioError() -> NSError {
        NSError(
            domain: "LiveMic.Import",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Diese Datei kann von iOS nicht als Audio abgespielt werden. Bitte verwende z. B. MP3, M4A, WAV oder AIFF."
            ]
        )
    }

    private func storedFileName(id: UUID, sourceURL: URL) -> String {
        let ext = sourceURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return ext.isEmpty ? id.uuidString : id.uuidString + "." + ext.lowercased()
    }

    private func replaceCopy(from source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func loadSounds() {
        guard let data = UserDefaults.standard.data(forKey: soundsKey),
              let decoded = try? JSONDecoder().decode([SoundClip].self, from: data) else {
            sounds = []
            return
        }

        sounds = decoded.filter { fileManager.fileExists(atPath: url(for: $0).path) }
    }

    private func saveSounds() {
        guard let data = try? JSONEncoder().encode(sounds) else { return }
        UserDefaults.standard.set(data, forKey: soundsKey)
    }

    private func loadBackingTrack() {
        guard let fileName = UserDefaults.standard.string(forKey: backingFileKey) else { return }
        let url = backingDirectory.appendingPathComponent(fileName)

        guard fileManager.fileExists(atPath: url.path) else {
            UserDefaults.standard.removeObject(forKey: backingFileKey)
            UserDefaults.standard.removeObject(forKey: backingNameKey)
            return
        }

        backingTrackURL = url
        backingTrackName = UserDefaults.standard.string(forKey: backingNameKey) ?? "Backing Track"
    }
}
