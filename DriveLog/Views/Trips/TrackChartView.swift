import SwiftUI
import Charts

/// 速度 / 海拔曲线（数据已降采样）
struct TrackChartView: View {
    let samples: [ChartSample]
    let unit: String
    let color: Color
    var showsArea: Bool = true
    var includesZero: Bool = true
    /// 从下到上的渐变色（速度曲线用速度区间配色）
    var gradientColors: [Color]? = nil

    private var lineStyle: LinearGradient {
        LinearGradient(colors: gradientColors ?? [color, color], startPoint: .bottom, endPoint: .top)
    }

    private var areaStyle: LinearGradient {
        let colors = (gradientColors ?? [color, color]).map { $0.opacity(0.22) }
        return LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top)
    }

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
                    .foregroundStyle(areaStyle)
                    .interpolationMethod(.monotone)
                }
                LineMark(
                    x: .value("时间", sample.date),
                    y: .value(unit, sample.value)
                )
                .foregroundStyle(lineStyle)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }
            .chartYScale(domain: .automatic(includesZero: includesZero))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    AxisValueLabel()
                }
            }
            .chartYAxisLabel(unit)
            .frame(height: 210)
        }
    }
}
