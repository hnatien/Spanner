import Foundation

/// One app's volume setting in the mixer, remembered by bundle ID.
public struct AppVolume: Codable, Equatable, Sendable {
    /// Slider position, 0...1.
    public var level: Double
    public var isMuted: Bool

    public init(level: Double = 1, isMuted: Bool = false) {
        self.level = min(max(level, 0), 1)
        self.isMuted = isMuted
    }

    /// Linear gain applied to samples. The slider is squared so equal slider
    /// steps sound like roughly equal loudness steps.
    public var gain: Float {
        isMuted ? 0 : Float(level * level)
    }

    /// Full volume and unmuted: the app needs no tap at all.
    public var isUnity: Bool { !isMuted && level >= 1 }
}

/// Per-sample gain smoothing for the real-time audio callback, so slider
/// moves don't click. Moves `current` toward `target` over ~30 ms.
public struct GainRamp: Sendable {
    public private(set) var current: Float
    private let step: Float

    public init(initial: Float, sampleRate: Double, rampSeconds: Double = 0.03) {
        current = initial
        step = Float(1 / max(sampleRate * rampSeconds, 1))
    }

    /// Gain for the next frame.
    public mutating func next(toward target: Float) -> Float {
        let delta = target - current
        if abs(delta) <= step {
            current = target
        } else {
            current += delta > 0 ? step : -step
        }
        return current
    }
}
