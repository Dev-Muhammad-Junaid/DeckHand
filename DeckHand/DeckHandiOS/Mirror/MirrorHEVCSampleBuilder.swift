//
//  MirrorHEVCSampleBuilder.swift
//  DeckHandiOS
//
//  Turns the HEVC mirror's binary frames (S5) into `CMSampleBuffer`s for
//  `AVSampleBufferDisplayLayer`: parameter sets →
//  `CMVideoFormatDescriptionCreateFromHEVCParameterSets`, each key or delta
//  frame → a block buffer and a sample buffer marked "display
//  immediately". One builder per mirror stream, used only by that
//  stream's reader task.
//
//  A payload that isn't whole length-prefixed NAL units
//  (`MirrorHEVCNALUnits.isWellFormed`) gives no sample, so damaged data
//  never reaches the decoder; the watchdog then asks for a key frame.
//

import CoreGraphics
import CoreMedia
import Foundation

/// What the reader hands the main actor for one HEVC frame. `@unchecked
/// Sendable`: a `CMSampleBuffer` is immutable once made, and the reader
/// gives up its reference.
enum MirrorVideoEvent: @unchecked Sendable {
    /// New parameter sets. `valid`: a format could be made from them.
    case parameterSets(valid: Bool, dimensions: CGSize?)
    /// A key or delta frame. `sample` is `nil` when it couldn't be built
    /// (no format yet, or a damaged payload).
    case frame(kind: MirrorVideoWatchdog.FrameKind, afterDrop: Bool, sample: CMSampleBuffer?)
}

final class MirrorHEVCSampleBuilder {
    private var format: CMVideoFormatDescription?
    private var headerLength = 4

    /// The picture size of the current format.
    var dimensions: CGSize? {
        guard let format else { return nil }
        let size = CMVideoFormatDescriptionGetDimensions(format)
        return CGSize(width: Int(size.width), height: Int(size.height))
    }

    /// Reads a `hevcParameterSets` payload. Returns whether it made a format.
    func setParameterSets(_ payload: Data) -> Bool {
        guard let sets = try? MirrorHEVCParameterSets.decode(payload) else {
            format = nil
            return false
        }
        let pointers: [UnsafeMutablePointer<UInt8>] = sets.sets.map { set in
            let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: set.count)
            set.copyBytes(to: pointer, count: set.count)
            return pointer
        }
        defer { pointers.forEach { $0.deallocate() } }
        let constPointers = pointers.map { UnsafePointer($0) }
        let sizes = sets.sets.map(\.count)

        var made: CMFormatDescription?
        let status = constPointers.withUnsafeBufferPointer { pointerBuffer in
            sizes.withUnsafeBufferPointer { sizeBuffer in
                CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: sets.sets.count,
                    parameterSetPointers: pointerBuffer.baseAddress!,
                    parameterSetSizes: sizeBuffer.baseAddress!,
                    nalUnitHeaderLength: Int32(sets.nalUnitHeaderLength),
                    extensions: nil,
                    formatDescriptionOut: &made
                )
            }
        }
        guard status == noErr, let made else {
            format = nil
            return false
        }
        format = made
        headerLength = sets.nalUnitHeaderLength
        return true
    }

    /// A sample buffer for one frame, or `nil`.
    func sampleBuffer(payload: Data, isKeyFrame: Bool, presentationTimeMicros: UInt64) -> CMSampleBuffer? {
        guard let format, MirrorHEVCNALUnits.isWellFormed(payload, headerLength: headerLength) else { return nil }

        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: payload.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: payload.count,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &block
        )
        guard status == kCMBlockBufferNoErr, let block else { return nil }
        status = payload.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: payload.count
            )
        }
        guard status == kCMBlockBufferNoErr else { return nil }

        var sample: CMSampleBuffer?
        var sampleSize = payload.count
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: CMTimeValue(clamping: presentationTimeMicros), timescale: 1_000_000),
            decodeTimeStamp: .invalid
        )
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sample
        )
        guard status == noErr, let sample else { return nil }

        // Show as soon as decoded (no timebase), and say which frames
        // depend on others.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
            if !isKeyFrame {
                CFDictionarySetValue(
                    dictionary,
                    Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                    Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
                )
            }
        }
        return sample
    }
}
