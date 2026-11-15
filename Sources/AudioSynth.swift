import Foundation
import AVFoundation

enum MusicTrack: Int {
    case none = 0
    case titleMarch
    case strategyMap
    case fieldBattle
    case fortAssault
    case trainHeist
    case victoryFanfare
}

enum SoundEffect {
    case cannonFire
    case shellWhistle
    case explosionBridge
    case musketShot
    case cavalryBugle
    case punchSlapstick
    case dizzyBoing
    case trainChug
    case trainWhistle
    case goldChime
    case thunderClap
    case fortAlarm
    case flagCapture
    case menuMove
    case menuSelect
    case turnHorn
}

final class AudioSynth: @unchecked Sendable {
    static let shared = AudioSynth()

    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var sampleRate: Double = 44100.0

    private var currentTrack: MusicTrack = .titleMarch
    private var chipMode: AudioChipMode = .modernSynth
    private var musicVol: Double = 0.80
    private var sfxVol: Double = 0.85
    private var isPaused: Bool = false

    // Music Sequencer State
    private var beatPhase: Double = 0.0
    private var stepIndex: Int = 0
    private var leadPhase: Double = 0.0
    private var harmPhase: Double = 0.0
    private var bassPhase: Double = 0.0
    private var arpCounter: Int = 0
    private var noiseSeed: UInt32 = 0x1861_BEEF

    private struct ActiveVoice {
        var freqStart: Double
        var freqEnd: Double
        var duration: Double
        var elapsed: Double = 0
        var phase: Double = 0
        var gain: Double
        var noiseMix: Double
        var squareWave: Bool
        var vibratoHz: Double = 0
    }

    private var voices: [ActiveVoice] = []

    private init() {
        startRealtimeEngine()
    }

    private func startRealtimeEngine() {
        let eng = AVAudioEngine()
        let outFmt = eng.outputNode.inputFormat(forBus: 0)
        let sr = outFmt.sampleRate > 8000 ? outFmt.sampleRate : 44100.0
        self.sampleRate = sr

        let renderFmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        let node = AVAudioSourceNode(format: renderFmt) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let count = Int(frameCount)
            self.renderFrames(count: count, sampleRate: sr) { idx, l, r in
                if abl.count >= 2 {
                    abl[0].mData?.assumingMemoryBound(to: Float.self)[idx] = l
                    abl[1].mData?.assumingMemoryBound(to: Float.self)[idx] = r
                } else if abl.count == 1 {
                    let ptr = abl[0].mData?.assumingMemoryBound(to: Float.self)
                    ptr?[idx * 2] = l
                    ptr?[idx * 2 + 1] = r
                }
            }
            return noErr
        }

