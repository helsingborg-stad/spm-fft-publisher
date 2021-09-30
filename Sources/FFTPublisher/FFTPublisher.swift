import Foundation
import AVKit
import Combine
import Accelerate

// https://stackoverflow.com/questions/60120842/how-to-use-apples-accelerate-framework-in-swift-in-order-to-compute-the-fft-of
public protocol FFT: AnyObject {
    var averageMagnitude: PassthroughSubject<CGFloat, Never> { get }
    var magnitudes: PassthroughSubject<[CGFloat], Never> { get }
}
public class FFTPublisher: ObservableObject, FFT {
    public var maxDB: Float = 64.0
    public var minDB: Float = -28.0
    public var headroom: Float {
        maxDB - minDB
    }
    public var bands: Int = Int(150)
    public var minFrequency: Float = 125
    public var maxFrequency: Float = 8000
    public var disabled: Bool = false
    public let averageMagnitude: PassthroughSubject<CGFloat, Never> = .init()
    public let magnitudes: PassthroughSubject<[CGFloat], Never> = .init()
    public init() {

    }
    public func end() {
        DispatchQueue.main.async {
            self.magnitudes.send(Array(repeating: 0, count: self.bands))
        }
    }
    /// Requires float audio format
    public func consume(buffer: UnsafePointer<AudioBufferList>, frames: AVAudioFrameCount, rate: Float) {
        if disabled {
            return
        }
        guard let ptr = buffer.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) else {
            return
        }
        var samples = [Float]()
        samples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: Int(frames)))
        let fft = TempiFFT(withSize: samples.count, sampleRate: rate)
        fft.windowType = TempiFFTWindowType.hanning
        fft.fftForward(samples)
        fft.calculateLinearBands(minFrequency: minFrequency, maxFrequency: maxFrequency, numberOfBands: bands)
        let avg = CGFloat(convert(fft.averageMagnitude(lowFreq: self.minFrequency, highFreq: self.maxFrequency)))
        var scales: [CGFloat] = []
        let count = fft.numberOfBands

        for i in 0..<count {
            scales.insert(CGFloat(convert(fft.magnitudeAtBand(i))), at: 0)
        }
        DispatchQueue.main.async {
            self.averageMagnitude.send(avg)
            self.magnitudes.send(scales)
        }
    }
    private func convert(_ magnitude: Float) -> Float {
        var magnitudeDB = TempiFFT.toDB(magnitude)
        magnitudeDB = max(0, magnitudeDB + abs(minDB))
        return min(1.0, magnitudeDB / headroom)
    }
}
