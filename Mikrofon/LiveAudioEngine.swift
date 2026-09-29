import AVFAudio
import Foundation

@MainActor
final class LiveAudioEngine: NSObject, ObservableObject {
    @Published private(set) var isLive = false
    @Published private(set) var isStarting = false
    @Published private(set) var micLevel: Double = 0
    @Published private(set) var outputName = "iPhone"
    @Published private(set) var outputDetail = "Interner Lautsprecher"
    @Published private(set) var isExternalOutput = false
    @Published private(set) var isBackingPlaying = false

    @Published var micGain: Double = 1.0 {
        didSet { micMixer.outputVolume = Float(micGain) }
    }

    @Published var backingVolume: Double = 0.55 {
        didSet { backingPlayer?.volume = Float(backingVolume) }
    }

    @Published var soundVolume: Double = 0.85
    @Published var backingLoops = true {
        didSet { backingPlayer?.numberOfLoops = backingLoops ? -1 : 0 }
    }

    @Published var errorMessage: String?

    private let session = AVAudioSession.sharedInstance()
    private let engine = AVAudioEngine()
    private let micMixer = AVAudioMixerNode()
    private var hasMicTap = false

    private var backingPlayer: AVAudioPlayer?
    private var oneShotPlayers: [UUID: AVAudioPlayer] = [:]
    private var routeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        engine.attach(micMixer)

        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshRoute()
            }
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                self?.handleInterruption(note)
            }
        }

        refreshRoute()
    }

    deinit {
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    func toggleLive() {
        if isLive {
            stopLive()
            return
        }

        guard !isStarting else { return }
        isStarting = true

        Task {
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                isStarting = false
                errorMessage = "Mikrofonzugriff wurde nicht erlaubt. Bitte aktiviere ihn in den iOS-Einstellungen für Live Mic."
                return
            }

            do {
                try startLive()
            } catch {
                isStarting = false
                errorMessage = "Live-Mikrofon konnte nicht gestartet werden: \(error.localizedDescription)"
            }
        }
    }

    func stopLive() {
        backingPlayer?.stop()
        backingPlayer = nil
        isBackingPlaying = false
        oneShotPlayers.removeAll()

        if hasMicTap {
            engine.inputNode.removeTap(onBus: 0)
            hasMicTap = false
        }

        engine.stop()
        engine.disconnectNodeOutput(engine.inputNode)
        engine.disconnectNodeOutput(micMixer)
        micLevel = 0
        isLive = false
        isStarting = false

        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        refreshRoute()
    }

    func playOrPauseBacking(url: URL) {
        do {
            try activateSessionForPlayback()

            if let player = backingPlayer, player.url == url {
                if player.isPlaying {
                    player.pause()
                    isBackingPlaying = false
                } else {
                    player.play()
                    isBackingPlaying = true
                }
                return
            }

            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(backingVolume)
            player.numberOfLoops = backingLoops ? -1 : 0
            player.prepareToPlay()
            player.play()

            backingPlayer = player
            isBackingPlaying = true
        } catch {
            errorMessage = "Backing-Track konnte nicht abgespielt werden: \(error.localizedDescription)"
        }
    }

    func restartBacking() {
        backingPlayer?.currentTime = 0
        if backingPlayer != nil {
            backingPlayer?.play()
            isBackingPlaying = true
        }
    }

    func stopBacking() {
        backingPlayer?.stop()
        backingPlayer = nil
        isBackingPlaying = false
    }

    func playSound(url: URL) {
        do {
            try activateSessionForPlayback()

            let id = UUID()
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(soundVolume)
            player.prepareToPlay()
            player.play()
            oneShotPlayers[id] = player

            let lifetime = max(player.duration + 0.5, 1.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) { [weak self] in
                self?.oneShotPlayers[id] = nil
            }
        } catch {
            errorMessage = "Sound konnte nicht abgespielt werden: \(error.localizedDescription)"
        }
    }

    func presentError(_ message: String) {
        errorMessage = message
    }

    func refreshRoute() {
        guard let output = session.currentRoute.outputs.first else {
            outputName = "Keine Ausgabe"
            outputDetail = "Verbinde einen Lautsprecher oder Kopfhörer"
            isExternalOutput = false
            return
        }

        outputName = output.portName

        switch output.portType {
        case .bluetoothA2DP:
            outputDetail = "Bluetooth · A2DP"
            isExternalOutput = true
        case .bluetoothHFP:
            outputDetail = "Bluetooth · Freisprechen"
            isExternalOutput = true
        case .bluetoothLE:
            outputDetail = "Bluetooth LE"
            isExternalOutput = true
        case .airPlay:
            outputDetail = "AirPlay"
            isExternalOutput = true
        case .headphones:
            outputDetail = "Kopfhörer"
            isExternalOutput = true
        case .usbAudio:
            outputDetail = "USB Audio"
            isExternalOutput = true
        case .HDMI:
            outputDetail = "HDMI"
            isExternalOutput = true
        case .carAudio:
            outputDetail = "Car Audio"
            isExternalOutput = true
        case .builtInReceiver:
            outputDetail = "iPhone-Hörer"
            isExternalOutput = false
        case .builtInSpeaker:
            outputDetail = "Interner Lautsprecher"
            isExternalOutput = false
        default:
            outputDetail = output.portType.rawValue
            isExternalOutput = output.portType != .builtInSpeaker
        }
    }

    private func startLive() throws {
        isStarting = true

        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.allowBluetoothA2DP, .allowAirPlay, .defaultToSpeaker]
        )

        try? session.setPreferredSampleRate(48_000)
        try? session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        if let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try? session.setPreferredInput(builtInMic)
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(
                domain: "LiveMic",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Kein verwendbares Mikrofon gefunden."]
            )
        }

        engine.disconnectNodeOutput(input)
        engine.disconnectNodeOutput(micMixer)

        engine.connect(input, to: micMixer, format: format)
        engine.connect(micMixer, to: engine.mainMixerNode, format: nil)
        micMixer.outputVolume = Float(micGain)

        if hasMicTap {
            input.removeTap(onBus: 0)
            hasMicTap = false
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let channel = buffer.floatChannelData?.pointee else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }

            var sum: Float = 0
            for index in 0..<frameCount {
                let sample = channel[index]
                sum += sample * sample
            }

            let rms = sqrt(sum / Float(frameCount))
            let db = 20 * log10(max(rms, 0.000_001))
            let normalized = Double(min(max((db + 60) / 60, 0), 1))

            Task { @MainActor [weak self] in
                self?.micLevel = normalized
            }
        }
        hasMicTap = true

        engine.prepare()
        try engine.start()

        isLive = true
        isStarting = false
        refreshRoute()
    }

    private func activateSessionForPlayback() throws {
        if !isLive {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetoothA2DP, .allowAirPlay, .defaultToSpeaker]
            )
            try session.setActive(true)
        }
        refreshRoute()
    }

    private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        if type == .began {
            if engine.isRunning {
                engine.pause()
            }
            isLive = false
            isBackingPlaying = false
            micLevel = 0
        }
    }
}
