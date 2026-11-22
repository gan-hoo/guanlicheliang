import Foundation

struct XY {
    var x: Double
    var y: Double
}

/// 图表降采样：Largest-Triangle-Three-Buckets，保留曲线形状
enum Downsampler {
    static func lttb(_ data: [XY], threshold: Int) -> [XY] {
        let n = data.count
        guard threshold >= 3, n > threshold else { return data }

        var sampled: [XY] = []
        sampled.reserveCapacity(threshold)
        sampled.append(data[0])

        let bucketSize = Double(n - 2) / Double(threshold - 2)
        var a = 0

        for i in 0..<(threshold - 2) {
            var avgStart = Int(floor(Double(i + 1) * bucketSize)) + 1
            let avgEnd = min(Int(floor(Double(i + 2) * bucketSize)) + 1, n)
            if avgStart >= avgEnd { avgStart = avgEnd - 1 }
            var avgX = 0.0
            var avgY = 0.0
            for j in avgStart..<avgEnd {
                avgX += data[j].x
                avgY += data[j].y
            }
            let count = Double(avgEnd - avgStart)
            avgX /= count
            avgY /= count

            let rangeStart = Int(floor(Double(i) * bucketSize)) + 1
            let rangeEnd = max(rangeStart + 1, min(Int(floor(Double(i + 1) * bucketSize)) + 1, n - 1))
            let pointA = data[a]
            var maxArea = -1.0
            var maxIndex = rangeStart
            for j in rangeStart..<rangeEnd {
                let area = abs((pointA.x - avgX) * (data[j].y - pointA.y) - (pointA.x - data[j].x) * (avgY - pointA.y)) * 0.5
                if area > maxArea {
                    maxArea = area
                    maxIndex = j
                }
            }
            sampled.append(data[maxIndex])
            a = maxIndex
        }

        sampled.append(data[n - 1])
        return sampled
    }
}
