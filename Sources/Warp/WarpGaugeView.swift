//
//  WarpGaugeView.swift
//  Warp
//

import AppKit
@_weakLinked import DroppyKit
import SwiftUI

public struct WarpGaugeView: View {
    let speedMbps: Double
    let phase: SpeedtestPhase
    let unit: SpeedUnit
    let size: CGFloat
    let showTicks: Bool
    let progress: Double
    let interfaceIcon: String
    let usesAdaptiveForegrounds: Bool
    let onRaisedCard: Bool

    // 270-degree radial arc opening at the bottom
    // Start angle: 135° (bottom-left, 7:30)
    // End angle: 405° (bottom-right, 4:30)
    // Top dead center: 270° (12:00)
    private static let startAngle = Angle(degrees: 135)
    private static let endAngle = Angle(degrees: 405)
    private static let totalAngleDegrees: Double = 270.0
    private static let arcRadiusFactor: CGFloat = 0.45

    // 4 evenly spaced progress dots along the 90° bottom opening (left-to-right)
    private static let bottomDotAngles: [Double] = [117.0, 99.0, 81.0, 63.0]

    // Equal 45° sectors around the 270° arc (6 equal sectors)
    private static let scalePoints: [(speed: Double, frac: Double)] = [
        (0.0, 0.0),
        (10.0, 1.0 / 6.0),
        (50.0, 2.0 / 6.0),
        (100.0, 3.0 / 6.0),   // Top dead center (12 o'clock)
        (250.0, 4.0 / 6.0),
        (500.0, 5.0 / 6.0),
        (1000.0, 1.0)
    ]

    private static func speedToFraction(_ speed: Double) -> Double {
        if speed <= 0 { return 0 }
        if speed >= 1000 { return 1.0 }
        for i in 0..<(scalePoints.count - 1) {
            let p0 = scalePoints[i]
            let p1 = scalePoints[i + 1]
            if speed >= p0.speed && speed <= p1.speed {
                let t = (speed - p0.speed) / (p1.speed - p0.speed)
                return p0.frac + t * (p1.frac - p0.frac)
            }
        }
        return 1.0
    }

    public init(
        speedMbps: Double,
        phase: SpeedtestPhase,
        unit: SpeedUnit = .mbps,
        size: CGFloat = 160,
        showTicks: Bool = false,
        progress: Double = 0.0,
        interfaceIcon: String = "wifi",
        usesAdaptiveForegrounds: Bool = false,
        onRaisedCard: Bool = false
    ) {
        self.speedMbps = speedMbps
        self.phase = phase
        self.unit = unit
        self.size = size
        self.showTicks = showTicks
        self.progress = progress
        self.interfaceIcon = interfaceIcon
        self.usesAdaptiveForegrounds = usesAdaptiveForegrounds
        self.onRaisedCard = onRaisedCard
    }

    private var fraction: Double {
        Self.speedToFraction(speedMbps)
    }

    private var clampedProgress: Double {
        min(1.0, max(0.0, progress))
    }

    private var strokeWidth: CGFloat {
        max(6.0, size * 0.088)
    }

    private var primaryInk: Color {
        usesAdaptiveForegrounds ? AdaptiveColors.primaryTextAuto : .white
    }

