//
//  WarpGaugeView.swift
//  Warp
//

import SwiftUI

public struct WarpGaugeView: View {
    let speedMbps: Double
    let phase: SpeedtestPhase
    let unit: SpeedUnit
    let size: CGFloat
    let showTicks: Bool

    // 270-degree radial arc opening at the bottom
    // Start angle: 135° (bottom-left, 7:30)
    // End angle: 405° (bottom-right, 4:30)
    // Top dead center: 270° (12:00)
    private static let startAngle = Angle(degrees: 135)
    private static let endAngle = Angle(degrees: 405)
    private static let totalAngleDegrees: Double = 270.0

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
        showTicks: Bool = true
    ) {
        self.speedMbps = speedMbps
        self.phase = phase
        self.unit = unit
        self.size = size
        self.showTicks = showTicks
    }

    private var fraction: Double {
        Self.speedToFraction(speedMbps)
    }

    private var needleAngle: Angle {
        Angle(degrees: Self.startAngle.degrees + (Self.totalAngleDegrees * fraction))
    }

    private var isUpload: Bool {
        if case .uploading = phase { return true }
        return false
    }

    private var activeGradient: AngularGradient {
        if isUpload {
            return AngularGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.85, green: 0.65, blue: 1.0),
                    Color(red: 0.70, green: 0.40, blue: 0.95),
                    Color(red: 0.55, green: 0.20, blue: 0.82),
                    Color(red: 0.35, green: 0.08, blue: 0.60)
                ]),
                center: .center,
                startAngle: Self.startAngle,
                endAngle: Self.endAngle
            )
        } else {
            return AngularGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.40, green: 0.95, blue: 0.60),
                    Color(red: 0.20, green: 0.85, blue: 0.45),
                    Color(red: 0.10, green: 0.65, blue: 0.30),
                    Color(red: 0.05, green: 0.45, blue: 0.20)
                ]),
                center: .center,
                startAngle: Self.startAngle,
                endAngle: Self.endAngle
            )
        }
    }

    private var needleColor: Color {
        if isUpload {
            return Color(red: 0.85, green: 0.60, blue: 1.0)
        } else if speedMbps > 0 {
            return Color(red: 0.35, green: 0.95, blue: 0.55)
        } else {
            return Color.white.opacity(0.8)
        }
    }

    public var body: some View {
        ZStack {
            GaugeArc(startAngle: Self.startAngle, endAngle: Self.endAngle)
                .stroke(
                    Color.white.opacity(0.12),
                    style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round)
                )

            if fraction > 0.001 {
                GaugeArc(
                    startAngle: Self.startAngle,
                    endAngle: Angle(degrees: Self.startAngle.degrees + (Self.totalAngleDegrees * fraction))
                )
                .stroke(
                    activeGradient,
                    style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round)
                )
                .animation(.spring(response: 0.35, dampingFraction: 0.72), value: fraction)
            }

            if showTicks {
                ticksView
            }

            GaugeNeedle(angle: needleAngle, radius: size * 0.27)
                .stroke(
                    LinearGradient(
                        colors: [.white, needleColor],
                        startPoint: .bottom,
                        endPoint: .top
                    ),
                    style: StrokeStyle(lineWidth: max(1.5, size * 0.018), lineCap: .round)
                )
                .shadow(color: needleColor.opacity(0.6), radius: 3)
                .animation(.spring(response: 0.35, dampingFraction: 0.72), value: needleAngle)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white, Color(nsColor: .darkGray)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.045
                    )
                )
                .frame(width: size * 0.09, height: size * 0.09)
                .shadow(color: .black.opacity(0.5), radius: 2)

            VStack(spacing: 0) {
                Text(unit.formatValueOnly(mbps: speedMbps))
                    .font(.system(size: size * 0.122, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.white)

                Text(unit.rawValue)
                    .font(.system(size: size * 0.048, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .offset(y: size * 0.285)
        }
        .frame(width: size, height: size)
    }

    private var ticksView: some View {
        ZStack {
            ForEach(0...12, id: \.self) { i in
                let tickDeg = Self.startAngle.degrees + (Double(i) * 22.5)
                let rad = tickDeg * .pi / 180.0
                let isMajor = (i % 2 == 0)
                let r1 = isMajor ? size * 0.33 : size * 0.35
                let r2 = size * 0.38
                let center = CGPoint(x: size / 2, y: size / 2)

                Path { path in
                    let p1 = CGPoint(x: center.x + r1 * cos(rad), y: center.y + r1 * sin(rad))
                    let p2 = CGPoint(x: center.x + r2 * cos(rad), y: center.y + r2 * sin(rad))
                    path.move(to: p1)
                    path.addLine(to: p2)
                }
                .stroke(
                    Color.white.opacity(isMajor ? 0.40 : 0.20),
                    lineWidth: max(1.0, isMajor ? size * 0.013 : size * 0.008)
                )
            }

            labelsView
        }
    }

    private var labelsView: some View {
        let center = CGPoint(x: size / 2, y: size / 2)
        let milestones: [(text: String, deg: Double)] = [
            ("0", 135.0),
            ("50", 225.0),
            ("100", 270.0),
            ("250", 315.0),
            ("1G", 405.0)
        ]

        return ForEach(milestones, id: \.text) { item in
            let rad = item.deg * .pi / 180.0
            let rText = (item.text == "0" || item.text == "1G") ? size * 0.225 : (item.text == "100" ? size * 0.22 : size * 0.245)
            let point = CGPoint(x: center.x + rText * cos(rad), y: center.y + rText * sin(rad))
            Text(item.text)
                .font(.system(size: max(8, size * 0.044), weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
                .position(point)
        }
    }
}

// MARK: - Shapes

private struct GaugeArc: Shape {
    var startAngle: Angle
    var endAngle: Angle

    var animatableData: Double {
        get { endAngle.degrees }
        set { endAngle = Angle(degrees: newValue) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * 0.82
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

private struct GaugeNeedle: Shape {
    var angle: Angle
    var radius: CGFloat

    var animatableData: Double {
        get { angle.degrees }
        set { angle = Angle(degrees: newValue) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rad = angle.degrees * .pi / 180.0
        let tip = CGPoint(
            x: center.x + radius * cos(rad),
            y: center.y + radius * sin(rad)
        )
        path.move(to: center)
        path.addLine(to: tip)
        return path
    }
}
