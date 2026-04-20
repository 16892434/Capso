import AVFoundation
import CoreMedia
import Foundation

/// Builds short `.mov` fixtures that mirror Capso's real recording pipeline:
/// H.264 video + one or two AAC audio tracks in a QuickTime container.
enum DualAudioFixture {
    enum FixtureError: Error {
        case writerSetupFailed
        case pixelBufferCreateFailed
        case audioFormatCreateFailed
        case blockBufferCreateFailed
        case sampleBufferCreateFailed
        case writerFinishFailed(Error?)
    }

    static func make(audioTrackCount: Int = 2,
                     durationSeconds: Double = 0.5) throws -> URL {
        precondition((1...2).contains(audioTrackCount))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-fixture-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let width = 160
        let height = 120
        let fps: Int32 = 30

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw FixtureError.writerSetupFailed }
        writer.add(videoInput)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000,
        ]
        var audioInputs: [AVAssetWriterInput] = []
        for _ in 0..<audioTrackCount {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw FixtureError.writerSetupFailed }
            writer.add(input)
            audioInputs.append(input)
        }

        let pbAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )

        guard writer.startWriting() else { throw FixtureError.writerSetupFailed }
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: fps)
        let frameCount = max(1, Int(Double(fps) * durationSeconds))

        for i in 0..<frameCount {
            while !videoInput.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.001) }
            let pb = try makeBlackPixelBuffer(width: width, height: height)
            let pts = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            if !pbAdaptor.append(pb, withPresentationTime: pts) {
                throw FixtureError.writerFinishFailed(writer.error)
            }
        }
        videoInput.markAsFinished()

        for input in audioInputs {
            try writeSilence(into: input, seconds: durationSeconds)
            input.markAsFinished()
        }

        let done = DispatchGroup()
        done.enter()
        writer.finishWriting { done.leave() }
        done.wait()
        guard writer.status == .completed else {
            throw FixtureError.writerFinishFailed(writer.error)
        }
        return url
    }

    // MARK: - Helpers

    private static func makeBlackPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true,
             kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
            &pb)
        guard status == kCVReturnSuccess, let pb else {
            throw FixtureError.pixelBufferCreateFailed
        }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        let base = CVPixelBufferGetBaseAddress(pb)!
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        memset(base, 0, bpr * height)
        return pb
    }

    private static func writeSilence(into input: AVAssetWriterInput, seconds: Double) throws {
        let sampleRate: Float64 = 48_000
        let channels: UInt32 = 2
        let bytesPerFrame: UInt32 = 4 * channels  // Float32 interleaved

        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var format: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &format
        )
        guard formatStatus == noErr, let format else {
            throw FixtureError.audioFormatCreateFailed
        }

        let totalFrames = Int(sampleRate * seconds)
        let chunkFrames = 1024
        var written = 0
        while written < totalFrames {
            let frames = min(chunkFrames, totalFrames - written)
            let dataSize = frames * Int(bytesPerFrame)

            var block: CMBlockBuffer?
            let blockStatus = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil, blockLength: dataSize,
                blockAllocator: nil, customBlockSource: nil,
                offsetToData: 0, dataLength: dataSize,
                flags: kCMBlockBufferAssureMemoryNowFlag,
                blockBufferOut: &block
            )
            guard blockStatus == kCMBlockBufferNoErr, let block else {
                throw FixtureError.blockBufferCreateFailed
            }
            CMBlockBufferFillDataBytes(with: 0, blockBuffer: block,
                                       offsetIntoDestination: 0, dataLength: dataSize)

            var timing = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
                presentationTimeStamp: CMTime(value: CMTimeValue(written),
                                              timescale: CMTimeScale(sampleRate)),
                decodeTimeStamp: .invalid
            )
            var sampleSize = Int(bytesPerFrame)
            var sample: CMSampleBuffer?
            let sbStatus = CMSampleBufferCreate(
                allocator: kCFAllocatorDefault,
                dataBuffer: block, dataReady: true,
                makeDataReadyCallback: nil, refcon: nil,
                formatDescription: format,
                sampleCount: CMItemCount(frames),
                sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize,
                sampleBufferOut: &sample
            )
            guard sbStatus == noErr, let sample else {
                throw FixtureError.sampleBufferCreateFailed
            }

            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.001) }
            if !input.append(sample) {
                throw FixtureError.sampleBufferCreateFailed
            }
            written += frames
        }
    }
}
