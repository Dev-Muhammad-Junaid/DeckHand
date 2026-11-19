//
//  MirrorHEVCEncoder.swift
//  DeckHandMac
//
//  The HEVC mirror's encoder (S5): a `VTCompressionSession` fed the
//  `CVPixelBuffer`s ScreenCaptureKit already delivers (NV12 / `420v` when
//  an HEVC remote is watching), so no pixel ever goes through the CPU.
//
//  Settings: HEVC Main, real time, no frame reordering (no B-frames, so
//  every frame can be shown the moment it decodes), a key frame at least
//  every `MirrorKeyFramePolicy.interval` seconds, an average bit rate from
//  `MirrorVideoBitrate`. Key frames are also forced when a remote needs one
//  (`MirrorKeyFramePolicy`, spaced out). Every key frame carries the
//  parameter sets, so a remote can join or recover at any key frame.
//
//  Threading: `encode` runs on the capture's sample queue; VideoToolbox
//  calls back on its own thread; `requestKeyFrame` comes from the main
//  actor. Shared state is behind `lock`. At most `maxPendingEncodes`
//  frames are inside the encoder at once; a capture frame beyond that is
//  skipped (the next delta simply covers more change).
//

import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// One encoded HEVC access unit, ready for `MirrorSubscriber.sendHEVC`.
struct MirrorHEVCEncodedFrame: Sendable {
    let isKeyFrame: Bool
    /// `MirrorHEVCParameterSets.encoded()`; present on key frames.
    let parameterSets: Data?
    /// Length-prefixed NAL units, as VideoToolbox wrote them.
    let payload: Data
    let presentationTimeMicros: UInt64
    let encodeSeconds: Double
    let width: Int
    let height: Int
}

final class MirrorHEVCEncoder: @unchecked Sendable {
    static let maxPendingEncodes = 2

    /// Called on VideoToolbox's thread, in encode order.
    private let onFrame: @Sendable (MirrorHEVCEncodedFrame) -> Void
    /// Called once if no HEVC encoder can be made on this Mac.
    private let onUnavailable: @Sendable () -> Void

    private let lock = NSLock()
    private var session: VTCompressionSession?
    private var width = 0
    private var height = 0
    private var fps = 20
    private var policy = MirrorKeyFramePolicy()
    private var pendingEncodes = 0
    private var unavailable = false
    /// Frames skipped because the encoder was full, since the last read.
    private var skipped = 0

    init(
        onFrame: @escaping @Sendable (MirrorHEVCEncodedFrame) -> Void,
        onUnavailable: @escaping @Sendable () -> Void
    ) {
        self.onFrame = onFrame
        self.onUnavailable = onUnavailable
    }

    deinit {
        if let session {
            VTCompressionSessionInvalidate(session)
        }
    }

    // MARK: Control (any thread)

