//
//  MirrorAudioCapture.swift
//  DeckHandMac
//
//  S17: an audio-only ScreenCaptureKit stream of the Mac's sound, encoded
//  into packets on its own queue.
//
//  ScreenCaptureKit always captures some video; this stream asks for a
//  2×2 picture once a second and throws it away. Audio is captured from
//  every app (the filter is the main display with nothing excluded) except
//  Pixel Hand itself (`excludesCurrentProcessAudio`), at 48 kHz stereo.
//
//  Threading: `start` and `stop` are called by `MirrorAudioService` on the
//  main actor; samples arrive, are converted and encoded on `queue`; the
//  callbacks are set before `start` and called on `queue`.
//

import AVFoundation
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

final class MirrorAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case noDisplay

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "no display to capture"
            }
        }
    }

    /// One encoded packet, its format and its capture time (µs, uptime).
    var onPacket: (@Sendable (MirrorAudioFormat, MirrorAudioPacket, UInt64) -> Void)?
    /// The capture stopped by itself (Screen Recording turned off, …).
    var onFailure: (@Sendable (String) -> Void)?

    private let queue = DispatchQueue(label: "com.widgetsflow.pixelhand.mirror.audio", qos: .userInteractive)
    /// Main actor only.
    private var stream: SCStream?

    // Capture queue only.
    private var encoder: MirrorAudioEncoder?
    private var sequence: UInt32 = 0
    private var loggedUnsupportedFormat = false

    /// Starts capturing. Throws when ScreenCaptureKit refuses (no Screen
    /// Recording permission, no display).
    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = MirrorAudioFormat.preferredSampleRate
        config.channelCount = 2
        // Video can't be turned off: the smallest, slowest picture.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 3
        config.showsCursor = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        // The picture is dropped here instead of ScreenCaptureKit logging
        // "stream output not found" for every frame.
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
        queue.async { [self] in
            encoder = nil
        }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let pcm = Self.stereoSamples(from: sampleBuffer) else {
            if !loggedUnsupportedFormat {
                loggedUnsupportedFormat = true
                DeckHandLog.app.error("Mirror audio: unsupported capture format, audio dropped")
            }
            return
        }
        let rate = Int(pcm.sampleRate.rounded())
        if encoder?.sampleRate != rate {
            encoder = MirrorAudioEncoder(sampleRate: rate, channels: 2)
            DeckHandLog.app.info("Mirror audio: \(self.encoder?.codec.label ?? "?", privacy: .public) at \(rate, privacy: .public) Hz")
        }
        guard let encoder else { return }
        let micros = DispatchTime.now().uptimeNanoseconds / 1_000
        for output in encoder.encode(pcm.samples) {
            guard let format = encoder.format else { continue }
            sequence &+= 1
            let packet = MirrorAudioPacket(
                sequence: sequence,
                sampleTime: output.sampleTime,
                frameCount: output.frameCount,
                data: output.data
            )
            onPacket?(format, packet, micros)
        }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onFailure?(error.localizedDescription)
    }

    // MARK: Samples

    /// The buffer's audio as interleaved stereo Float32 (mono doubled,
    /// extra channels dropped). `nil` for anything but 32-bit float PCM.
    private static func stereoSamples(from sampleBuffer: CMSampleBuffer) -> (samples: [Float], sampleRate: Double)? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              asbd.mBitsPerChannel == 32,
              asbd.mChannelsPerFrame > 0
        else { return nil }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0 else { return nil }
        let channels = Int(asbd.mChannelsPerFrame)
        let planar = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0

        var listSize = 0
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &listSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        ) == noErr, listSize > 0 else { return nil }
        let listMemory = UnsafeMutableRawPointer.allocate(byteCount: listSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { listMemory.deallocate() }
        let list = listMemory.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: list,
            bufferListSize: listSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        ) == noErr else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(list)
        var samples = [Float](repeating: 0, count: frames * 2)
        func sample(frame: Int, channel: Int) -> Float {
            let source = min(channel, channels - 1)
            if planar {
                guard source < buffers.count, let data = buffers[source].mData else { return 0 }
                let count = Int(buffers[source].mDataByteSize) / MemoryLayout<Float>.size
                guard frame < count else { return 0 }
                return data.assumingMemoryBound(to: Float.self)[frame]
            }
            guard let data = buffers.first?.mData else { return 0 }
            let count = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size
            let index = frame * channels + source
            guard index < count else { return 0 }
            return data.assumingMemoryBound(to: Float.self)[index]
        }
        for frame in 0..<frames {
            samples[frame * 2] = sample(frame: frame, channel: 0)
            samples[frame * 2 + 1] = sample(frame: frame, channel: 1)
        }
        _ = blockBuffer // keeps the samples alive until here
        return (samples, asbd.mSampleRate)
    }
}
