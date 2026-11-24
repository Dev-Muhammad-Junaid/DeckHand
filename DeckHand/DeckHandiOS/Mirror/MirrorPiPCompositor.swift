//
//  MirrorPiPCompositor.swift
//  DeckHandiOS
//
//  UX-041: makes the frames Picture in Picture shows. No app UI draws over
//  PiP, so the Mac's pointer has to be inside the frames:
//
//      HEVC sample ─▶ VTDecompressionSession ─▶ BGRA CVPixelBuffer ─┐
//      JPEG UIImage ─▶ drawn into a BGRA CVPixelBuffer ─────────────┤ base
//                                                                   ▼
//      pointer state + sprite ─▶ copy of base, sprite drawn in ─▶ CMSampleBuffer
//                                                                   ▼
//                                          PiP's AVSampleBufferDisplayLayer
//
//  The inline mirror is untouched: its display layer decodes HEVC itself
//  and the SwiftUI pointer stays on top at 60 Hz. This is a second,
//  hardware decode of the same samples, run only while PiP could start
//  (`MirrorPiPPacer`: two composited frames a second while warm, the
//  stream's rate while PiP shows, none while paused).
//
//  Decoder trouble (`MirrorPiPDecodeHealth`): after a failure only a key
//  frame is decoded and one is asked for; three failures in a row switch
//  to passthrough, where the compressed samples go straight to PiP's layer
//  (picture without the pointer) until the mirror restarts.
//
//  Main actor, except the decoder's output handler, which hops back.
//

import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import UIKit
import VideoToolbox

/// Carries Core Video / Core Media objects across the decoder's thread hop.
private struct PiPUnchecked<Value>: @unchecked Sendable {
    let value: Value
}

@MainActor
final class MirrorPiPCompositor {
    /// What to draw for the pointer in the next frame.
    struct Pointer {
        var state: MirrorCursorState
        var sprite: MirrorCursorSprite?
        var displayPointWidth: Double
    }

    /// A finished frame for PiP's layer.
    var onFrame: ((CMSampleBuffer) -> Void)?
    /// A compressed sample to show as it is (passthrough).
    var onPassthrough: ((CMSampleBuffer) -> Void)?
    /// The PiP decoder wants a key frame.
    var onNeedsKeyFrame: (() -> Void)?

    /// The PiP window's width in points (from the playback delegate).
    var windowPointWidth = MirrorPiPFrameMath.defaultWindowPointWidth

    private(set) var pacer = MirrorPiPPacer()
    private(set) var health = MirrorPiPDecodeHealth()

    private var decoder: VTDecompressionSession?
    private var decoderFormat: CMFormatDescription?
    /// Bumped on reset so late decoder output for an old stream is dropped.
    private var generation = 0

    private var base: CVPixelBuffer?
    private var pointer: Pointer?
    private var lastStamp: MirrorPiPFrameMath.CursorStamp?
    private var lastStampVisible = false

    private var outputPool: CVPixelBufferPool?
    private var outputPoolSize: (width: Int, height: Int)?
    private var outputFormat: CMVideoFormatDescription?
    private var deferred: DispatchWorkItem?

    // MARK: Control

    /// How often to make frames (from `MirrorPiPPacer.mode(for:streamFPS:)`).
    func setMode(_ mode: MirrorPiPPacer.Mode) {
        if mode == .off {
            // Nothing can show it: let go of the decoder and buffers.
            tearDownDecoder()
            health.reset()
            base = nil
            deferred?.cancel()
        }
        if pacer.setMode(mode) == .now {
            makeFrame()
        }
    }

    var isRunning: Bool { pacer.mode != .off }

    /// A new stream (mirror restarted, other codec, other display): forget
    /// the picture and wait for a key frame.
    func reset() {
        generation &+= 1
        tearDownDecoder()
        health.reset()
        base = nil
        lastStamp = nil
        deferred?.cancel()
    }

    // MARK: Inputs

    /// An HEVC sample the inline mirror also got. Decoded even while
    /// frozen (paused), so the decoder's references stay whole; only the
    /// frames aren't shown.
    func receive(sample: CMSampleBuffer, isKeyFrame: Bool) {
        guard isRunning else { return }
        switch health.verdict(isKeyFrame: isKeyFrame) {
        case .skip:
            return
        case .passthrough:
            guard pacer.mode != .frozen else { return }
            onPassthrough?(sample)
        case .decode:
            decode(sample, isKeyFrame: isKeyFrame)
        }
    }

