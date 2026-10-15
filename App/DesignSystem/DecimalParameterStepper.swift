import SwiftUI
import BlurCore

// OWNER: METRO-COMPONENTS (frozen initialiser, ARCHITECTURE §5.14; Metro §9, §18 "Stable integer parameter"; METRO §C.3;
// SPEC §9.1). The native, accessible twin of a magnitude crown: a native `Stepper` over whole steps of a decimal quantity
// (σ in 0.1-px steps), labelled in the domain unit. It keeps the starter Stepper's behavioural contract:
//   • the step arithmetic runs on whole step counts (an Int), so 0.1-px steps never drift (0.3 + 0.1 + … stays exact);
//   • the Binding is written BEFORE `onAcceptedChange` (a post-write notification: never publish the change twice);
//   • a clamped or unchanged value emits nothing (no callback, no haptic);
//   • display precision = spoken precision = the step (Metro contract A.6), formatted by BlurCore's `NumberStyle`;
//   • native held repeat keeps working while the instrument redraws (stable identity; never inside a TimelineView);
//   • the full capsule owns touches that begin on it (`instrumentControlOwnsTouches`);
//   • accessibility sizes stack the label above the value instead of shrinking it (Metro §17).
public struct DecimalParameterStepper: View {
    @Binding private var value: Double
    private let label: String
    private let range: ClosedRange<Double>
    private let step: Double
    private let decimals: Int
    private let unit: String
    private let spokenUnit: String
    private let onAcceptedChange: (Double) -> Void
    @ScaledMetric(relativeTo: .caption2) private var labelSize = InstrumentTypeScale.captionMinimum
    @ScaledMetric(relativeTo: .body) private var valueSize = InstrumentTypeScale.stepperValue
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.instrumentHapticsEnabled) private var hapticsEnabled

    public init(_ label: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, decimals: Int,
                unit: String, spokenUnit: String, onAcceptedChange: @escaping (Double) -> Void = { _ in }) {
        self.label = label; self._value = value; self.range = range; self.step = step; self.decimals = decimals
        self.unit = unit; self.spokenUnit = spokenUnit; self.onAcceptedChange = onAcceptedChange
    }

    private var style: NumberStyle { NumberStyle.decimals(Swift.max(0, decimals), unit: unit.isEmpty ? nil : unit,
                                                          spokenUnit: spokenUnit.isEmpty ? nil : spokenUnit) }
    private var displayText: String { style.text(value) + (unit.isEmpty ? "" : " " + unit) }

    public var body: some View {
        Stepper {
            Group {
                if dynamicType.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) { parameterLabel; parameterValue }
                } else {
                    HStack(spacing: 10) { parameterLabel; parameterValue }
                }
            }
        } onIncrement: {
            adjust(1)
        } onDecrement: {
            adjust(-1)
        }
        .frame(minHeight: InstrumentMetrics.stepperHeight)
        .padding(.horizontal, 14)
        .background(InstrumentPalette.content.opacity(InstrumentOpacity.panelFill), in: .capsule)
        .overlay {
            Capsule().strokeBorder(InstrumentPalette.actionCyan.opacity(InstrumentOpacity.stepperBorder),
                                   lineWidth: InstrumentMetrics.panelStroke)
                .allowsHitTesting(false)
        }
        .instrumentControlOwnsTouches(identifier: "decimalStepper")
        .accessibilityValue(style.spoken(value))
        .accessibilityHint("Hold plus or minus for repeated adjustments.")
        .accessibilityIdentifier("decimalStepper.\(label)")
    }

    private var parameterLabel: some View {
        Text(label)
            .font(.system(size: labelSize, weight: .medium, design: .monospaced))
            .tracking(InstrumentTypeScale.stepperLabelTracking)
            .foregroundStyle(InstrumentPalette.secondaryInk)
            .lineLimit(dynamicType.isAccessibilitySize ? 2 : 1)
    }

    private var parameterValue: some View {
        Text(displayText)
            .font(.system(size: valueSize, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(InstrumentPalette.actionCyan)
            .lineLimit(1)
            .minimumScaleFactor(dynamicType.isAccessibilitySize ? 1 : 0.7)
    }

    private func adjust(_ direction: Int) {
        guard let next = DecimalParameterStepper.stepped(value, direction: direction, step: step, decimals: decimals, in: range) else {
            return   // clamped or unchanged: no event (Metro §9)
        }
        value = next
        // Post-write notification; the Binding already owns the value change.
        onAcceptedChange(next)
        if hapticsEnabled { InstrumentDetentHaptics.shared.play(InstrumentDetentKind(role: .fine, direction: direction)) }
    }

    /// One accepted step from `value`, on the grid of whole `step`s, rounded to `decimals` and clamped to `range`;
    /// nil when the result equals `value` (a range end, or a zero step). Pure; tested on the phone.
    nonisolated public static func stepped(_ value: Double, direction: Int, step: Double, decimals: Int,
                               in range: ClosedRange<Double>) -> Double? {
        guard step > 0, step.isFinite, value.isFinite, direction != 0 else { return nil }
        let index = (value / step).rounded() + Double(direction > 0 ? 1 : -1)
        let scale = pow(10, Double(Swift.max(0, decimals)))
        var next = ((index * step) * scale).rounded() / scale
        next = Swift.min(Swift.max(next, range.lowerBound), range.upperBound)
        return abs(next - value) < 0.5 / scale ? nil : next
    }
}
