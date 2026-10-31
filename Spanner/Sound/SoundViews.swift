import AppKit
import CoreAudio
import SpannerCore
import SwiftUI

/// Main-window page for sound.
struct SoundPage: View {
    @Environment(SoundController.self) private var sound

    var body: some View {
        @Bindable var settings = sound.settings
        Page {
            PageHeader(title: "Sound",
                       subtitle: "Turn individual apps up or down, switch devices, and mute your microphone from anywhere.",
                       symbol: AppSection.sound.symbol, tint: FeatureTint.sound)

            SettingsGroup(title: "Devices") {
                SettingsRow(title: "Output", symbol: sound.defaultOutput?.symbol ?? "speaker.wave.2.fill", tint: FeatureTint.sound) {
                    DevicePicker(devices: sound.outputDevices, selection: sound.defaultOutputID, select: sound.selectOutput)
                }
                SettingsRow(title: "Input", symbol: "mic.fill", tint: .orange) {
                    DevicePicker(devices: sound.inputDevices, selection: sound.defaultInputID, select: sound.selectInput)
                }
            }

            MixerGroup()

            SettingsGroup(title: "Microphone",
                          footer: sound.micShortcutUnavailable ? "Another app already uses this shortcut. Pick a different one." : nil) {
                SettingsRow(title: sound.isMicMuted ? "Microphone is muted" : "Microphone is on",
                            subtitle: sound.defaultInput?.name,
                            symbol: sound.isMicMuted ? "mic.slash.fill" : "mic.fill",
                            tint: sound.isMicMuted ? .red : .green) {
                    Button(sound.isMicMuted ? "Unmute" : "Mute") { sound.toggleMicMute() }
                        .disabled(sound.defaultInputID == nil)
                }
                SettingsRow(title: "Mute shortcut", subtitle: "Works in every app, including during calls.",
                            symbol: "keyboard", tint: .gray) {
                    ShortcutRecorder(shortcut: $settings.micMuteShortcut)
                }
                SettingsRow(title: "Show on screen when toggled", symbol: "rectangle.badge.checkmark", tint: .gray) {
                    Toggle("Show on screen when toggled", isOn: $settings.showsMicMuteHUD)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
        .onAppear { sound.isMixerVisible = true }
        .onDisappear { sound.isMixerVisible = false }
    }
}

private struct DevicePicker: View {
    let devices: [AudioDevice]
    let selection: AudioObjectID?
    let select: (AudioDevice) -> Void

    var body: some View {
        Picker("Device", selection: Binding(get: { selection ?? 0 },
                                            set: { id in devices.first { $0.id == id }.map(select) })) {
            ForEach(devices) { Text($0.name).tag($0.id) }
        }
        .labelsHidden()
        .fixedSize()
        .disabled(devices.isEmpty)
    }
}

private struct MixerGroup: View {
    @Environment(SoundController.self) private var sound
    @Environment(PermissionsManager.self) private var permissions

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            MissingPermissionsGroup(needed: [.systemAudio],
                                    footer: "macOS lists this under Screen & System Audio Recording. Spanner only adjusts the level; nothing is recorded.")
            SettingsGroup(title: "Volume by app", footer: footer) {
                if sound.mixerApps.isEmpty {
                    EmptyStateView(symbol: "speaker.slash", title: "Nothing is playing",
                                   message: "Apps appear here while they play sound.")
                } else {
                    ForEach(sound.mixerApps) { app in
                        MixerRow(app: app)
                    }
                }
            }
            .disabled(!permissions.systemAudioGranted)
            if let error = sound.mixerError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if !sound.settings.volumes.isEmpty {
                Button("Reset All to Full Volume") { sound.resetVolumes() }
                    .padding(.horizontal, Spacing.xs)
            }
        }
    }

    private var footer: String {
        "Levels are relative to the system volume and remembered per app. Apps you've turned down stay listed while they run."
    }
}

/// Icon, name, mute button and slider for one app. Used by the Sound page
/// and the menu bar panel.
struct MixerRow: View {
    @Environment(SoundController.self) private var sound
    let app: MixerApp
    var compact = false

    var body: some View {
        let volume = sound.volume(for: app)
        HStack(spacing: Spacing.m) {
            AppIcon(path: app.bundlePath, size: compact ? 20 : 24)
            if !compact {
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).lineLimit(1)
                    Text(app.isPlaying ? "Playing" : "Quiet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 150, alignment: .leading)
            }
            Button {
                sound.setVolume(AppVolume(level: volume.level, isMuted: !volume.isMuted), for: app)
            } label: {
                Image(systemName: volume.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 18)
                    .foregroundStyle(volume.isMuted ? .red : .secondary)
            }
            .buttonStyle(.borderless)
            .help(volume.isMuted ? "Unmute \(app.name)" : "Mute \(app.name)")
            Slider(value: Binding(get: { volume.level },
                                  set: { sound.setVolume(AppVolume(level: $0, isMuted: false), for: app) }),
                   in: 0...1) {
                Text("\(app.name) volume")
            }
            .labelsHidden()
            .controlSize(compact ? .small : .regular)
            Text(volume.isMuted ? "Muted" : "\(Int((volume.level * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .help(compact ? app.name : "")
    }
}

private struct AppIcon: View {
    let path: String?
    let size: CGFloat

    var body: some View {
        Image(nsImage: path.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSWorkspace.shared.icon(for: .application))
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Compact sound controls for the menu bar panel: output device, mic mute
/// and the apps playing right now.
struct SoundMenuSection: View {
    @Environment(SoundController.self) private var sound
    @Environment(PermissionsManager.self) private var permissions

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                SymbolTile(symbol: sound.defaultOutput?.symbol ?? "speaker.wave.2.fill", tint: FeatureTint.sound, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sound").font(.callout.weight(.medium))
                    Menu(sound.defaultOutput?.name ?? "No output") {
                        ForEach(sound.outputDevices) { device in
                            Button {
                                sound.selectOutput(device)
                            } label: {
                                if device.id == sound.defaultOutputID {
                                    Label(device.name, systemImage: "checkmark")
                                } else {
                                    Text(device.name)
                                }
                            }
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                }
                Spacer(minLength: Spacing.s)
                Button {
                    sound.toggleMicMute()
                } label: {
                    Image(systemName: sound.isMicMuted ? "mic.slash.fill" : "mic.fill")
                        .foregroundStyle(sound.isMicMuted ? .red : .primary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(sound.defaultInputID == nil)
                .help(sound.isMicMuted ? "Unmute microphone" : "Mute microphone")
            }
            if permissions.systemAudioGranted {
                ForEach(sound.mixerApps.prefix(4)) { app in
                    MixerRow(app: app, compact: true)
                }
            }
        }
        .onAppear { sound.isMixerVisible = true }
        .onDisappear { sound.isMixerVisible = false }
    }
}
