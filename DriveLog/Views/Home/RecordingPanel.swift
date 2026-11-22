import SwiftUI

/// 记录中：速度表、距离、计时、停止按钮
struct RecordingPanel: View {
    @ObservedObject var recorder: TripRecorder
    let vehicleName: String
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(Theme.record)
                    .symbolEffect(.pulse, options: .repeating)
                Text("正在记录")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Label(vehicleName, systemImage: "car.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let now = timeline.date
                let elapsed = now.timeIntervalSince(recorder.startDate ?? now)
                VStack(spacing: 14) {
                    SpeedGauge(speedKmh: recorder.displaySpeed(at: now) * 3.6,
                               maxSpeedKmh: recorder.maxSpeed * 3.6)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)

                    HStack(spacing: 10) {
                        BigValue(title: "距离", value: Fmt.km(recorder.distance / 1000, decimals: 2),
                                 systemImage: "road.lanes", tint: Theme.distance)
                        BigValue(title: "用时", value: Fmt.clock(elapsed),
                                 systemImage: "timer", tint: Theme.duration)
                    }
                    HStack(spacing: 10) {
                        StatTile(title: "行驶均速", value: Fmt.speed(recorder.averageMovingSpeed),
                                 systemImage: "speedometer", tint: Theme.speed)
                        StatTile(title: "海拔", value: Fmt.altitude(recorder.currentAltitude),
                                 systemImage: "mountain.2.fill", tint: Theme.altitude)
                    }
                    gpsStatus
                }
            }

            Button(role: .destructive, action: onStop) {
                Label("停止并保存", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .glassButtonStyle(prominent: true)
            .tint(Theme.record)
            .controlSize(.large)
        }
        .card(tint: Theme.record.opacity(0.07))
    }

    private var gpsStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(gpsColor)
                .frame(width: 8, height: 8)
                .shadow(color: gpsColor.opacity(0.7), radius: 3)
            Text(gpsText)
            Spacer()
            Label("\(recorder.pointCount)", systemImage: "point.3.connected.trianglepath.dotted")
                .contentTransition(.numericText(value: Double(recorder.pointCount)))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .animation(.snappy, value: recorder.pointCount)
    }

    private var gpsText: String {
        guard let accuracy = recorder.horizontalAccuracy else { return "等待 GPS 信号…" }
        let value = Int(accuracy.rounded())
        if accuracy <= 20 { return "GPS 良好 · ±\(value) m" }
        if accuracy <= 50 { return "GPS 一般 · ±\(value) m" }
        return "GPS 信号弱 · ±\(value) m"
    }

    private var gpsColor: Color {
        guard let accuracy = recorder.horizontalAccuracy else { return .gray }
        if accuracy <= 20 { return .green }
        if accuracy <= 50 { return .orange }
        return .red
    }
}

private struct BigValue: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.numeric(28, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }
}
