//
//  MirrorAudioDecoder.swift
//  DeckHandiOS
//
//  S17: one audio packet → interleaved Float32 samples. AAC-LC through
//  AVAudioConverter (with the Mac's magic cookie), 16-bit PCM directly.
//  Not thread-safe: the player calls it under its decode lock.
//

import AVFoundation
import Foundation

final class MirrorAudioDecoder {
    let format: MirrorAudioFormat

    private let compressedFormat: AVAudioFormat?
    private let pcmFormat: AVAudioFormat?
    private let converter: AVAudioConverter?

    /// `nil` when this device can't decode `format`.
    init?(format: MirrorAudioFormat) {
        self.format = format
        switch format.codec {
        case .pcm16:
            compressedFormat = nil
            pcmFormat = nil
            converter = nil

        case .aacLC:
            var description = AudioStreamBasicDescription(
                mSampleRate: Double(format.sampleRate),
                mFormatID: kAudioFormatMPEG4AAC,
                mFormatFlags: 0,
                mBytesPerPacket: 0,
                mFramesPerPacket: UInt32(format.framesPerPacket),
                mBytesPerFrame: 0,
                mChannelsPerFrame: UInt32(format.channels),
                mBitsPerChannel: 0,
                mReserved: 0
            )
            guard let compressed = AVAudioFormat(streamDescription: &description),
                  let pcm = AVAudioFormat(
                      commonFormat: .pcmFormatFloat32,
                      sampleRate: Double(format.sampleRate),
                      channels: AVAudioChannelCount(format.channels),
                      interleaved: true
                  )
            else { return nil }
            if !format.magicCookie.isEmpty {
                compressed.magicCookie = format.magicCookie
            }
            guard let converter = AVAudioConverter(from: compressed, to: pcm) else { return nil }
            compressedFormat = compressed
            pcmFormat = pcm
            self.converter = converter
        }
    }

    /// The packet's samples, interleaved; empty while the AAC decoder
    /// primes or when the packet is unusable.
    func decode(_ data: Data) -> [Float] {
        switch format.codec {
        case .pcm16:
            return MirrorAudioPCM16.decode(data)
        case .aacLC:
            return decodeAAC(data)
        }
    }

    /// After a gap: AAC carries state from packet to packet.
    func reset() {
        converter?.reset()
    }

    private func decodeAAC(_ data: Data) -> [Float] {
        guard let converter, let compressedFormat, let pcmFormat, !data.isEmpty else { return [] }
        let input = AVAudioCompressedBuffer(format: compressedFormat, packetCapacity: 1, maximumPacketSize: data.count)
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            input.data.copyMemory(from: base, byteCount: data.count)
        }
        input.byteLength = UInt32(data.count)
        input.packetCount = 1
        input.packetDescriptions?.pointee = AudioStreamPacketDescription(
            mStartOffset: 0,
            mVariableFramesInPacket: 0,
            mDataByteSize: UInt32(data.count)
        )
        let capacity = AVAudioFrameCount(format.framesPerPacket * 2)
        guard let output = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: capacity) else { return [] }
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
        guard status != .error, output.frameLength > 0 else { return [] }
        let buffers = UnsafeMutableAudioBufferListPointer(output.mutableAudioBufferList)
        guard let samples = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return [] }
        let count = Int(output.frameLength) * format.channels
        return Array(UnsafeBufferPointer(start: samples, count: count))
    }
}
