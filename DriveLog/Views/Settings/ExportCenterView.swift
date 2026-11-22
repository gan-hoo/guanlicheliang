import SwiftUI
import SwiftData

/// 导出加油、费用、行程概要为 CSV
struct ExportCenterView: View {
    @Environment(\.modelContext) private var context
    @State private var lastExport: URL?
    @State private var errorMessage: String?
    @State private var exportURL: URL?

    var body: some View {
        List {
            Section {
                Button {
                    run { try CSVExporter.exportFuel(context: context) }
                } label: {
                    Label("导出加油记录 CSV", systemImage: "fuelpump")
                }
                Button {
                    run { try CSVExporter.exportExpenses(context: context) }
                } label: {
                    Label("导出费用记录 CSV", systemImage: "creditcard")
                }
                Button {
                    run { try CSVExporter.exportTrips(context: context) }
                } label: {
                    Label("导出行程概要 CSV", systemImage: "map")
                }
            } footer: {
                Text("文件保存在「文件」→ 我的 iPhone → 行车记录 → 数据导出，UTF-8 编码，Excel 可直接打开。每段行程的 GPX 和原始 CSV 在「行程轨迹」文件夹。")
            }

            if let lastExport {
                Section("刚刚导出") {
                    Text(lastExport.lastPathComponent)
                        .font(.subheadline)
                    ShareLink(item: lastExport) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        exportURL = lastExport
                    } label: {
                        Label("存到…", systemImage: "folder")
                    }
                }
            }
        }
        .navigationTitle("导出 CSV")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(get: { exportURL.map(IdentifiableURL.init) },
                             set: { exportURL = $0?.url })) { item in
            DocumentExportPicker(url: item.url)
                .ignoresSafeArea()
        }
        .alert("导出失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func run(_ action: () throws -> URL) {
        do {
            lastExport = try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
