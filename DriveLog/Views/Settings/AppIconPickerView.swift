import SwiftUI
import UIKit

/// 更换 App 图标
struct AppIconPickerView: View {
    struct Option: Identifiable {
        let id: String
        let title: String
        /// nil 表示默认图标
        let iconName: String?
        let preview: String
    }

    static let options: [Option] = [
        Option(id: "default", title: "仪表盘 · 公路", iconName: nil, preview: "IconPreviewDefault"),
        Option(id: "odometer", title: "仪表盘 · 里程表", iconName: "AppIcon-Odometer", preview: "IconPreviewOdometer")
    ]

    @State private var currentIconName: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Group {
                Section {
                    ForEach(Self.options) { option in
                        Button {
                            select(option)
                        } label: {
                            HStack(spacing: 14) {
                                Image(option.preview)
                                    .resizable()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 13.5, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 13.5, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                                    )
                                Text(option.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if currentIconName == option.iconName {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listRowBackground(Theme.rowFill)
        }
        .appBackground()
        .navigationTitle("更换图标")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            currentIconName = UIApplication.shared.alternateIconName
        }
        .alert("无法更换图标",
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func select(_ option: Option) {
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = "当前系统不支持更换图标。"
            return
        }
        guard currentIconName != option.iconName else { return }
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(option.iconName)
                currentIconName = option.iconName
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