    private var trackColor: Color {
        let darkWhite: CGFloat = onRaisedCard ? 0.22 : 0.14
        if usesAdaptiveForegrounds {
            return Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor(white: isDark ? darkWhite : 0.86, alpha: 1.0)
            })
        }
        return Color(white: Double(darkWhite))
    }

    private var activeArcColor: Color {
        switch phase {
        case .uploading:
            return .purple
        case .failed:
            return .red
        case .downloading, .completed:
            return .green
        case .locating, .pinging:
            return Color(white: onRaisedCard ? 0.50 : 0.45)
        case .idle:
            return speedMbps > 0 ? .green : Color(white: onRaisedCard ? 0.32 : 0.26)
        }
    }

    private var wifiVariableValue: Double {
        guard speedMbps > 0 else { return 0.0 }
        return min(1.0, max(0.15, fraction))
    }

    public var body: some View {
        ZStack {
            // Layer 1 (Optional ticks behind track; default false for clean modern arc)
            if showTicks {
                ticksView
            }

            // Layer 2: Opaque flat background track
            GaugeArc(
                startAngle: Self.startAngle,
                endAngle: Self.endAngle,
                radiusFactor: Self.arcRadiusFactor
            )
            .stroke(
                trackColor,
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )

            // Layer 3: Opaque flat progress arc
            GaugeArc(
                startAngle: Self.startAngle,
                endAngle: Angle(degrees: Self.startAngle.degrees + (Self.totalAngleDegrees * max(0.0, fraction))),
                radiusFactor: Self.arcRadiusFactor
            )
            .stroke(
                activeArcColor,
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )
            .opacity(fraction > 0.001 ? 1.0 : 0.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.78), value: fraction)

            // Layer 4: Centered network interface icon (Wi-Fi with dynamic variableValue, or Ethernet cable/connector)
            Group {
                if interfaceIcon == "wifi" {
                    Image(systemName: "wifi", variableValue: wifiVariableValue)
                        .font(.system(size: size * 0.30, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(primaryInk)
                        .animation(.easeInOut(duration: 0.2), value: wifiVariableValue)
                } else {
                    Image(systemName: interfaceIcon)
                        .font(.system(size: size * 0.30, weight: .semibold))
                        .foregroundStyle(primaryInk)
                }
            }

            // Layer 5: Bottom duration progress dots (elapsed vs. remaining time)
            bottomProgressDotsView
        }
        .frame(width: size, height: size)
    }

    private var ticksView: some View {
        let center = CGPoint(x: size / 2, y: size / 2)
        let arcRadius = size * Self.arcRadiusFactor
        let trackInnerRadius = arcRadius - (strokeWidth / 2)

        return ForEach(0...12, id: \.self) { i in
            let tickDeg = Self.startAngle.degrees + (Double(i) * 22.5)
            let rad = tickDeg * .pi / 180.0
            let isMajor = (i % 2 == 0)
            let r1 = isMajor ? (trackInnerRadius - size * 0.056) : (trackInnerRadius - size * 0.032)
            let r2 = arcRadius

            Path { path in
                let p1 = CGPoint(x: center.x + r1 * cos(rad), y: center.y + r1 * sin(rad))
                let p2 = CGPoint(x: center.x + r2 * cos(rad), y: center.y + r2 * sin(rad))
                path.move(to: p1)
                path.addLine(to: p2)
            }
            .stroke(
                primaryInk.opacity(isMajor ? 0.30 : 0.16),
                style: StrokeStyle(
                    lineWidth: max(1.0, isMajor ? size * 0.014 : size * 0.009),
                    lineCap: .round
                )
            )
        }
    }

    private var bottomProgressDotsView: some View {
        let center = CGPoint(x: size / 2, y: size / 2)
        let arcRadius = size * Self.arcRadiusFactor
        let dotDiameter = max(5.0, strokeWidth * 0.84)
        let segment = 1.0 / Double(Self.bottomDotAngles.count)

        return ForEach(Array(Self.bottomDotAngles.enumerated()), id: \.offset) { index, deg in
            let rad = deg * .pi / 180.0
            let point = CGPoint(
                x: center.x + arcRadius * cos(rad),
                y: center.y + arcRadius * sin(rad)
            )
            let dotProgress = dotFillLevel(for: index, segment: segment)

            ZStack {
                Circle()
                    .fill(trackColor)

                if dotProgress > 0 {
                    Circle()
                        .fill(primaryInk.opacity(0.92 * dotProgress))
                }
            }
            .frame(width: dotDiameter, height: dotDiameter)
            .position(point)
            .animation(.easeInOut(duration: 0.22), value: dotProgress)
        }
    }

    private func dotFillLevel(for index: Int, segment: Double) -> Double {
        if phase == .completed {
            return 1.0
        }
        guard phase.isTesting else {
            return 0.0
        }
        let start = Double(index) * segment
        return min(1.0, max(0.0, (clampedProgress - start) / segment))
    }
}

// MARK: - Shapes

private struct GaugeArc: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var radiusFactor: CGFloat

    var animatableData: Double {
        get { endAngle.degrees }
        set { endAngle = Angle(degrees: newValue) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * radiusFactor
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}
