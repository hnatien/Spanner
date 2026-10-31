import CoreAudio
import Foundation
import OSLog
import SpannerCore
import Synchronization

/// Changes one app's volume with a Core Audio process tap (macOS 14.2+).
///
/// The tap captures the app's processes and mutes their normal output
/// (`mutedWhenTapped`). A private aggregate device pairs the tap with the
/// current output device, and its IO callback copies the captured audio to
/// the output with gain applied. Destroying the tap, or Spanner quitting or
/// crashing, unmutes the app, since taps belong to the process that made them.
///
/// The pipeline follows Apple's "Capturing system audio with Core Audio
/// taps" sample and the pitfalls documented by Mimir (see the Phase 2 notes):
/// rebuild when the output device changes, ramp gain to avoid clicks, and
/// keep the real-time callback free of allocation and locks.
final class AppVolumeTap {
    enum TapError: Error, CustomStringConvertible {
        case createTap(OSStatus), createAggregate(OSStatus), createIOProc(OSStatus), start(OSStatus)

        var description: String {
            switch self {
            case .createTap(let status): "AudioHardwareCreateProcessTap failed (\(status))"
            case .createAggregate(let status): "AudioHardwareCreateAggregateDevice failed (\(status))"
            case .createIOProc(let status): "AudioDeviceCreateIOProcIDWithBlock failed (\(status))"
            case .start(let status): "AudioDeviceStart failed (\(status))"
            }
        }
    }

    let processes: Set<AudioObjectID>
    let outputUID: String

    private let gain: GainBox
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private static let log = Logger(subsystem: "dev.spanner.Spanner", category: "Sound")

    init(processes: Set<AudioObjectID>, outputUID: String, gain: Float) throws {
        self.processes = processes
        self.outputUID = outputUID
        self.gain = GainBox(gain)
        do {
            try build()
        } catch {
            invalidate()
            throw error
        }
    }

    func setGain(_ value: Float) {
        gain.store(value)
    }

    /// Stops audio and releases the tap, which unmutes the app.
    func invalidate() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private func build() throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processes.sorted())
        description.uuid = UUID()
        description.name = "Spanner Volume"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw TapError.createTap(status) }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Spanner Volume",
            kAudioAggregateDeviceUIDKey: AudioHardware.ownDevicePrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { throw TapError.createAggregate(status) }

        let sampleRate = AudioHardware.get(aggregateID, kAudioDevicePropertyNominalSampleRate, as: Float64.self) ?? 48_000
        let block = Self.makeIOBlock(gain: gain, sampleRate: sampleRate)
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil, block)
        guard status == noErr, let procID else { throw TapError.createIOProc(status) }

        // A new aggregate device can take a moment to become startable.
        for attempt in 0..<5 {
            status = AudioDeviceStart(aggregateID, procID)
            if status == noErr { return }
            Self.log.debug("AudioDeviceStart attempt \(attempt) failed: \(status)")
            usleep(20_000)
        }
        throw TapError.start(status)
    }

    /// Built outside the main actor so the block isn't main-actor isolated:
    /// it runs on Core Audio's real-time IO thread.
    private nonisolated static func makeIOBlock(gain: GainBox, sampleRate: Double) -> AudioDeviceIOBlock {
        let state = RenderState(ramp: GainRamp(initial: gain.load(), sampleRate: sampleRate))
        return { _, input, _, output, _ in
            render(input: input, output: output, target: gain.load(), state: state)
        }
    }

    /// Copies the tap's stereo mixdown to every output channel with gain.
    /// Handles interleaved and non-interleaved Float32 buffers on both sides.
    private nonisolated static func render(input: UnsafePointer<AudioBufferList>,
                                           output: UnsafeMutablePointer<AudioBufferList>,
                                           target: Float, state: RenderState) {
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))

        // Locate the left and right input channels as (pointer, stride).
        var left: (UnsafePointer<Float>, Int)?
        var right: (UnsafePointer<Float>, Int)?
        var inputFrames = Int.max
        for buffer in inputs {
            guard let data = buffer.mData, buffer.mNumberChannels > 0 else { continue }
            let channels = Int(buffer.mNumberChannels)
            let samples = data.assumingMemoryBound(to: Float.self)
            inputFrames = min(inputFrames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels)
            for channel in 0..<channels {
                let entry = (UnsafePointer(samples + channel), channels)
                if left == nil { left = entry } else if right == nil { right = entry }
            }
        }

        for buffer in outputs {
            guard let data = buffer.mData else { continue }
            memset(data, 0, Int(buffer.mDataByteSize))
        }
        guard let left else { return }
        let source = (left, right ?? left)

        var outputFrames = Int.max
        for buffer in outputs where buffer.mNumberChannels > 0 {
            outputFrames = min(outputFrames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / Int(buffer.mNumberChannels))
        }
        let frames = min(inputFrames, outputFrames)
        guard frames > 0, frames != .max else { return }

        for frame in 0..<frames {
            let gain = state.ramp.next(toward: target)
            let l = source.0.0[frame * source.0.1] * gain
            let r = source.1.0[frame * source.1.1] * gain
            var outputChannel = 0
            for buffer in outputs {
                guard let data = buffer.mData else { continue }
                let channels = Int(buffer.mNumberChannels)
                let samples = data.assumingMemoryBound(to: Float.self)
                for channel in 0..<channels {
                    // Even channels get left, odd get right (stereo pairs).
                    samples[frame * channels + channel] = outputChannel % 2 == 0 ? l : r
                    outputChannel += 1
                }
            }
        }
    }
}

/// Target gain shared between the main thread (writer) and the IO thread
/// (reader), as atomic Float bits so the callback never takes a lock.
private nonisolated final class GainBox: Sendable {
    private let bits: Atomic<UInt32>

    init(_ value: Float) {
        bits = Atomic(value.bitPattern)
    }

    nonisolated func load() -> Float {
        Float(bitPattern: bits.load(ordering: .relaxed))
    }

    nonisolated func store(_ value: Float) {
        bits.store(value.bitPattern, ordering: .relaxed)
    }
}

/// Ramp state touched only by the IO thread.
private nonisolated final class RenderState: @unchecked Sendable {
    nonisolated(unsafe) var ramp: GainRamp

    nonisolated init(ramp: GainRamp) {
        self.ramp = ramp
    }
}
