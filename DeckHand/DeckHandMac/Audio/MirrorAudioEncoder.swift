//
//  MirrorAudioEncoder.swift
//  DeckHandMac
//
//  S17: interleaved Float32 → packets, on the audio capture queue.
//
//  AAC-LC through AVAudioConverter, 1024 frames a packet, 64 kb/s a
//  channel. If no AAC encoder can be made, 16-bit PCM in 960-frame
//  packets (`MirrorAudioPCM16`). For a latency comparison by ear the codec
//  can be forced:
//
//      defaults write com.widgetsflow.pixelhand.mac MirrorAudioCodec pcm16
//
//  The format (with AAC's magic cookie) is known after the encoder's first
//  output, before the first packet is handed out.
//
//  Not thread-safe: one capture queue only.
//

import AVFoundation
import Foundation

final class MirrorAudioEncoder {
    struct Output {
        let data: Data
        let sampleTime: UInt64
        let frameCount: Int
    }

    let sampleRate: Int
    let channels: Int
    let codec: MirrorAudioCodec
    /// Set once the first packet is out.
    private(set) var format: MirrorAudioFormat?

    private var chunker: MirrorAudioChunker
    private let pcmFormat: AVAudioFormat?
    private let aacFormat: AVAudioFormat?
    private let converter: AVAudioConverter?
    private var outputSampleTime: UInt64 = 0

    init(sampleRate: Int, channels: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
        let forced = UserDefaults.standard.string(forKey: "MirrorAudioCodec")

        var pcmFormat: AVAudioFormat?
        var aacFormat: AVAudioFormat?
        var converter: AVAudioConverter?
        if forced != "pcm16" {
            pcmFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(sampleRate),
                channels: AVAudioChannelCount(channels),
                interleaved: true
            )
            var description = AudioStreamBasicDescription(
                mSampleRate: Double(sampleRate),
                mFormatID: kAudioFormatMPEG4AAC,
                mFormatFlags: 0,
                mBytesPerPacket: 0,
                mFramesPerPacket: UInt32(MirrorAudioCodec.aacLC.framesPerPacket),
                mBytesPerFrame: 0,
                mChannelsPerFrame: UInt32(channels),
                mBitsPerChannel: 0,
                mReserved: 0
            )
            aacFormat = AVAudioFormat(streamDescription: &description)
            if let pcmFormat, let aacFormat {
                converter = AVAudioConverter(from: pcmFormat, to: aacFormat)
                converter?.bitRate = 64_000 * channels
            }
        }
        if let converter {
            self.codec = .aacLC
            self.converter = converter
            self.pcmFormat = pcmFormat
            self.aacFormat = aacFormat
        } else {
            if forced != "pcm16" {
                DeckHandLog.app.error("Mirror audio: no AAC encoder, sending 16-bit PCM")
            }
            self.codec = .pcm16
            self.converter = nil
            self.pcmFormat = nil
            self.aacFormat = nil
        }
        chunker = MirrorAudioChunker(channels: channels, framesPerPacket: codec.framesPerPacket)
    }

    /// Adds captured samples and returns the packets they complete.
    func encode(_ samples: [Float]) -> [Output] {
        var outputs: [Output] = []
        for chunk in chunker.append(samples) {
            switch codec {
            case .pcm16:
                if format == nil {
                    format = MirrorAudioFormat(codec: .pcm16, channels: channels, sampleRate: sampleRate)
                }
                outputs.append(Output(
                    data: MirrorAudioPCM16.encode(chunk.samples),
                    sampleTime: chunk.sampleTime,
                    frameCount: codec.framesPerPacket
                ))
            case .aacLC:
                outputs += encodeAAC(chunk.samples)
            }
        }
        return outputs
    }

    private func encodeAAC(_ samples: [Float]) -> [Output] {
        guard let converter, let pcmFormat, let aacFormat else { return [] }
        let frames = samples.count / channels
        guard let input = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(frames)) else { return [] }
        input.frameLength = AVAudioFrameCount(frames)
        let inputBuffers = UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList)
        guard let destination = inputBuffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return [] }
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            destination.update(from: base, count: samples.count)
        }

        let maximumPacketSize = max(converter.maximumOutputPacketSize, 1_536 * channels)
        let output = AVAudioCompressedBuffer(format: aacFormat, packetCapacity: 8, maximumPacketSize: maximumPacketSize)
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error else {
            DeckHandLog.app.error("Mirror audio: AAC encode failed: \(error?.localizedDescription ?? "?", privacy: .public)")
            return []
        }
        guard output.packetCount > 0, let descriptions = output.packetDescriptions else { return [] }
        if format == nil {
            format = MirrorAudioFormat(
                codec: .aacLC,
                channels: channels,
                sampleRate: sampleRate,
                magicCookie: converter.magicCookie ?? Data()
            )
        }
        var outputs: [Output] = []
        for index in 0..<Int(output.packetCount) {
            let description = descriptions[index]
            let start = output.data.advanced(by: Int(description.mStartOffset))
            outputs.append(Output(
                data: Data(bytes: start, count: Int(description.mDataByteSize)),
                sampleTime: outputSampleTime,
                frameCount: MirrorAudioCodec.aacLC.framesPerPacket
            ))
            outputSampleTime &+= UInt64(MirrorAudioCodec.aacLC.framesPerPacket)
        }
        return outputs
    }
}