    /// A JPEG frame.
    func receive(image: UIImage) {
        guard isRunning, let cgImage = image.cgImage else { return }
        guard let size = MirrorPiPFrameMath.jpegBufferSize(width: Double(cgImage.width), height: Double(cgImage.height)),
              let buffer = Self.makeBuffer(width: size.width, height: size.height, pool: nil) else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let context = Self.context(for: buffer) {
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        // A JPEG stream needs no decoder.
        if decoder != nil { tearDownDecoder() }
        setBase(buffer)
    }

    /// The pointer moved or changed shape.
    func receive(pointer new: Pointer?) {
        pointer = new
        guard isRunning, pacer.mode != .frozen, let base else { return }
        let stamp = currentStamp(width: CVPixelBufferGetWidth(base), height: CVPixelBufferGetHeight(base))
        let visible = stamp != nil
        guard stamp != lastStamp || visible != lastStampVisible else { return }
        changed()
    }

    // MARK: Decode

    private func decode(_ sample: CMSampleBuffer, isKeyFrame: Bool) {
        guard let format = CMSampleBufferGetFormatDescription(sample) else { return }
        if decoder == nil || decoderFormat.map({ !CMFormatDescriptionEqual($0, otherFormatDescription: format) }) ?? true {
            tearDownDecoder()
            guard makeDecoder(format: format) else {
                failed()
                return
            }
        }
        guard let decoder else { return }
        let generation = generation
        let status = VTDecompressionSessionDecodeFrame(
            decoder,
            sampleBuffer: sample,
            flags: [._EnableAsynchronousDecompression],
            infoFlagsOut: nil
        ) { status, _, imageBuffer, _, _ in
            let box = PiPUnchecked(value: imageBuffer)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    MirrorPiPCompositor.deliver(to: self, generation: generation, status: status, buffer: box.value, isKeyFrame: isKeyFrame)
                }
            }
        }
        if status != noErr {
            if Int(status) == Int(kVTInvalidSessionErr) {
                // The system took the decoder away (background): make a
                // new one at the next key frame.
                tearDownDecoder()
            }
            failed()
        }
    }

    private static func deliver(to compositor: MirrorPiPCompositor, generation: Int, status: OSStatus, buffer: CVImageBuffer?, isKeyFrame: Bool) {
        guard generation == compositor.generation else { return }
        guard status == noErr, let buffer else {
            if Int(status) == Int(kVTInvalidSessionErr) { compositor.tearDownDecoder() }
            compositor.failed()
            return
        }
        compositor.health.decoded(isKeyFrame: isKeyFrame)
        compositor.setBase(buffer)
    }

    private func failed() {
        let wasPassthrough = health.isPassthrough
        if health.failed() {
            onNeedsKeyFrame?()
        }
        if health.isPassthrough, !wasPassthrough {
            DeckHandLog.connection.error("PiP: the pointer can't be drawn into this stream (decoder keeps failing); showing the video as it is")
            tearDownDecoder()
        }
    }

    private func makeDecoder(format: CMFormatDescription) -> Bool {
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: format,
            decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &session
        )
        guard status == noErr, let session else {
            DeckHandLog.connection.error("PiP: couldn't make an HEVC decoder (\(status, privacy: .public))")
            return false
        }
        VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        decoder = session
        decoderFormat = format
        return true
    }

    private func tearDownDecoder() {
        if let decoder {
            VTDecompressionSessionInvalidate(decoder)
        }
        decoder = nil
        decoderFormat = nil
    }

    // MARK: Composite

    private func setBase(_ buffer: CVPixelBuffer) {
        base = buffer
        changed()
    }

    private func changed() {
        let now = CACurrentMediaTime()
        switch pacer.somethingChanged(now: now) {
        case .none:
            break
        case .now:
            makeFrame()
        case let .after(delay):
            deferred?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.pacer.deferredFire(now: CACurrentMediaTime()) else { return }
                    self.makeFrame()
                }
            }
            deferred = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func currentStamp(width: Int, height: Int) -> MirrorPiPFrameMath.CursorStamp? {
        guard let pointer, let sprite = pointer.sprite,
              let rect = MirrorPiPFrameMath.cursorRect(
                state: pointer.state,
                shape: sprite.shape,
                displayPointWidth: pointer.displayPointWidth,
                frameWidth: width,
                frameHeight: height,
                windowPointWidth: windowPointWidth
              ) else { return nil }
        return MirrorPiPFrameMath.CursorStamp(shapeID: sprite.shape.id, rect: rect)
    }

    /// Copies the base picture, draws the pointer into it and hands the
    /// result to PiP's layer.
    private func makeFrame() {
        guard let base, pacer.mode != .frozen, pacer.mode != .off else { return }
        pacer.frameMade(now: CACurrentMediaTime())
        let width = CVPixelBufferGetWidth(base)
        let height = CVPixelBufferGetHeight(base)
        let stamp = currentStamp(width: width, height: height)
        lastStamp = stamp
        lastStampVisible = stamp != nil

        var frame = base
        if let pointer, let sprite = pointer.sprite, let cursorImage = sprite.image.cgImage,
           let rect = MirrorPiPFrameMath.cursorRect(
               state: pointer.state,
               shape: sprite.shape,
               displayPointWidth: pointer.displayPointWidth,
               frameWidth: width,
               frameHeight: height,
               windowPointWidth: windowPointWidth
           ),
           let output = copyForDrawing(base, width: width, height: height) {
            CVPixelBufferLockBaseAddress(output, [])
            if let context = Self.context(for: output) {
                let flipped = MirrorPiPFrameMath.flipped(rect, frameHeight: height)
                context.interpolationQuality = .high
                context.draw(cursorImage, in: CGRect(x: flipped.x, y: flipped.y, width: flipped.width, height: flipped.height))
            }
            CVPixelBufferUnlockBaseAddress(output, [])
            frame = output
        }
        guard let sample = makeSample(frame) else { return }
        onFrame?(sample)
    }

    /// A pool buffer holding a copy of `source` (both BGRA).
    private func copyForDrawing(_ source: CVPixelBuffer, width: Int, height: Int) -> CVPixelBuffer? {
        guard CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA else { return nil }
        if outputPoolSize.map({ $0.width != width || $0.height != height }) ?? true {
            outputPool = Self.makePool(width: width, height: height)
            outputPoolSize = (width, height)
        }
        guard let output = Self.makeBuffer(width: width, height: height, pool: outputPool) else { return nil }
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(output, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        guard let from = CVPixelBufferGetBaseAddress(source), let to = CVPixelBufferGetBaseAddress(output) else { return nil }
        let fromRow = CVPixelBufferGetBytesPerRow(source)
        let toRow = CVPixelBufferGetBytesPerRow(output)
        if fromRow == toRow {
            memcpy(to, from, fromRow * height)
        } else {
            let rowBytes = min(fromRow, toRow, width * 4)
            for row in 0..<height {
                memcpy(to + row * toRow, from + row * fromRow, rowBytes)
            }
        }
        return output
    }

    private func makeSample(_ buffer: CVPixelBuffer) -> CMSampleBuffer? {
        if outputFormat.map({ !CMVideoFormatDescriptionMatchesImageBuffer($0, imageBuffer: buffer) }) ?? true {
            var format: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &format)
            outputFormat = format
        }
        guard let outputFormat else { return nil }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescription: outputFormat,
            sampleTiming: &timing,
            sampleBufferOut: &sample
        )
        guard let sample else { return nil }
        Self.markDisplayImmediately(sample)
        return sample
    }

    // MARK: Helpers

    static func markDisplayImmediately(_ sample: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
              CFArrayGetCount(attachments) > 0 else { return }
        let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(
            dictionary,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
        )
    }

    private static func bufferAttributes(width: Int, height: Int) -> [CFString: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
    }

    private static func makePool(width: Int, height: Int) -> CVPixelBufferPool? {
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, bufferAttributes(width: width, height: height) as CFDictionary, &pool)
        return pool
    }

    private static func makeBuffer(width: Int, height: Int, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        } else {
            CVPixelBufferCreate(
                kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                bufferAttributes(width: width, height: height) as CFDictionary, &buffer
            )
        }
        return buffer
    }

    /// A bitmap context over a locked BGRA buffer.
    private static func context(for buffer: CVPixelBuffer) -> CGContext? {
        CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }
}