    /// The capture's frame rate; a new session picks it up.
    func setFrameRate(_ fps: Int) {
        lock.lock()
        let changed = self.fps != fps
        self.fps = fps
        if changed, let session {
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: fps))
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: MirrorVideoBitrate.averageBitsPerSecond(width: width, height: height, fps: fps)))
        }
        lock.unlock()
    }

    /// A remote needs a key frame; it comes with the next captured frame
    /// unless one was forced very recently.
    func requestKeyFrame() {
        lock.lock()
        policy.request()
        lock.unlock()
    }

    /// Capture frames skipped since the last call (encoder full).
    func takeSkippedCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let count = skipped
        skipped = 0
        return count
    }

    func invalidate() {
        lock.lock()
        let old = session
        session = nil
        lock.unlock()
        if let old {
            VTCompressionSessionCompleteFrames(old, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(old)
        }
    }

    // MARK: Encoding (sample queue)

    /// Submits one captured frame. Returns `false` when it was skipped.
    @discardableResult
    func encode(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) -> Bool {
        let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)

        lock.lock()
        if unavailable {
            lock.unlock()
            return false
        }
        if pendingEncodes >= Self.maxPendingEncodes {
            skipped += 1
            lock.unlock()
            return false
        }
        var retired: VTCompressionSession?
        if session == nil || bufferWidth != width || bufferHeight != height {
            retired = session
            session = nil
            width = bufferWidth
            height = bufferHeight
            policy.reset()
            session = Self.makeSession(width: bufferWidth, height: bufferHeight, fps: fps)
            if session == nil {
                unavailable = true
                lock.unlock()
                if let retired { VTCompressionSessionInvalidate(retired) }
                DeckHandLog.app.error("Mirror: no HEVC encoder for \(bufferWidth, privacy: .public)×\(bufferHeight, privacy: .public); remotes get JPEG")
                onUnavailable()
                return false
            }
        }
        guard let session else {
            lock.unlock()
            return false
        }
        let now = Self.now()
        let forceKeyFrame = policy.shouldForceKeyFrame(now: now)
        pendingEncodes += 1
        lock.unlock()

        if let retired { VTCompressionSessionInvalidate(retired) }

        let properties: CFDictionary? = forceKeyFrame
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary
            : nil
        let started = now
        let frameWidth = bufferWidth
        let frameHeight = bufferHeight
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: properties,
            infoFlagsOut: nil
        ) { [weak self] status, flags, sampleBuffer in
            self?.didEncode(status: status, flags: flags, sampleBuffer: sampleBuffer, started: started, width: frameWidth, height: frameHeight)
        }
        if status != noErr {
            lock.lock()
            pendingEncodes = max(0, pendingEncodes - 1)
            lock.unlock()
            DeckHandLog.app.error("Mirror: HEVC encode failed (\(status, privacy: .public))")
            return false
        }
        return true
    }

    // MARK: Output (VideoToolbox's thread)

    private func didEncode(
        status: OSStatus,
        flags: VTEncodeInfoFlags,
        sampleBuffer: CMSampleBuffer?,
        started: Double,
        width: Int,
        height: Int
    ) {
        lock.lock()
        pendingEncodes = max(0, pendingEncodes - 1)
        lock.unlock()

        guard status == noErr, !flags.contains(.frameDropped), let sampleBuffer,
              let payload = Self.payload(of: sampleBuffer) else { return }

        let isKeyFrame = Self.isKeyFrame(sampleBuffer)
        let now = Self.now()
        var parameterSets: Data?
        if isKeyFrame {
            guard let sets = Self.parameterSets(of: sampleBuffer) else { return }
            parameterSets = sets.encoded()
            lock.lock()
            policy.noteKeyFrame(at: now)
            lock.unlock()
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let micros = pts.isValid && pts.seconds.isFinite && pts.seconds >= 0
            ? UInt64(pts.seconds * 1_000_000)
            : DispatchTime.now().uptimeNanoseconds / 1_000
        onFrame(MirrorHEVCEncodedFrame(
            isKeyFrame: isKeyFrame,
            parameterSets: parameterSets,
            payload: payload,
            presentationTimeMicros: micros,
            encodeSeconds: max(0, now - started),
            width: width,
            height: height
        ))
    }

    // MARK: Helpers

    private static func now() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    private static func makeSession(width: Int, height: Int, fps: Int) -> VTCompressionSession? {
        let specification = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: kCFBooleanTrue,
        ] as CFDictionary
        var created: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: specification,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &created
        )
        guard status == noErr, let session = created else { return nil }

        func set(_ key: CFString, _ value: CFTypeRef) {
            let result = VTSessionSetProperty(session, key: key, value: value)
            if result != noErr {
                DeckHandLog.app.debug("Mirror: HEVC property \(key as String, privacy: .public) not set (\(result, privacy: .public))")
            }
        }
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main_AutoLevel)
        set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, NSNumber(value: MirrorKeyFramePolicy.interval))
        set(kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: fps))
        set(kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: MirrorVideoBitrate.averageBitsPerSecond(width: width, height: height, fps: fps)))
        set(kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, kCFBooleanTrue)
        VTCompressionSessionPrepareToEncodeFrames(session)
        return session
    }

    private static func isKeyFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
              let first = attachments.first else { return true }
        return (first[kCMSampleAttachmentKey_NotSync] as? Bool) != true
    }

    private static func payload(of sampleBuffer: CMSampleBuffer) -> Data? {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let status = data.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
        }
        return status == noErr ? data : nil
    }

    private static func parameterSets(of sampleBuffer: CMSampleBuffer) -> MirrorHEVCParameterSets? {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        var count = 0
        var headerLength: Int32 = 0
        let status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
            format,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &count,
            nalUnitHeaderLengthOut: &headerLength
        )
        guard status == noErr, count > 0 else { return nil }
        var sets: [Data] = []
        for index in 0..<count {
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            let result = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                format,
                parameterSetIndex: index,
                parameterSetPointerOut: &pointer,
                parameterSetSizeOut: &size,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            )
            guard result == noErr, let pointer, size > 0 else { return nil }
            sets.append(Data(bytes: pointer, count: size))
        }
        return MirrorHEVCParameterSets(nalUnitHeaderLength: Int(headerLength), sets: sets)
    }
}
