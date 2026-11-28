import Foundation

/// 每段行程自动生成 GPX 和原始 CSV，放在 Documents/行程轨迹/（「文件」App 可见）
enum TripExporter {
    private static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func baseName(id: UUID, startDate: Date) -> String {
        "\(fileStamp.string(from: startDate))_\(id.uuidString.prefix(8))"
    }

    static func gpxURL(id: UUID, startDate: Date) -> URL {
        AppPaths.tripExportsDirectory.appendingPathComponent(baseName(id: id, startDate: startDate) + ".gpx")
    }

    static func csvURL(id: UUID, startDate: Date) -> URL {
        AppPaths.tripExportsDirectory.appendingPathComponent(baseName(id: id, startDate: startDate) + ".csv")
    }

    static func export(trip: Trip, points: [TrackPoint]) {
        export(id: trip.id, startDate: trip.startDate, points: points)
    }

    static func export(id: UUID, startDate: Date, points: [TrackPoint]) {
        guard !points.isEmpty else { return }
        let name = "行程 \(Fmt.dateTimeFull.string(from: startDate))"
        do {
            try gpx(points: points, name: name).write(to: gpxURL(id: id, startDate: startDate), atomically: true, encoding: .utf8)
            try csv(points: points).write(to: csvURL(id: id, startDate: startDate), atomically: true, encoding: .utf8)
        } catch {
            print("导出行程文件失败：\(error)")
        }
    }

    /// 文件不存在时补生成（例如从备份恢复之后）
    static func ensureExports(id: UUID, startDate: Date, points: [TrackPoint]) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: gpxURL(id: id, startDate: startDate).path)
            || !fm.fileExists(atPath: csvURL(id: id, startDate: startDate).path) {
            export(id: id, startDate: startDate, points: points)
        }
    }

    static func deleteExports(id: UUID, startDate: Date) {
        try? FileManager.default.removeItem(at: gpxURL(id: id, startDate: startDate))
        try? FileManager.default.removeItem(at: csvURL(id: id, startDate: startDate))
    }

    static func gpx(points: [TrackPoint], name: String) -> String {
        var lines: [String] = []
        lines.reserveCapacity(points.count + 12)
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<gpx version=\"1.1\" creator=\"行车记录\" xmlns=\"http://www.topografix.com/GPX/1/1\">")
        lines.append("  <metadata>")
        lines.append("    <name>\(xmlEscape(name))</name>")
        if let first = points.first {
            lines.append("    <time>\(iso.string(from: first.timestamp))</time>")
        }
        lines.append("  </metadata>")
        lines.append("  <trk>")
        lines.append("    <name>\(xmlEscape(name))</name>")
        lines.append("    <trkseg>")
        for p in points {
            var line = "      <trkpt lat=\"\(String(format: "%.7f", p.latitude))\" lon=\"\(String(format: "%.7f", p.longitude))\">"
            if p.hasValidAltitude {
                line += "<ele>\(String(format: "%.1f", p.altitude))</ele>"
            }
            line += "<time>\(iso.string(from: p.timestamp))</time></trkpt>"
            lines.append(line)
        }
        lines.append("    </trkseg>")
        lines.append("  </trk>")
        lines.append("</gpx>")
        return lines.joined(separator: "\n") + "\n"
    }

    static func csv(points: [TrackPoint]) -> String {
        var lines: [String] = ["time,latitude,longitude,altitude_m,horizontal_accuracy_m,vertical_accuracy_m,speed_kmh,speed_accuracy_mps,course_deg"]
        lines.reserveCapacity(points.count + 1)
        for p in points {
            let speedKmh = p.speed >= 0 ? String(format: "%.1f", p.speed * 3.6) : ""
            let speedAcc = p.speedAccuracy >= 0 ? String(format: "%.2f", p.speedAccuracy) : ""
            let altitude = p.verticalAccuracy > 0 ? String(format: "%.1f", p.altitude) : ""
            let course = p.course >= 0 ? String(format: "%.1f", p.course) : ""
            lines.append([
                iso.string(from: p.timestamp),
                String(format: "%.7f", p.latitude),
                String(format: "%.7f", p.longitude),
                altitude,
                String(format: "%.1f", p.horizontalAccuracy),
                String(format: "%.1f", p.verticalAccuracy),
                speedKmh,
                speedAcc,
                course
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// 合并导出时每段行程的名字用的时间
    static func displayStamp(_ date: Date) -> String {
        displayFormatter.string(from: date)
    }

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f
    }()

    /// 多段行程合成一个 GPX：每段行程一个 <trk>
    static func gpx(tracks: [(name: String, points: [TrackPoint])], name: String) -> String {
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<gpx version=\"1.1\" creator=\"行车记录\" xmlns=\"http://www.topografix.com/GPX/1/1\">")
        lines.append("  <metadata>")
        lines.append("    <name>\(xmlEscape(name))</name>")
        if let first = tracks.first(where: { !$0.points.isEmpty })?.points.first {
            lines.append("    <time>\(iso.string(from: first.timestamp))</time>")
        }
        lines.append("  </metadata>")
        for track in tracks where !track.points.isEmpty {
            lines.append("  <trk>")
            lines.append("    <name>\(xmlEscape(track.name))</name>")
            lines.append("    <trkseg>")
            for p in track.points {
                var line = "      <trkpt lat=\"\(String(format: "%.7f", p.latitude))\" lon=\"\(String(format: "%.7f", p.longitude))\">"
                if p.hasValidAltitude {
                    line += "<ele>\(String(format: "%.1f", p.altitude))</ele>"
                }
                line += "<time>\(iso.string(from: p.timestamp))</time></trkpt>"
                lines.append(line)
            }
            lines.append("    </trkseg>")
            lines.append("  </trk>")
        }
        lines.append("</gpx>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// 多段行程合成一个 CSV：和单段的列一样，前面多一列 trip（行程名）
    static func csv(tracks: [(name: String, points: [TrackPoint])]) -> String {
        var lines: [String] = []
        for (index, track) in tracks.enumerated() {
            let single = csv(points: track.points).split(separator: "\n", omittingEmptySubsequences: true)
            for (row, line) in single.enumerated() {
                if row == 0 {
                    if index == 0 { lines.append("trip," + line) }
                } else {
                    lines.append("\"\(track.name)\"," + line)
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
