import AVFoundation
import Kingfisher
import SwiftUI

struct SliderWithText<T: BinaryFloatingPoint>: View {
    @Binding var value: T
    let inRange: ClosedRange<T>
    let buffers: [CMTimeRange]
    let activeFillColor: Color
    let fillColor: Color
    let emptyColor: Color
    let height: Double
    let thumbnails: WebVTT?
    let onEditingChanged: (Bool) -> Void

    @State private var localRealProgress: T = 0
    @State private var isAdjusting: Bool = false
    @FocusState private var isFocused: Bool
    @State private var progressDuration: T = 0

    @State private var unitSeekImage: CGFloat = .zero

    init(
        value: Binding<T>,
        inRange: ClosedRange<T>,
        buffers: [CMTimeRange],
        activeFillColor: Color,
        fillColor: Color,
        emptyColor: Color,
        height: Double,
        thumbnails: WebVTT?,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
    ) {
        _value = value
        self.inRange = inRange
        self.buffers = buffers
        self.activeFillColor = activeFillColor
        self.fillColor = fillColor
        self.emptyColor = emptyColor
        self.height = height
        self.thumbnails = thumbnails
        self.onEditingChanged = onEditingChanged
    }

    var body: some View {
        let isActive = isFocused || isAdjusting

        ZStack(alignment: .center) {
            VStack {
                GeometryReader { geometry in
                    ZStack(alignment: .center) {
                        emptyColor
                        (isActive ? activeFillColor : fillColor)
                            .mask(alignment: .leading) {
                                Color.black.frame(width: max(geometry.size.width * CGFloat(localRealProgress), 0))
                            }

                        ForEach(buffers, id: \.self) { buffer in
                            if let start = buffer.start.seconds as? T, let end = buffer.end.seconds as? T {
                                emptyColor
                                    .mask(alignment: .leading) {
                                        let duration = if isActive {
                                            max(Double(end / inRange.upperBound) - Double(start / inRange.upperBound), 0)
                                        } else {
                                            max(Double(end / inRange.upperBound) - Double(localRealProgress), 0)
                                        }

                                        let point = CGPoint(
                                            x: isActive ? max(geometry.size.width * (Double(start / inRange.upperBound) + duration * 0.5), 0) : max(geometry.size.width * (Double(localRealProgress) + duration * 0.5), 0),
                                            y: (isActive ? height * 1.25 : height) * 0.5,
                                        )

                                        Color.black
                                            .frame(width: max(geometry.size.width * duration, 0))
                                            .position(x: point.x, y: point.y)
                                    }
                            }
                        }
                    }
                    .frame(height: isActive ? height * 1.25 : height, alignment: .center)
                    .animation(.easeInOut, value: isActive)
                    .contentShape(.capsule)
                    .clipShape(.capsule)
                    .focusable()
                    .focused($isFocused)
                    .onMoveCommand(perform: adjust)
                    .overlay {
                        if isActive, let cue = thumbnails?.cues.first(where: { TimeInterval(unitSeekImage) * TimeInterval(inRange.upperBound) > $0.timeStart && TimeInterval(unitSeekImage) * TimeInterval(inRange.upperBound) < $0.timeEnd }), let imageUrl = cue.imageUrl, let frame = cue.frame {
                            KFImage
                                .url(URL(string: imageUrl))
                                .placeholder {
                                    ProgressView().scaleEffect(0.75)
                                }
                                .resizable()
                                .cropping(rect: frame)
                                .loadTransition(.blurReplace, animation: .easeInOut)
                                .cancelOnDisappear(true)
                                .retry(NetworkRetryStrategy())
                                .scaledToFill()
                                .frame(width: frame.width, height: frame.height)
                                .clipShape(.rect(cornerRadius: 6))
                                .background(.ultraThickMaterial, in: .rect(cornerRadius: 6))
                                .overlay(.ultraThickMaterial, in: .rect(cornerRadius: 6).stroke(lineWidth: 1))
                                .overlay(alignment: .bottom) {
                                    Text((T(Float(unitSeekImage)) * inRange.upperBound).asTimeString(style: .positional))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(3)
                                }
                                .position(x: min(max(unitSeekImage * geometry.size.width, frame.width * 0.5), geometry.size.width - frame.width * 0.5), y: -(frame.height * 0.5) - 6)
                        }
                    }
                }

                HStack {
                    Text(progressDuration.asTimeString(style: .positional))
                    Spacer(minLength: 0)
                    Text("-" + (inRange.upperBound - progressDuration).asTimeString(style: .positional))
                }
                .font(.caption.monospacedDigit())
                .foregroundColor(isActive ? fillColor : emptyColor)
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: isFocused) {
            onEditingChanged(isFocused)
        }
        .onAppear {
            localRealProgress = getPrgPercentage(value)
            progressDuration = inRange.upperBound * localRealProgress
            unitSeekImage = CGFloat(localRealProgress)
        }
        .onChange(of: value) {
            localRealProgress = getPrgPercentage(value)
            progressDuration = inRange.upperBound * localRealProgress
            unitSeekImage = CGFloat(localRealProgress)
        }
    }

    private func adjust(_ direction: MoveCommandDirection) {
        let delta: T

        switch direction {
        case .left:
            delta = -stepAmount
        case .right:
            delta = stepAmount
        default:
            return
        }

        isAdjusting = true

        let newValue = max(min(value + delta, inRange.upperBound), inRange.lowerBound)
        value = newValue
        localRealProgress = getPrgPercentage(newValue)
        progressDuration = inRange.upperBound * localRealProgress

        withAnimation(.easeInOut) {
            unitSeekImage = CGFloat(localRealProgress)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            isAdjusting = false
        }
    }

    private var stepAmount: T {
        let range = inRange.upperBound - inRange.lowerBound

        if range > 1 {
            return max(range / 100, 10)
        }

        return max(range / 20, 0.01)
    }

    private func getPrgPercentage(_ value: T) -> T {
        let range = inRange.upperBound - inRange.lowerBound
        let correctedStartValue = value - inRange.lowerBound
        let percentage = correctedStartValue / range
        return percentage
    }
}

extension BinaryFloatingPoint {
    func asTimeString(style: DateComponentsFormatter.UnitsStyle) -> String {
        let formatter = DateComponentsFormatter()
        if self < 3600 {
            formatter.allowedUnits = [.minute, .second]
        } else {
            formatter.allowedUnits = [.hour, .minute, .second]
        }
        formatter.unitsStyle = style
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: TimeInterval(self)) ?? ""
    }
}