        eng.attach(node)
        eng.connect(node, to: eng.mainMixerNode, format: renderFmt)
        do {
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            #endif
            try eng.start()
            self.engine = eng
            self.sourceNode = node
        } catch {
            self.engine = nil
        }
    }

    func stopRealtimeEngineForOfflineRender() {
        lock.lock()
        engine?.stop()
        engine = nil
        sourceNode = nil
        voices.removeAll()
        beatPhase = 0
        stepIndex = 0
        lock.unlock()
    }

    func syncSettings(_ s: PlayerSettings) {
        lock.lock()
        chipMode = s.audioChip
        musicVol = Double(s.musicVolume)
        sfxVol = Double(s.sfxVolume)
        lock.unlock()
    }

    func setTrack(_ track: MusicTrack) {
        lock.lock()
        if currentTrack != track {
            currentTrack = track
            stepIndex = 0
            beatPhase = 0
        }
        lock.unlock()
    }

    func setPaused(_ paused: Bool) {
        lock.lock()
        isPaused = paused
        lock.unlock()
    }

    func trigger(_ sfx: SoundEffect) {
        lock.lock()
        defer { lock.unlock() }
        if voices.count > 20 { voices.removeFirst(4) }

        switch sfx {
        case .cannonFire:
            voices.append(ActiveVoice(freqStart: 150, freqEnd: 34, duration: 0.42, gain: 0.55, noiseMix: 0.72, squareWave: false))
            voices.append(ActiveVoice(freqStart: 95, freqEnd: 28, duration: 0.52, gain: 0.40, noiseMix: 0.45, squareWave: true))
        case .shellWhistle:
            voices.append(ActiveVoice(freqStart: 780, freqEnd: 360, duration: 0.34, gain: 0.22, noiseMix: 0.05, squareWave: false))
        case .explosionBridge:
            voices.append(ActiveVoice(freqStart: 120, freqEnd: 24, duration: 0.65, gain: 0.62, noiseMix: 0.85, squareWave: true))
        case .musketShot:
            voices.append(ActiveVoice(freqStart: 420, freqEnd: 95, duration: 0.12, gain: 0.30, noiseMix: 0.65, squareWave: true))
        case .cavalryBugle:
            let notes: [Double] = [523.25, 659.25, 783.99, 1046.50]
            for (i, n) in notes.enumerated() {
                voices.append(ActiveVoice(freqStart: n, freqEnd: n * 1.005, duration: 0.14 + Double(i) * 0.04, elapsed: -Double(i) * 0.09, gain: 0.32, noiseMix: 0.0, squareWave: true))
            }
        case .punchSlapstick:
            voices.append(ActiveVoice(freqStart: 290, freqEnd: 75, duration: 0.15, gain: 0.42, noiseMix: 0.45, squareWave: true))
        case .dizzyBoing:
            voices.append(ActiveVoice(freqStart: 260, freqEnd: 680, duration: 0.28, gain: 0.30, noiseMix: 0.0, squareWave: false, vibratoHz: 22.0))
        case .trainChug:
            voices.append(ActiveVoice(freqStart: 90, freqEnd: 60, duration: 0.11, gain: 0.25, noiseMix: 0.88, squareWave: false))
        case .trainWhistle:
            voices.append(ActiveVoice(freqStart: 587.33, freqEnd: 580.0, duration: 0.38, gain: 0.28, noiseMix: 0.08, squareWave: true))
            voices.append(ActiveVoice(freqStart: 739.99, freqEnd: 732.0, duration: 0.38, gain: 0.24, noiseMix: 0.08, squareWave: true))
        case .goldChime:
            voices.append(ActiveVoice(freqStart: 880, freqEnd: 880, duration: 0.12, gain: 0.30, noiseMix: 0.0, squareWave: true))
            voices.append(ActiveVoice(freqStart: 1318.5, freqEnd: 1318.5, duration: 0.22, elapsed: -0.09, gain: 0.32, noiseMix: 0.0, squareWave: true))
        case .thunderClap:
            voices.append(ActiveVoice(freqStart: 85, freqEnd: 22, duration: 0.75, gain: 0.50, noiseMix: 0.90, squareWave: false))
        case .fortAlarm:
            voices.append(ActiveVoice(freqStart: 660, freqEnd: 880, duration: 0.18, gain: 0.32, noiseMix: 0.05, squareWave: true))
        case .flagCapture:
            let triad: [Double] = [523.25, 659.25, 783.99, 1046.50]
            for (i, f) in triad.enumerated() {
                voices.append(ActiveVoice(freqStart: f, freqEnd: f, duration: 0.22, elapsed: -Double(i) * 0.08, gain: 0.34, noiseMix: 0.0, squareWave: true))
            }
        case .menuMove:
            voices.append(ActiveVoice(freqStart: 540, freqEnd: 620, duration: 0.055, gain: 0.20, noiseMix: 0.0, squareWave: true))
        case .menuSelect:
            voices.append(ActiveVoice(freqStart: 523.25, freqEnd: 783.99, duration: 0.13, gain: 0.28, noiseMix: 0.0, squareWave: true))
        case .turnHorn:
            voices.append(ActiveVoice(freqStart: 392.0, freqEnd: 523.25, duration: 0.24, gain: 0.30, noiseMix: 0.0, squareWave: true))
        }
    }

    func renderOfflineInterleavedInt16(frames: Int, sampleRate: Double) -> [Int16] {
        var out = [Int16](repeating: 0, count: frames * 2)
        renderFrames(count: frames, sampleRate: sampleRate) { idx, l, r in
            let cl = max(-1.0, min(1.0, Double(l)))
            let cr = max(-1.0, min(1.0, Double(r)))
            out[idx * 2] = Int16(cl * 30500.0)
            out[idx * 2 + 1] = Int16(cr * 30500.0)
        }
        return out
    }

    private func nextNoise() -> Double {
        noiseSeed = noiseSeed &* 1664525 &+ 1013904223
        return Double(Int32(bitPattern: noiseSeed)) / Double(Int32.max)
    }

    private static func midiHz(_ m: Int) -> Double {
        guard m > 0 else { return 0 }
        return 440.0 * pow(2.0, Double(m - 69) / 12.0)
    }

    // 16-step original comic-march / ragtime / battle patterns (MIDI notes)
    private static let titleLead:    [Int] = [72, 76, 79, 76, 84, 83, 81, 79, 77, 76, 74, 72, 74, 79, 76, 72]
    private static let titleBass:    [Int] = [48, 55, 48, 55, 53, 60, 55, 62, 53, 60, 50, 55, 48, 55, 43, 48]

    private static let mapLead:      [Int] = [67, 0,  72, 74, 76, 0,  74, 72, 69, 0,  72, 69, 67, 0,  64, 67]
    private static let mapBass:      [Int] = [48, 48, 55, 55, 45, 45, 52, 52, 53, 53, 48, 48, 43, 43, 48, 55]

    private static let battleLead:   [Int] = [69, 72, 76, 76, 79, 76, 72, 69, 71, 74, 79, 79, 81, 79, 76, 72]
    private static let battleBass:   [Int] = [45, 45, 52, 45, 45, 52, 48, 45, 43, 43, 50, 43, 45, 52, 45, 40]

    private static let fortLead:     [Int] = [76, 79, 81, 84, 81, 79, 76, 72, 74, 77, 79, 83, 79, 77, 74, 71]
    private static let fortBass:     [Int] = [48, 55, 52, 55, 48, 55, 52, 48, 43, 50, 47, 50, 43, 50, 47, 43]

    private static let trainLead:    [Int] = [72, 75, 76, 79, 84, 79, 76, 72, 74, 77, 78, 81, 83, 79, 74, 79]
    private static let trainBass:    [Int] = [48, 55, 52, 55, 48, 55, 52, 55, 50, 57, 54, 57, 43, 50, 47, 50]

    private static let victoryLead:  [Int] = [72, 76, 79, 84, 84, 86, 88, 84, 81, 84, 79, 76, 74, 79, 84, 84]
    private static let victoryBass:  [Int] = [48, 52, 55, 60, 53, 57, 60, 53, 55, 59, 62, 55, 48, 55, 48, 48]

    private func trackData(_ t: MusicTrack) -> (stepsPerSec: Double, lead: [Int], bass: [Int]) {
        switch t {
        case .none:           return (6.0, Self.mapLead, Self.mapBass)
        case .titleMarch:     return (7.4, Self.titleLead, Self.titleBass)
        case .strategyMap:    return (5.6, Self.mapLead, Self.mapBass)
        case .fieldBattle:    return (8.8, Self.battleLead, Self.battleBass)
        case .fortAssault:    return (9.6, Self.fortLead, Self.fortBass)
        case .trainHeist:     return (10.2, Self.trainLead, Self.trainBass)
        case .victoryFanfare: return (7.8, Self.victoryLead, Self.victoryBass)
        }
    }

    private func renderFrames(count: Int, sampleRate sr: Double, write: (Int, Float, Float) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        let dt = 1.0 / sr
        let (stepsPerSec, leadSeq, bassSeq) = trackData(currentTrack)
        let isSID = (chipMode == .c64SID)

        for i in 0..<count {
            var mixL = 0.0
            var mixR = 0.0

            if !isPaused && currentTrack != .none && musicVol > 0.001 {
                beatPhase += dt * stepsPerSec
                if beatPhase >= 1.0 {
                    beatPhase -= 1.0
                    stepIndex = (stepIndex + 1) % 16
                }
                arpCounter += 1

                let leadMidi = leadSeq[stepIndex]
                let bassMidi = bassSeq[stepIndex]
                let env = max(0.0, 1.0 - beatPhase * 0.72)

                // Voice 1: Lead (Brass/Fife in Modern, PWM + Arp in C64 SID)
                if leadMidi > 0 {
                    let arpOffset = isSID ? ([0, 4, 7][(arpCounter / 680) % 3]) : 0
                    let fLead = Self.midiHz(leadMidi + arpOffset)
                    leadPhase = fmod(leadPhase + fLead * dt, 1.0)
                    let wave: Double
                    if isSID {
                        wave = leadPhase < 0.34 ? 0.85 : -0.85
                    } else {
                        // Warm brassy saw + fundamental harmonic
                        let saw = (leadPhase * 2.0 - 1.0) * 0.55
                        let horn = sin(leadPhase * .pi * 2.0) * 0.55 + sin(leadPhase * .pi * 4.0) * 0.25
                        wave = (saw + horn) * 0.7
                    }
                    mixL += wave * env * 0.16 * musicVol
                    mixR += wave * env * 0.13 * musicVol
                }

                // Voice 2: Harmony / Ragtime Offbeat Chord
                if leadMidi > 0 && (stepIndex % 2 == 1) {
                    let fHarm = Self.midiHz(leadMidi - 5)
                    harmPhase = fmod(harmPhase + fHarm * dt, 1.0)
                    let hw = isSID ? (harmPhase < 0.5 ? 0.6 : -0.6) : sin(harmPhase * .pi * 2.0)
                    mixL += hw * env * 0.08 * musicVol
                    mixR += hw * env * 0.11 * musicVol
                }

                // Voice 3: Marching Tuba / SID Triangle-Saw Bass
                if bassMidi > 0 {
                    let fBass = Self.midiHz(bassMidi)
                    bassPhase = fmod(bassPhase + fBass * dt, 1.0)
                    let bw: Double
                    if isSID {
                        bw = abs(bassPhase * 4.0 - 2.0) - 1.0
                    } else {
                        bw = sin(bassPhase * .pi * 2.0) * 0.75 + (bassPhase < 0.5 ? 0.25 : -0.25)
                    }
                    let bassEnv = max(0.0, 1.0 - beatPhase * 0.85)
                    mixL += bw * bassEnv * 0.17 * musicVol
                    mixR += bw * bassEnv * 0.17 * musicVol
                }

                // Military Snare / Train Chug Percussion
                if beatPhase < 0.18 && (stepIndex % 2 == 1 || currentTrack == .trainHeist) {
                    let n = nextNoise() * (1.0 - beatPhase / 0.18)
                    let snareGain = (currentTrack == .trainHeist ? 0.09 : 0.065) * musicVol
                    mixL += n * snareGain
                    mixR += n * snareGain
                }
            }

            // Active Sound Effects
            if !voices.isEmpty && sfxVol > 0.001 {
                var vIdx = voices.count - 1
                while vIdx >= 0 {
                    voices[vIdx].elapsed += dt
                    let el = voices[vIdx].elapsed
                    let dur = voices[vIdx].duration
                    if el >= dur {
                        voices.remove(at: vIdx)
                    } else if el >= 0 {
                        let t = el / max(0.001, dur)
                        let baseF = voices[vIdx].freqStart + (voices[vIdx].freqEnd - voices[vIdx].freqStart) * t
                        let vib = voices[vIdx].vibratoHz > 0 ? (1.0 + 0.08 * sin(el * voices[vIdx].vibratoHz * .pi * 2.0)) : 1.0
                        let freq = max(18.0, baseF * vib)
                        voices[vIdx].phase = fmod(voices[vIdx].phase + freq * dt, 1.0)
                        let tone: Double
                        if voices[vIdx].squareWave || isSID {
                            tone = voices[vIdx].phase < 0.45 ? 0.9 : -0.9
                        } else {
                            tone = sin(voices[vIdx].phase * .pi * 2.0)
                        }
                        let nz = nextNoise()
                        let mixed = tone * (1.0 - voices[vIdx].noiseMix) + nz * voices[vIdx].noiseMix
                        let amp = (1.0 - t) * voices[vIdx].gain * sfxVol * 0.55
                        mixL += mixed * amp
                        mixR += mixed * amp
                    }
                    vIdx -= 1
                }
            }

            let outL = Float(tanh(mixL))
            let outR = Float(tanh(mixR))
            write(i, outL, outR)
        }
    }
}
