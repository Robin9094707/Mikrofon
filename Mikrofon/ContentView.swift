import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var audio: LiveAudioEngine
    @EnvironmentObject private var library: SoundLibrary

    @State private var importingBacking = false
    @State private var importingSound = false
    @State private var editingSound: SoundClip?

    var body: some View {
        NavigationStack {
            ZStack {
                StageBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        header
                        liveMicCard
                        backingCard
                        soundboardCard
                        tipsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 36)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarHidden(true)
        }
        .fileImporter(
            isPresented: $importingBacking,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false,
            onCompletion: handleBackingImport
        )
        .fileImporter(
            isPresented: $importingSound,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false,
            onCompletion: handleSoundImport
        )
        .sheet(item: $editingSound) { clip in
            RenameSoundSheet(sound: clip)
                .environmentObject(library)
                .presentationDetents([.height(270)])
        }
        .alert(
            "Live Mic",
            isPresented: Binding(
                get: { audio.errorMessage != nil },
                set: { visible in if !visible { audio.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(audio.errorMessage ?? "")
        }
        .onAppear {
            audio.refreshRoute()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LIVE MIC")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .tracking(1.2)

                Text("Mic · Music · Soundboard")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            RoutePickerView()
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("Audioausgabe auswählen")
        }
        .padding(.horizontal, 4)
    }

    private var liveMicCard: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(audio.isLive ? Color.green.opacity(0.18) : Color.white.opacity(0.08))
                        .frame(width: 62, height: 62)

                    Image(systemName: audio.isLive ? "mic.fill" : "mic.slash.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(audio.isLive ? .green : .secondary)
                        .symbolEffect(.pulse, isActive: audio.isLive)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(audio.isLive ? "Mikrofon ist LIVE" : "Live-Mikrofon")
                        .font(.title3.bold())

                    HStack(spacing: 6) {
                        Circle()
                            .fill(audio.isExternalOutput ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)

                        Text(audio.outputName)
                            .lineLimit(1)
                            .font(.subheadline.weight(.semibold))
                    }

                    Text(audio.outputDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            LevelMeter(level: audio.micLevel)

            VStack(spacing: 8) {
                HStack {
                    Label("Mikrofon-Lautstärke", systemImage: "waveform")
                    Spacer()
                    Text("\(Int(audio.micGain * 100)) %")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.semibold))

                Slider(value: $audio.micGain, in: 0...1.5)
                    .tint(.green)
            }

            Button {
                audio.toggleLive()
            } label: {
                HStack(spacing: 10) {
                    if audio.isStarting {
                        ProgressView()
                    } else {
                        Image(systemName: audio.isLive ? "stop.fill" : "mic.fill")
                    }

                    Text(audio.isLive ? "Live beenden" : "LIVE starten")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(audio.isLive ? .glass : .glassProminent)
            .tint(audio.isLive ? .red : .green)
            .disabled(audio.isStarting)

            Text("Bluetooth-Lautsprecher funktionieren über A2DP. Bluetooth selbst kann hörbare Verzögerung verursachen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassPanel()
    }

    private var backingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Backing Track", systemImage: "music.note")
                    .font(.headline)

                Spacer()

                Button {
                    importingBacking = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.glass)
            }

            if let url = library.backingTrackURL {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(library.backingTrackName ?? "Backing Track")
                                .fontWeight(.semibold)
                                .lineLimit(1)

                            Text("Läuft zusammen mit deinem Live-Mikro")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    HStack(spacing: 10) {
                        Button {
                            audio.playOrPauseBacking(url: url)
                        } label: {
                            Label(
                                audio.isBackingPlaying ? "Pause" : "Abspielen",
                                systemImage: audio.isBackingPlaying ? "pause.fill" : "play.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)

                        Button {
                            audio.restartBacking()
                        } label: {
                            Image(systemName: "backward.end.fill")
                        }
                        .buttonStyle(.glass)

                        Button(role: .destructive) {
                            audio.stopBacking()
                            library.clearBackingTrack()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.glass)
                    }

                    VStack(spacing: 8) {
                        HStack {
                            Text("Musik")
                            Spacer()
                            Text("\(Int(audio.backingVolume * 100)) %")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline.weight(.semibold))

                        Slider(value: $audio.backingVolume, in: 0...1)
                    }

                    Toggle(isOn: $audio.backingLoops) {
                        Label("Endlosschleife", systemImage: "repeat")
                    }
                    .font(.subheadline.weight(.semibold))
                }
            } else {
                Button {
                    importingBacking = true
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title2)
                        Text("MP3 oder Audiodatei importieren")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }
                .buttonStyle(.glass)
            }
        }
        .glassPanel()
    }

    private var soundboardCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Soundboard", systemImage: "square.grid.2x2.fill")
                    .font(.headline)

                Spacer()

                Button {
                    importingSound = true
                } label: {
                    Label("Sound", systemImage: "plus")
                }
                .buttonStyle(.glass)
            }

            if library.sounds.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 34))
                    Text("Noch keine Sounds")
                        .font(.headline)
                    Text("Importiere kurze MP3-, M4A- oder WAV-Dateien und löse sie während des Live-Mikros direkt aus.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(library.sounds) { sound in
                        Button {
                            audio.playSound(url: library.url(for: sound))
                        } label: {
                            VStack(spacing: 9) {
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                Text(sound.name)
                                    .font(.subheadline.weight(.bold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 86)
                        }
                        .buttonStyle(.glass)
                        .contextMenu {
                            Button {
                                editingSound = sound
                            } label: {
                                Label("Umbenennen", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                library.delete(sound)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                }

                VStack(spacing: 8) {
                    HStack {
                        Text("Sound-Lautstärke")
                        Spacer()
                        Text("\(Int(audio.soundVolume * 100)) %")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline.weight(.semibold))

                    Slider(value: $audio.soundVolume, in: 0...1)
                }

                Text("Tipp: Sound-Knopf länger gedrückt halten → Umbenennen oder Löschen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .glassPanel()
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Für die beste Party", systemImage: "sparkles")
                .font(.headline)

            Text("Lautsprecher zuerst in iOS verbinden, dann LIVE starten. Für Karaoke: Backing Track auswählen, Musiklautstärke einstellen und anschließend das Mikro aktivieren.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Bei sehr lauten Lautsprechern Abstand zum iPhone halten, sonst kann akustisches Feedback/Pfeifen entstehen.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .glassPanel()
    }

    private func handleBackingImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try library.importBackingTrack(from: url)
        } catch {
            audio.presentError("Import fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func handleSoundImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try library.importSound(from: url)
        } catch {
            audio.presentError("Sound konnte nicht importiert werden: \(error.localizedDescription)")
        }
    }
}

private struct StageBackground: View {
    var body: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.50),
                    Color.black.opacity(0.15),
                    Color.mint.opacity(0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.purple.opacity(0.30), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }
}

private struct LevelMeter: View {
    let level: Double

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<18, id: \.self) { index in
                let threshold = Double(index + 1) / 18.0
                Capsule()
                    .fill(level >= threshold ? Color.green : Color.white.opacity(0.13))
                    .frame(maxWidth: .infinity)
                    .frame(height: 18 + CGFloat(index % 4) * 4)
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .frame(height: 34)
        .accessibilityElement()
        .accessibilityLabel("Mikrofonpegel")
        .accessibilityValue("\(Int(level * 100)) Prozent")
    }
}

private struct RenameSoundSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: SoundLibrary

    let sound: SoundClip
    @State private var name: String

    init(sound: SoundClip) {
        self.sound = sound
        _name = State(initialValue: sound.name)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Sound umbenennen")
                    .font(.title2.bold())

                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(save)

                Button("Speichern", action: save)
                    .buttonStyle(.glassProminent)
                    .frame(maxWidth: .infinity)

                Spacer()
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private func save() {
        library.rename(sound, to: name)
        dismiss()
    }
}

private extension View {
    func glassPanel() -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity)
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
    }
}
