import SwiftUI

/// 仪表盘弧线（可动画的进度）
struct GaugeArc: Shape {
    var startAngle: Double
    var sweep: Double
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: radius,
                    startAngle: .degrees(startAngle),
                    endAngle: .degrees(startAngle + sweep * max(0, min(1, progress))),
                    clockwise: false)
        return path
    }
}

/// 速度表：和 App 图标、地图图例同一套速度配色（<30 蓝 / 30–60 绿 / 60–90 黄 / 90–110 橙 / >110 红）
struct SpeedGauge: View {
    let speedKmh: Double
    var maxSpeedKmh: Double = 0
    var diameter: CGFloat = 250
    var lineWidth: CGFloat = 16

    private static let startAngle: Double = 135
    private static let sweep: Double = 270

    var body: some View {
        let scaleMax: Double = (maxSpeedKmh > 150 || speedKmh > 150) ? 220 : 160
        let fraction = min(max(speedKmh / scaleMax, 0), 1)
        let maxFraction = min(max(maxSpeedKmh / scaleMax, 0), 1)
        let radius = diameter / 2
        let rounded = Int(speedKmh.rounded())

        ZStack {
            // 底轨
            GaugeArc(startAngle: Self.startAngle, sweep: Self.sweep, progress: 1)
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .padding(lineWidth / 2)

            // 当前速度
            GaugeArc(startAngle: Self.startAngle, sweep: Self.sweep, progress: fraction)
                .stroke(gradient(scaleMax: scaleMax), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .padding(lineWidth / 2)
                .shadow(color: SpeedBand.band(forKmh: speedKmh).color.opacity(0.55), radius: 12)

            // 刻度
            ForEach(0..<41, id: \.self) { index in
                let isMajor = index % 10 == 0
                let angle = Angle.degrees(Self.startAngle + Self.sweep * Double(index) / 40)
                let tickRadius = radius - lineWidth - 9
                Capsule()
                    .fill(Color.primary.opacity(isMajor ? 0.45 : 0.15))
                    .frame(width: isMajor ? 2.5 : 1.5, height: isMajor ? 10 : 5)
                    .rotationEffect(angle - .degrees(90))
                    .offset(x: tickRadius * CGFloat(cos(angle.radians)),
                            y: tickRadius * CGFloat(sin(angle.radians)))
            }

            // 刻度数字
            ForEach(0..<5, id: \.self) { index in
                let value = Int(scaleMax / 4 * Double(index))
                let angle = Angle.degrees(Self.startAngle + Self.sweep * Double(index) / 4)
                let labelRadius = radius - lineWidth - 30
                Text("\(value)")
                    .font(.numeric(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .offset(x: labelRadius * CGFloat(cos(angle.radians)),
                            y: labelRadius * CGFloat(sin(angle.radians)))
            }

            // 本次最高速度标记
            if maxFraction > 0.005 {
                let angle = Angle.degrees(Self.startAngle + Self.sweep * maxFraction)
                let markRadius = radius - lineWidth / 2
                Capsule()
                    .fill(Theme.maxSpeed)
                    .frame(width: 4, height: lineWidth + 10)
                    .shadow(color: Theme.maxSpeed.opacity(0.6), radius: 4)
                    .rotationEffect(angle - .degrees(90))
                    .offset(x: markRadius * CGFloat(cos(angle.radians)),
                            y: markRadius * CGFloat(sin(angle.radians)))
            }

            // 中间的速度数字
            VStack(spacing: -6) {
                Text("\(rounded)")
                    .font(.numeric(diameter * 0.32, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(rounded)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("km/h")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .offset(y: 4)

            // 底部开口处：最高速度
            VStack(spacing: 0) {
                Text("最高")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(Int(maxSpeedKmh.rounded()))")
                    .font(.numeric(15, weight: .bold))
                    .foregroundStyle(Theme.maxSpeed)
                    .contentTransition(.numericText(value: maxSpeedKmh.rounded()))
            }
            .offset(y: radius * 0.72)
        }
        .frame(width: diameter, height: diameter)
        .animation(.spring(response: 0.7, dampingFraction: 0.8), value: fraction)
        .animation(.snappy, value: rounded)
        .animation(.snappy, value: Int(maxSpeedKmh.rounded()))
    }

    private func gradient(scaleMax: Double) -> AngularGradient {
        func at(_ kmh: Double) -> CGFloat { CGFloat(min(1, kmh / scaleMax)) }
        let stops: [Gradient.Stop] = [
            .init(color: SpeedBand.crawl.color, location: 0),
            .init(color: SpeedBand.crawl.color, location: at(15)),
            .init(color: SpeedBand.city.color, location: at(45)),
            .init(color: SpeedBand.suburban.color, location: at(75)),
            .init(color: SpeedBand.highway.color, location: at(100)),
            .init(color: SpeedBand.fast.color, location: at(125)),
            .init(color: SpeedBand.fast.color, location: 1)
        ]
        return AngularGradient(gradient: Gradient(stops: stops),
                               center: .center,
                               startAngle: .degrees(Self.startAngle),
                               endAngle: .degrees(Self.startAngle + Self.sweep))
    }
}
