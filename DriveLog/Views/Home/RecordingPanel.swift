import SwiftUI

/// 记录中：大号实时速度、距离、计时、停止按钮
struct RecordingPanel: View {
    @ObservedObject var recorder: TripRecorder
    let vehicleName: String
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
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
                let speedKmh = Int((recorder.displaySpeed(at: now) * 3.6).rounded())
                let elapsed = now.timeIntervalSince(recorder.startDate ?? now)
                VStack(spacing: 10) {
                    VStack(spacing: 0) {
                        Text("\(speedKmh)")
                            .font(.system(size: 108, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text("km/h")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        BigValue(title: "距离", value: Fmt.km(recorder.distance / 1000, decimals: 2))
                        BigValue(title: "计时", value: Fmt.clock(elapsed))
                    }
                    HStack(spacing: 10) {
                        StatTile(title: "最高", value: Fmt.speed(recorder.maxSpeed), systemImage: "bolt.fill", tint: .orange)
                        StatTile(title: "均速", value: Fmt.speed(recorder.averageMovingSpeed), systemImage: "speedometer", tint: .blue)
                        StatTile(title: "海拔", value: Fmt.altitude(recorder.currentAltitude), systemImage: "mountain.2.fill", tint: .green)
                    }
                    gpsStatus(now: now)
                }
            }

            Button(role: .destructive, action: onStop) {
                Label("停止并保存", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .glassButtonStyle(prominent: true)
            .tint(.red)
            .controlSize(.large)
        }
        .card(tint: Color.red.opacity(0.10))
    }

    @ViewBuilder
    private func gpsStatus(now: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "location.fill")
            if let accuracy = recorder.horizontalAccuracy {
                Text(accuracy <= 20 ? "GPS 良好 ±\(Int(accuracy)) m" : (accuracy <= 50 ? "GPS 一般 ±\(Int(accuracy)) m" : "GPS 信号弱 ±\(Int(accuracy)) m"))
            } else {
                Text("等待 GPS 信号…")
            }
            Spacer()
            Text("\(recorder.pointCount) 个点")
        }
        .font(.caption)
        .foregroundStyle(gpsColor)
    }

    private var gpsColor: Color {
        guard let accuracy = recorder.horizontalAccuracy else { return .secondary }
        if accuracy <= 20 { return .green }
        if accuracy <= 50 { return .orange }
        return .red
    }
}

private struct BigValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
        )
    }
}
