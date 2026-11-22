import SwiftUI
import Charts

/// 速度 / 海拔曲线（数据已降采样）
struct TrackChartView: View {
    let samples: [ChartSample]
    let unit: String
    let color: Color
    var showsArea: Bool = true
    var includesZero: Bool = true

    var body: some View {
        if samples.count < 2 {
            Text("数据不足")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            Chart(samples) { sample in
                if showsArea {
                    AreaMark(
                        x: .value("时间", sample.date),
                        y: .value(unit, sample.value)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)],
                                       startPoint: .top,
                                       endPoint: .bottom)
                    )
                    .interpolationMethod(.monotone)
                }
                LineMark(
                    x: .value("时间", sample.date),
                    y: .value(unit, sample.value)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            }
            .chartYScale(domain: .automatic(includesZero: includesZero))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .chartYAxisLabel(unit)
            .frame(height: 200)
        }
    }
}
