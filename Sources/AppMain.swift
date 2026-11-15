#if os(macOS)
import AppKit
import SpriteKit
import GameController
import AVFoundation
import CoreMedia
import CoreVideo
import CoreText

@MainActor
final class InteractiveSKView: SKView {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        scene?.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        scene?.keyUp(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        scene?.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        scene?.rightMouseDown(with: event)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var skView: InteractiveSKView!
    private var gameScene: GameScene!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()

        let contentRect = NSRect(x: 0, y: 0, width: 1280, height: 800)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Iron Rails: Blue & Gray"
        window.minSize = NSSize(width: 960, height: 600)
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenPrimary]
        window.delegate = self
        window.center()

        skView = InteractiveSKView(frame: contentRect)
        skView.autoresizingMask = [.width, .height]
        skView.ignoresSiblingOrder = true
        skView.preferredFramesPerSecond = 120
        window.contentView = skView

        gameScene = GameScene(size: CGSize(width: 1280, height: 800))
        gameScene.scaleMode = .aspectFill
        skView.presentScene(gameScene)

        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--export-appstore-screenshots"), idx + 1 < args.count {
            ScreenshotSuiteExporter.exportAll(skView: skView, scene: gameScene, rootDir: args[idx + 1])
            exit(0)
        }
        if let idx = args.firstIndex(of: "--render-trailers"), idx + 1 < args.count {
            VideoSuiteExporter.renderLaunchTrailers(skView: skView, scene: gameScene, outputDir: args[idx + 1])
            exit(0)
        }
        if let idx = args.firstIndex(of: "--render-review-walkthrough"), idx + 1 < args.count {
            VideoSuiteExporter.renderAppReviewWalkthrough(skView: skView, scene: gameScene, outputFile: args[idx + 1])
            exit(0)
        }

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(skView)
        NSApplication.shared.activate(ignoringOtherApps: true)

        GCController.startWirelessControllerDiscovery {}

        if PersistenceManager.shared.data.settings.launchFullscreen {
            window.toggleFullScreen(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // 1. App Menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Iron Rails: Blue & Gray", action: #selector(showAboutPanel), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Iron Rails", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Iron Rails", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // 2. Campaign & Skirmish Menu
        let gameItem = NSMenuItem()
        mainMenu.addItem(gameItem)
        let gameMenu = NSMenu(title: "Campaign")
        gameItem.submenu = gameMenu
        gameMenu.addItem(withTitle: "New 1861 Continental Campaign", action: #selector(newCampaignAction), keyEquivalent: "n")
        gameMenu.addItem(withTitle: "Quick River-Bridge Field Battle", action: #selector(quickBattleAction), keyEquivalent: "b")
        gameMenu.addItem(withTitle: "Quick Steam Train Heist", action: #selector(quickTrainAction), keyEquivalent: "t")
        gameMenu.addItem(withTitle: "Quick Fort Assault", action: #selector(quickFortAction), keyEquivalent: "r")
        gameMenu.addItem(.separator())
        gameMenu.addItem(withTitle: "Pause / Resume", action: #selector(pauseAction), keyEquivalent: "p")
        gameMenu.addItem(withTitle: "Return to Command Tent", action: #selector(titleAction), keyEquivalent: "")

        // 3. Retro & AV Menu
        let retroItem = NSMenuItem()
        mainMenu.addItem(retroItem)
        let retroMenu = NSMenu(title: "Retro & AV")
        retroItem.submenu = retroMenu
        retroMenu.addItem(withTitle: "Cycle Visual Era (2026 HD Comic / CRT / 1989 C64)", action: #selector(cycleVisualsAction), keyEquivalent: "1")
        retroMenu.addItem(withTitle: "Cycle Audio Synth (Brass & Ragtime / C64 SID 6581)", action: #selector(cycleAudioAction), keyEquivalent: "2")

        // 4. View Menu
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(toggleFullscreenAction), keyEquivalent: "f")
        viewMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc private func showAboutPanel() {
        let alert = NSAlert()
        alert.messageText = "Iron Rails: Blue & Gray (v1.0.0)"
        alert.informativeText = """
        A comic-arcade continental railroad strategy & real-time action game inspired by the beloved 1989 Commodore 64 / Amiga classic.

        • 1861–1864 Strategic Territory & Railroad Map (Paymaster Gold Express, Clipper Ship Reinforcements & Storm Clouds)
        • Real-Time River-Bridge Field Battles (Artillery Range Gauge, Cavalry Saber Charges & Infantry Volleys)
        • Side-Scrolling Moving Steam Train Heists & 60-Second Timber Fort Assaults
        • Live 1989 ↔ 2026 Time-Machine: Switch instantly between 120Hz HD Comic Art & Authentic 16-Color C64 + MOS 6581 SID

        © 2026 NGD. 100% Original Code, Artwork & Procedural Audio.
        """
        alert.runModal()
    }

    @objc private func newCampaignAction()  { gameScene?.startNewCampaign(year: .y1861, playerMode: .unionVsAI, difficulty: .colonel) }
    @objc private func quickBattleAction()  { gameScene?.startFieldBattle(attacker: .veteran(for: .unionBlue), defender: .veteran(for: .grayCorps), humanFaction: .unionBlue) }
    @objc private func quickTrainAction()   { gameScene?.startTrainHeist(raider: .unionBlue, trainOwner: .grayCorps) }
    @objc private func quickFortAction()    { gameScene?.startFortAssault(attacker: .unionBlue, defender: .grayCorps) }
    @objc private func pauseAction()        { gameScene?.togglePauseFromUI() }
    @objc private func titleAction()        { gameScene?.enterTitleMenu() }
    @objc private func cycleVisualsAction() { gameScene?.cycleVisualTheme() }
    @objc private func cycleAudioAction()   { gameScene?.cycleAudioChip() }
    @objc private func toggleFullscreenAction() { window?.toggleFullScreen(nil) }
}

@main
struct IronRailsMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

// MARK: - Automated Retina App Store Screenshot Suite (Mac 2560x1600, iPhone 2796x1290, iPad 2732x2048)

@MainActor
enum ScreenshotSuiteExporter {
    static func exportAll(skView: SKView, scene: GameScene, rootDir: String) {
        let fm = FileManager.default
        let macDir    = URL(fileURLWithPath: rootDir).appendingPathComponent("Mac_2560x1600", isDirectory: true)
        let iphoneDir = URL(fileURLWithPath: rootDir).appendingPathComponent("iPhone_67_2796x1290", isDirectory: true)
        let ipadDir   = URL(fileURLWithPath: rootDir).appendingPathComponent("iPad_129_2732x2048", isDirectory: true)
        try? fm.createDirectory(at: macDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: iphoneDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: ipadDir, withIntermediateDirectories: true)

        AudioSynth.shared.stopRealtimeEngineForOfflineRender()

        let slugs = [
            "01_river_bridge_field_battle",
            "02_paymaster_train_heist",
            "03_continental_railway_map",
            "04_timber_fort_assault",
            "05_c64_1989_retro_sid_mode",
            "06_command_tent_title"
        ]

        for i in 1...6 {
            scene.stageAppStoreScreenshot(index: i, isMobile: false)
            guard let tex = skView.texture(from: scene) else { continue }
            let cg = tex.cgImage()

            let showTouchHUD = (i == 1 || i == 2 || i == 4 || i == 5)
            let isActionRunner = (i == 2 || i == 4)
            let name = "\(slugs[i - 1]).jpg"

            saveCompositedJPEG(sceneCG: cg, width: 2560, height: 1600, includeTouchHUD: false, isRunner: isActionRunner, to: macDir.appendingPathComponent(name))
            saveCompositedJPEG(sceneCG: cg, width: 2796, height: 1290, includeTouchHUD: showTouchHUD, isRunner: isActionRunner, to: iphoneDir.appendingPathComponent(name))
            saveCompositedJPEG(sceneCG: cg, width: 2732, height: 2048, includeTouchHUD: showTouchHUD, isRunner: isActionRunner, to: ipadDir.appendingPathComponent(name))
        }

        PersistenceManager.shared.updateSettings {
            $0.visualTheme = .hdOverdrive
            $0.audioChip = .modernSynth
        }
        print("[ScreenshotSuiteExporter] Exported 18 Retina App Store screenshots to \(rootDir)")
        fflush(stdout)
    }

    private static func saveCompositedJPEG(sceneCG: CGImage, width: Int, height: Int, includeTouchHUD: Bool, isRunner: Bool, to url: URL) {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return }

        ctx.interpolationQuality = .high
        // Aspect-FILL 1280x800 (all UI sits inside universal safe box x: 145..1135, y: 135..665)
        let scale = max(CGFloat(width) / 1280.0, CGFloat(height) / 800.0)
        let dw = 1280.0 * scale
        let dh = 800.0 * scale
        let dx = (CGFloat(width) - dw) * 0.5
        let dy = (CGFloat(height) - dh) * 0.5
        ctx.draw(sceneCG, in: CGRect(x: dx, y: dy, width: dw, height: dh))

        if includeTouchHUD {
            drawMobileTouchControlsPreview(ctx: ctx, width: CGFloat(width), height: CGFloat(height), isRunner: isRunner)
        }

        guard let outCG = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: outCG)
        if let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.94]) {
            try? jpg.write(to: url)
        }
    }

    private static func drawMobileTouchControlsPreview(ctx: CGContext, width: CGFloat, height: CGFloat, isRunner: Bool) {
        let brass = NSColor(calibratedRed: 1.0, green: 0.83, blue: 0.28, alpha: 0.85)
        let crimson = NSColor(calibratedRed: 0.88, green: 0.25, blue: 0.22, alpha: 0.82)
        let blue = NSColor(calibratedRed: 0.16, green: 0.45, blue: 0.92, alpha: 0.82)
        let darkFill = NSColor(calibratedRed: 0.05, green: 0.09, blue: 0.18, alpha: 0.55)

        let stickR = min(130, height * 0.095)
        let stickRect = CGRect(x: 84, y: 68, width: stickR * 2, height: stickR * 2)
        ctx.setFillColor(darkFill.cgColor)
        ctx.fillEllipse(in: stickRect)
        ctx.setStrokeColor(brass.cgColor)
        ctx.setLineWidth(4.5)
        ctx.strokeEllipse(in: stickRect)

        let knobR = stickR * 0.42
        ctx.setFillColor(brass.withAlphaComponent(0.75).cgColor)
        ctx.fillEllipse(in: CGRect(x: stickRect.midX - knobR, y: stickRect.midY - knobR, width: knobR * 2, height: knobR * 2))

        let actD = min(185, height * 0.135)
        let actRect = CGRect(x: width - 88 - actD, y: 68, width: actD, height: actD)
        ctx.setFillColor(crimson.cgColor)
        ctx.fillEllipse(in: actRect)
        ctx.setStrokeColor(brass.cgColor)
        ctx.setLineWidth(4.5)
        ctx.strokeEllipse(in: actRect)
        VideoSuiteExporter.drawCenteredText(isRunner ? "PUNCH" : "FIRE", ctx: ctx, center: CGPoint(x: actRect.midX, y: actRect.midY), fontSize: actD * 0.18, color: .white)

        let altD = actD * 0.86
        let altRect = CGRect(x: actRect.minX - altD - 28, y: actRect.minY + 12, width: altD, height: altD)
        ctx.setFillColor(blue.cgColor)
        ctx.fillEllipse(in: altRect)
        ctx.setStrokeColor(brass.cgColor)
        ctx.setLineWidth(4.0)
        ctx.strokeEllipse(in: altRect)
        VideoSuiteExporter.drawCenteredText(isRunner ? "JUMP" : "UNIT", ctx: ctx, center: CGPoint(x: altRect.midX, y: altRect.midY), fontSize: altD * 0.18, color: .white)
    }
}

// MARK: - 60fps H.264 + AAC Launch Trailers & Uncut App Review Walkthrough Recorder

@MainActor
enum VideoSuiteExporter {
    final class VideoOnlyRecorder {
        let writer: AVAssetWriter
        let videoInput: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let width: Int
        let height: Int

        init(url: URL, width: Int, height: Int) throws {
            try? FileManager.default.removeItem(at: url)
            self.width = width
            self.height = height
            self.writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

            let vSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 10_500_000,
                    AVVideoMaxKeyFrameIntervalKey: 60,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            self.videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
            self.videoInput.expectsMediaDataInRealTime = false

            let pbAttrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            self.adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: pbAttrs
            )

            writer.add(videoInput)
            guard writer.startWriting(), writer.status == .writing else {
                throw writer.error ?? NSError(domain: "VideoSuiteExporter", code: -1)
            }
            writer.startSession(atSourceTime: .zero)
        }

        func appendVideoFrame(frameIndex: Int, fps: Int32, drawBlock: (CGContext) -> Void) {
            while !videoInput.isReadyForMoreMediaData && writer.status == .writing {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.002))
            }
            guard writer.status == .writing, let pool = adaptor.pixelBufferPool else { return }
            var pbOut: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pbOut)
            guard let pb = pbOut else { return }

            CVPixelBufferLockBaseAddress(pb, [])
            if let base = CVPixelBufferGetBaseAddress(pb) {
                let bpr = CVPixelBufferGetBytesPerRow(pb)
                let cs = CGColorSpaceCreateDeviceRGB()
                let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                if let ctx = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bpr, space: cs, bitmapInfo: bitmapInfo) {
                    drawBlock(ctx)
                }
            }
            CVPixelBufferUnlockBaseAddress(pb, [])

            let pts = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
            _ = adaptor.append(pb, withPresentationTime: pts)
        }

        func finishSync() {
            videoInput.markAsFinished()
            var done = false
            writer.finishWriting { done = true }
            while !done {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
            }
        }
    }

    private static func writeStereoWAV(interleavedSamples: [Int16], sampleRate: UInt32, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let dataBytes = UInt32(interleavedSamples.count * MemoryLayout<Int16>.size)
        let riffChunkSize = 36 + dataBytes
        let byteRate = sampleRate * 4
        let blockAlign: UInt16 = 4
        let bitsPerSample: UInt16 = 16
        let channels: UInt16 = 2
        let audioFormatPCM: UInt16 = 1
        let fmtChunkSize: UInt32 = 16

        var header = Data(capacity: 44 + Int(dataBytes))
        header.append(contentsOf: Array("RIFF".utf8))
        withUnsafeBytes(of: riffChunkSize.littleEndian) { header.append(contentsOf: $0) }
        header.append(contentsOf: Array("WAVEfmt ".utf8))
        withUnsafeBytes(of: fmtChunkSize.littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: audioFormatPCM.littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: channels.littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: sampleRate.littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: byteRate.littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: blockAlign.littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: bitsPerSample.littleEndian) { header.append(contentsOf: $0) }
        header.append(contentsOf: Array("data".utf8))
        withUnsafeBytes(of: dataBytes.littleEndian) { header.append(contentsOf: $0) }
        interleavedSamples.withUnsafeBytes { header.append(contentsOf: $0) }
        try header.write(to: url)
    }

    private static func runExportSync(_ session: AVAssetExportSession) {
        var done = false
        session.exportAsynchronously { done = true }
        while !done {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
    }

    private static func muxVideoAndAudio(videoURL: URL, pcm: [Int16], outputURL: URL) {
        let dir = outputURL.deletingLastPathComponent()
        let wavURL = dir.appendingPathComponent("_tmp_\(UUID().uuidString).wav")
        let m4aURL = dir.appendingPathComponent("_tmp_\(UUID().uuidString).m4a")
        defer {
            try? FileManager.default.removeItem(at: videoURL)
            try? FileManager.default.removeItem(at: wavURL)
            try? FileManager.default.removeItem(at: m4aURL)
        }

        try? writeStereoWAV(interleavedSamples: pcm, sampleRate: 44100, to: wavURL)
        let wavAsset = AVURLAsset(url: wavURL)
        if let m4aExp = AVAssetExportSession(asset: wavAsset, presetName: AVAssetExportPresetAppleM4A) {
            m4aExp.outputURL = m4aURL
            m4aExp.outputFileType = .m4a
            runExportSync(m4aExp)
        }

        try? FileManager.default.removeItem(at: outputURL)
        let comp = AVMutableComposition()
        let vAsset = AVURLAsset(url: videoURL)
        let aAsset = AVURLAsset(url: m4aURL)
        if let srcV = vAsset.tracks(withMediaType: .video).first,
           let dstV = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? dstV.insertTimeRange(CMTimeRange(start: .zero, duration: vAsset.duration), of: srcV, at: .zero)
        }
        if let srcA = aAsset.tracks(withMediaType: .audio).first,
           let dstA = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let dur = CMTimeMinimum(vAsset.duration, aAsset.duration)
            try? dstA.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: srcA, at: .zero)
        }
        if let exporter = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) {
            exporter.outputURL = outputURL
            exporter.outputFileType = .mp4
            exporter.shouldOptimizeForNetworkUse = true
            runExportSync(exporter)
        }
    }

    static func drawCenteredText(_ text: String, ctx: CGContext, center: CGPoint, fontSize: CGFloat, color: NSColor) {
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let b = CTLineGetBoundsWithOptions(line, [])
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: center.x - b.width * 0.5, y: center.y - b.height * 0.34)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // 1. Uncut Zero-Overlay macOS App Review Guideline 2.1 Walkthrough Recording (18s @ 60fps)
    static func renderAppReviewWalkthrough(skView: SKView, scene: GameScene, outputFile: String) {
        let outURL = URL(fileURLWithPath: outputFile)
        try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tempVideo = outURL.deletingLastPathComponent().appendingPathComponent("_tmp_ir_review.mp4")

        guard let rec = try? VideoOnlyRecorder(url: tempVideo, width: 1280, height: 800) else { return }
        AudioSynth.shared.stopRealtimeEngineForOfflineRender()

        let fps: Int32 = 60
        let totalFrames = 18 * 60
        let samplesPerFrame = 735
        var pcm: [Int16] = []
        pcm.reserveCapacity(totalFrames * samplesPerFrame * 2)

        for f in 0..<totalFrames {
            scene.applyTrailerAutopilot(frame: f, includeTitleIntro: true)
            pcm.append(contentsOf: AudioSynth.shared.renderOfflineInterleavedInt16(frames: samplesPerFrame, sampleRate: 44100))
            if let tex = skView.texture(from: scene) {
                let cg = tex.cgImage()
                rec.appendVideoFrame(frameIndex: f, fps: fps) { ctx in
                    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1280, height: 800))
                }
            }
        }
        rec.finishSync()
        muxVideoAndAudio(videoURL: tempVideo, pcm: pcm, outputURL: outURL)

        PersistenceManager.shared.updateSettings {
            $0.visualTheme = .hdOverdrive
            $0.audioChip = .modernSynth
        }
        print("[VideoSuiteExporter] Exported uncut App Review walkthrough to \(outputFile)")
        fflush(stdout)
    }

    // 2. Dual 60fps Launch Trailers: 16:9 YouTube/Web (1920x1080) & 9:16 Reels/TikTok/Shorts (1080x1920)
    static func renderLaunchTrailers(skView: SKView, scene: GameScene, outputDir: String) {
        let dirURL = URL(fileURLWithPath: outputDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        AudioSynth.shared.stopRealtimeEngineForOfflineRender()

        let w16URL = dirURL.appendingPathComponent("IronRails_LaunchTrailer_16x9_1080p60.mp4")
        let v916URL = dirURL.appendingPathComponent("IronRails_Reels_TikTok_Shorts_9x16_1080p60.mp4")
        let tmp16 = dirURL.appendingPathComponent("_tmp16.mp4")
        let tmp916 = dirURL.appendingPathComponent("_tmp916.mp4")

        guard let rec16 = try? VideoOnlyRecorder(url: tmp16, width: 1920, height: 1080),
              let rec916 = try? VideoOnlyRecorder(url: tmp916, width: 1080, height: 1920) else { return }

        let fps: Int32 = 60
        let totalFrames = 15 * 60
        let samplesPerFrame = 735
        var pcm: [Int16] = []
        pcm.reserveCapacity(totalFrames * samplesPerFrame * 2)

        for f in 0..<totalFrames {
            scene.applyTrailerAutopilot(frame: f, includeTitleIntro: false)
            pcm.append(contentsOf: AudioSynth.shared.renderOfflineInterleavedInt16(frames: samplesPerFrame, sampleRate: 44100))

            let caption: String = {
                if f < 150 { return "1861–1864 CONTINENTAL RAILWAY STRATEGY" }
                if f < 450 { return "DESTRUCTIBLE BRIDGE ARTILLERY & CAVALRY" }
                if f < 680 { return "HIGH-SPEED STEAM PAYMASTER TRAIN HEISTS" }
                return "LIVE 1989 C64 + MOS 6581 SID TIME-MACHINE"
            }()

            if let tex = skView.texture(from: scene) {
                let cg = tex.cgImage()
                rec16.appendVideoFrame(frameIndex: f, fps: fps) { ctx in
                    ctx.setFillColor(NSColor(calibratedRed: 0.04, green: 0.07, blue: 0.14, alpha: 1.0).cgColor)
                    ctx.fill(CGRect(x: 0, y: 0, width: 1920, height: 1080))
                    let sc = max(1920.0 / 1280.0, 1080.0 / 800.0)
                    let dw = 1280.0 * sc, dh = 800.0 * sc
                    ctx.draw(cg, in: CGRect(x: (1920 - dw) * 0.5, y: (1080 - dh) * 0.5, width: dw, height: dh))
                    ctx.setFillColor(NSColor(calibratedRed: 0.05, green: 0.09, blue: 0.18, alpha: 0.88).cgColor)
                    ctx.fill(CGRect(x: 360, y: 28, width: 1200, height: 54))
                    drawCenteredText(caption, ctx: ctx, center: CGPoint(x: 960, y: 55), fontSize: 24, color: NSColor(calibratedRed: 1, green: 0.83, blue: 0.28, alpha: 1))
                }

                rec916.appendVideoFrame(frameIndex: f, fps: fps) { ctx in
                    ctx.setFillColor(NSColor(calibratedRed: 0.04, green: 0.08, blue: 0.16, alpha: 1.0).cgColor)
                    ctx.fill(CGRect(x: 0, y: 0, width: 1080, height: 1920))
                    drawCenteredText("IRON RAILS: BLUE & GRAY", ctx: ctx, center: CGPoint(x: 540, y: 1620), fontSize: 44, color: NSColor(calibratedRed: 1, green: 0.83, blue: 0.28, alpha: 1))
                    drawCenteredText("MAC • IPHONE • IPAD UNIVERSAL", ctx: ctx, center: CGPoint(x: 540, y: 1555), fontSize: 24, color: .white)
                    // Crisp wide gameplay frame centered at y=960
                    let gw: CGFloat = 1040, gh: CGFloat = 650
                    ctx.draw(cg, in: CGRect(x: 20, y: 635, width: gw, height: gh))
                    ctx.setStrokeColor(NSColor(calibratedRed: 1, green: 0.83, blue: 0.28, alpha: 1).cgColor)
                    ctx.setLineWidth(5)
                    ctx.stroke(CGRect(x: 20, y: 635, width: gw, height: gh))
                    drawCenteredText(caption, ctx: ctx, center: CGPoint(x: 540, y: 420), fontSize: 25, color: NSColor(calibratedRed: 0.35, green: 0.72, blue: 1, alpha: 1))
                }
            }
        }

        rec16.finishSync()
        rec916.finishSync()
        muxVideoAndAudio(videoURL: tmp16, pcm: pcm, outputURL: w16URL)
        muxVideoAndAudio(videoURL: tmp916, pcm: pcm, outputURL: v916URL)

        PersistenceManager.shared.updateSettings {
            $0.visualTheme = .hdOverdrive
            $0.audioChip = .modernSynth
        }
        print("[VideoSuiteExporter] Exported 16:9 & 9:16 60fps Launch Trailers to \(outputDir)")
        fflush(stdout)
    }
}
#endif
