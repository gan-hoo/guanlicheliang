import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

/// 备份与恢复：一键导出全部数据（车辆、加油、费用、行程、轨迹、照片）为一个文件
struct BackupView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var recorder = TripRecorder.shared

    @State private var backups: [URL] = []
    @State private var isWorking = false
    @State private var message: String?
    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var pendingRestoreURL: URL?
    @State private var pendingRestoreSummary: String = ""
    @State private var restoreIsSecurityScoped = false

    var body: some View {
        List {
            Section {
                Button {
                    Task { await createBackup() }
                } label: {
                    Label("立即备份全部数据", systemImage: "externaldrive.badge.plus")
                }
                .disabled(isWorking)
                if isWorking {
                    HStack {
                        ProgressView()
                        Text("处理中…")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("备份")
            } footer: {
                Text("备份包含车辆、加油、费用、行程、GPS 轨迹和照片，保存在「文件」→ 我的 iPhone → 行车记录 → 备份。\n⚠️ 这个文件夹会随 App 一起删除！请点备份文件旁的「存到…」，把它存到 iCloud 云盘或电脑上。")
            }

            if !backups.isEmpty {
                Section("已有备份") {
                    ForEach(backups, id: \.self) { url in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(url.deletingPathExtension().lastPathComponent)
                                .font(.subheadline)
                                .lineLimit(1)
                            HStack {
                                Text(BackupService.fileSize(url))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("存到…") {
                                    exportURL = url
                                }
                                .glassButtonStyle()
                                .controlSize(.small)
                                ShareLink(item: url) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .glassButtonStyle()
                                .controlSize(.small)
                                Button("恢复") {
                                    prepareRestore(url: url, securityScoped: false)
                                }
                                .glassButtonStyle()
                                .controlSize(.small)
                                .tint(.orange)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            try? FileManager.default.removeItem(at: backups[index])
                        }
                        reload()
                    }
                }
            }

            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("从「文件」选择备份恢复…", systemImage: "arrow.counterclockwise.circle")
                }
                .disabled(isWorking || recorder.isRecording)
            } header: {
                Text("恢复")
            } footer: {
                Text(recorder.isRecording
                     ? "正在记录行程，停止后才能恢复。"
                     : "恢复会用备份里的数据完整替换当前所有数据（车辆、加油、费用、行程、轨迹、照片）。")
            }
        }
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    prepareRestore(url: url, securityScoped: true)
                }
            case .failure(let error):
                message = "无法打开文件：\(error.localizedDescription)"
            }
        }
        .sheet(item: Binding(get: { exportURL.map(IdentifiableURL.init) },
                             set: { exportURL = $0?.url })) { item in
            DocumentExportPicker(url: item.url)
                .ignoresSafeArea()
        }
        .alert("确认恢复？",
               isPresented: Binding(get: { pendingRestoreURL != nil }, set: { if !$0 { pendingRestoreURL = nil } })) {
            Button("恢复（覆盖当前数据）", role: .destructive) {
                if let url = pendingRestoreURL {
                    Task { await restore(url: url) }
                }
            }
            Button("取消", role: .cancel) {
                pendingRestoreURL = nil
            }
        } message: {
            Text("备份内容：\(pendingRestoreSummary)\n\n当前 App 里的所有数据会被替换，无法撤销。建议先做一次备份。")
        }
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func reload() {
        backups = BackupService.existingBackups()
    }

    private func createBackup() async {
        isWorking = true
        await Task.yield()
        defer { isWorking = false }
        do {
            let result = try BackupService.createBackup(context: context)
            reload()
            exportURL = result.url
            message = nil
        } catch {
            message = "备份失败：\(error.localizedDescription)"
        }
    }

    private func prepareRestore(url: URL, securityScoped: Bool) {
        let accessing = securityScoped && url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            // 先复制到临时目录，避免恢复时文件不可访问
            let local = AppPaths.temporaryDirectory.appendingPathComponent("restore.\(BackupService.fileExtension)")
            try? FileManager.default.removeItem(at: local)
            try FileManager.default.copyItem(at: url, to: local)
            let summary = try BackupService.inspect(url: local)
            pendingRestoreSummary = "\(Fmt.dateTimeFull.string(from: summary.createdAt)) · \(summary.text)"
            pendingRestoreURL = local
        } catch {
            message = "无法读取备份：\(error.localizedDescription)"
        }
    }

    private func restore(url: URL) async {
        isWorking = true
        await Task.yield()
        defer { isWorking = false }
        do {
            let summary = try BackupService.restore(from: url, context: context)
            message = "恢复完成：\(summary.text)"
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
        }
        pendingRestoreURL = nil
        try? FileManager.default.removeItem(at: url)
    }
}

struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// 「存储到文件」：可以直接存到 iCloud 云盘
struct DocumentExportPicker: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
