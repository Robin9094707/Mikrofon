# Live Mic

Eine moderne iOS-Fun-App für Live-Mikrofon, Bluetooth-/AirPlay-Ausgabe, Backing-Tracks und ein eigenes Soundboard.

## Features

- Live-Mikrofon-Monitoring über AVAudioEngine
- Bluetooth A2DP, AirPlay, USB und kabelgebundene Audioausgabe
- Automatische Anzeige der aktuell verwendeten Audio-Route
- Echter Mikrofon-Pegelmesser und Mikrofon-Lautstärke
- MP3/Audio als Backing-Track importieren, Lautstärke einstellen, loopen und pausieren
- Eigenes Soundboard: Audio importieren, abspielen, umbenennen und löschen
- Persistente lokale Sound-Bibliothek
- Native SwiftUI-Oberfläche mit Apples Liquid Glass
- GitHub Actions Build für ein IPA-Artefakt

## Build

Das Projekt wird mit XcodeGen erzeugt:

```bash
brew install xcodegen
xcodegen generate
open Mikrofon.xcodeproj
```

Die GitHub Action erzeugt ein unsigned IPA. Für direkte Installation auf einem normalen iPhone muss die IPA anschließend mit einem gültigen Apple-Zertifikat signiert bzw. über einen passenden Sideloading-/Signing-Workflow installiert werden.

## Hinweis zu Bluetooth

Bluetooth-Audio hat technisch bedingte Latenz. Die App minimiert die lokale Audio-Pipeline, kann aber die zusätzliche Latenz eines Bluetooth-Lautsprechers nicht entfernen.

## 1.0.1

- Live-Mikrofon-Graph auf direkte InputNode → MainMixer → Output-Ausgabe umgestellt
- automatischer Neuaufbau der Audio-Engine bei Bluetooth-/Route-Wechsel
- Audioformate folgen der aktiven Hardware-Route automatisch
- Dateipicker lässt Dateien breit auswählen und validiert Audio anschließend
- MP3/M4A/WAV/AIFF-Import robuster
