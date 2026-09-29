import AVFAudio
import Foundation

@MainActor
final class LiveAudioEngine: NSObject, ObservableObject {
    @Published private(set) var isLive = false
    @Published private(set) var isStarting = false
    @Published private(set) var micLevel: Double = 0
    @Published private(set) var inputName = "iPhone-Mikrofon"
    @Published private(set) var outputName = "iPhone"
    @Published private(set) var outputDetail = "Interner Lautsprecher"
    @Published private(set) var isExternalOutput = false
    @Published private(set) var isBackingPlaying = false

    @Published var micGain: Double = 1.0 {
        didSet {
            engine.mainMixerNode.outputVolume = Float(min(max(micGain, 0), 1))
        }
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
    private var hasMicTap = false
    private var recoveryPending = false

    private var backingPlayer: AVAudioPlayer?
    private var oneShotPlayers: [UUID: AVAudioPlayer] = [:]

    private var routeObserver: NSObjectProtocol?
    private var engineConfigurationObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()

        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshRoute()
                self.scheduleLiveGraphRecovery()
            }
        }

        engineConfigurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleLiveGraphRecovery()
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
        if let engineConfigurationObserver { NotificationCenter.default.removeObserver(engineConfigurationObserver) }
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
                try configureLiveSession()
                try buildAndStartLiveGraph()

                isLive = true
                isStarting = false
                refreshRoute()
            } catch {
                stopEngineGraph()
                isStarting = false
                isLive = false
                errorMessage = "Live-Mikrofon konnte nicht gestartet werden: \(error.localizedDescription)"
            }
        }
    }

    func stopLive() {
        backingPlayer?.stop()
        backingPlayer = nil
        isBackingPlaying = false
        oneShotPlayers.removeAll()

        stopEngineGraph()

        micLevel = 0
        isLive = false
        isStarting = false
        recoveryPending = false

        try? session.overrideOutputAudioPort(.none)
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

            guard player.play() else {
                throw audioError("Die Audiodatei konnte nicht gestartet werden.")
            }

            backingPlayer = player
            isBackingPlaying = true
        } catch {
            errorMessage = "Backing-Track konnte nicht abgespielt werden: \(error.localizedDescription)"
        }
    }

    func restartBacking() {
        backingPlayer?.currentTime = 0
        if backingPlayer?.play() == true {
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

            guard player.play() else {
                throw audioError("Der Sound konnte nicht gestartet werden.")
            }

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
        if let input = session.currentRoute.inputs.first {
            inputName = input.portName
        } else {
            inputName = "iPhone-Mikrofon"
        }

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

    private func configureLiveSession() throws {
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.allowBluetoothA2DP, .allowAirPlay, .defaultToSpeaker]
        )

        try? session.setPreferredSampleRate(48_000)
        try? session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // A2DP is output-only. Prefer the iPhone microphone while keeping
        // a connected Bluetooth music speaker as the output route.
        if let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try? session.setPreferredInput(builtInMic)
        }

        // playAndRecord can otherwise fall back to the quiet receiver.
        if session.currentRoute.outputs.first?.portType == .builtInReceiver {
            try? session.overrideOutputAudioPort(.speaker)
        } else {
            try? session.overrideOutputAudioPort(.none)
        }

        refreshRoute()
    }

    private func buildAndStartLiveGraph() throws {
        stopEngineGraph()

        let input = engine.inputNode
        let mainMixer = engine.mainMixerNode
        let output = engine.outputNode

        let inputHardwareFormat = input.inputFormat(forBus: 0)
        let outputHardwareFormat = output.outputFormat(forBus: 0)

        guard inputHardwareFormat.sampleRate > 0,
              inputHardwareFormat.channelCount > 0 else {
            throw audioError("Das Mikrofon liefert aktuell kein verwendbares Audiosignal.")
        }

        guard outputHardwareFormat.sampleRate > 0,
              outputHardwareFormat.channelCount > 0 else {
            throw audioError("Die ausgewählte Audioausgabe ist aktuell nicht verfügbar.")
        }

        // Keep connection and tap formats nil so AVAudioEngine can follow
        // Bluetooth/sample-rate changes instead of holding stale hardware formats.
        engine.connect(input, to: mainMixer, format: nil)
        mainMixer.outputVolume = Float(min(max(micGain, 0), 1))

        input.installTap(onBus: 0, bufferSize: 512, format: nil) { [weak self] buffer, _ in
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

        guard engine.isRunning else {
            throw audioError("Die Audio-Engine wurde gestartet, läuft aber nicht.")
        }
    }

    private func stopEngineGraph() {
        if hasMicTap {
            engine.inputNode.removeTap(onBus: 0)
            hasMicTap = false
        }

        engine.stop()
        engine.disconnectNodeOutput(engine.inputNode)
    }

    private func scheduleLiveGraphRecovery() {
        guard isLive, !isStarting, !recoveryPending else { return }

        recoveryPending = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }

                self.recoveryPending = false
                guard self.isLive, !self.isStarting else { return }

                self.isStarting = true

                do {
                    try self.configureLiveSession()
                    try self.buildAndStartLiveGraph()
                    self.isStarting = false
                    self.refreshRoute()
                } catch {
                    self.stopEngineGraph()
                    self.isLive = false
                    self.isStarting = false
                    self.micLevel = 0
                    self.errorMessage = "Audioausgabe hat sich geändert und Live Mic konnte nicht neu verbunden werden: \(error.localizedDescription)"
                }
            }
        }
    }

    private func activateSessionForPlayback() throws {
        if !isLive {
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay])
            try session.setActive(true)
        }

        refreshRoute()
    }

    private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        if type == .began {
            stopEngineGraph()
            isLive = false
            isStarting = false
            isBackingPlaying = false
            micLevel = 0
        }
    }

    private func audioError(_ message: String) -> NSError {
        NSError(
            domain: "LiveMic.Audio",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
