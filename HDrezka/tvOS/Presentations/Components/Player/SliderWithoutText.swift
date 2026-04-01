import SwiftUI

struct SliderWithoutText<T: BinaryFloatingPoint>: View {
    @Binding var value: T
    let inRange: ClosedRange<T>
    let activeFillColor: Color
    let fillColor: Color
    let emptyColor: Color
    let height: CGFloat
    let onEditingChanged: (Bool) -> Void

    @State private var localRealProgress: T = 0
    @State private var isAdjusting: Bool = false
    @FocusState private var isFocused: Bool

    init(
        value: Binding<T>,
        inRange: ClosedRange<T>,
        activeFillColor: Color,
        fillColor: Color,
        emptyColor: Color,
        height: CGFloat,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
    ) {
        _value = value
        self.inRange = inRange
        self.activeFillColor = activeFillColor
        self.fillColor = fillColor
        self.emptyColor = emptyColor
        self.height = height
        self.onEditingChanged = onEditingChanged
    }

    var body: some View {
        let isActive = isFocused || isAdjusting

        GeometryReader { geometry in
            ZStack(alignment: .center) {
                ZStack(alignment: .center) {
                    emptyColor
                    (isActive ? activeFillColor : fillColor)
                        .mask(alignment: .leading) {
                            Color.black
                                .frame(width: max(geometry.size.width * CGFloat(localRealProgress), 0))
                        }
                }
                .frame(height: isActive ? height * 1.25 : height, alignment: .center)
                .animation(.easeInOut, value: isActive)
                .contentShape(.capsule)
                .clipShape(.capsule)
            }
            .focusable()
            .focused($isFocused)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onMoveCommand(perform: adjust)
            .onChange(of: isFocused) {
                onEditingChanged(isFocused)
            }
            .onAppear {
                localRealProgress = getPrgPercentage(value)
            }
            .onChange(of: value) {
                localRealProgress = getPrgPercentage(value)
            }
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
