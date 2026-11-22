import SwiftUI
import SwiftData

/// 费用分类：增删、改名、换图标、排序
struct ExpenseCategoryManagerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ExpenseCategory.sortOrder) private var categories: [ExpenseCategory]
    @Query private var expenses: [Expense]
    @State private var editing: ExpenseCategory?
    @State private var showAdd = false
    @State private var pendingDelete: ExpenseCategory?

    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    Button {
                        editing = category
                    } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(iconName: category.iconName, color: CategoryPalette.color(for: category), size: 30)
                            Text(category.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            let count = expenses.filter { $0.categoryID == category.id }.count
                            if count > 0 {
                                Text("\(count) 条")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onMove(perform: move)
                .onDelete { offsets in
                    if let index = offsets.first {
                        pendingDelete = categories[index]
                    }
                }
            } footer: {
                Text("点分类可以改名和换图标；右上角「编辑」可以拖动排序。删除分类后，该分类下的费用会变成「未分类」。")
            }
        }
        .navigationTitle("费用分类")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { category in
            CategoryEditSheet(category: category)
        }
        .sheet(isPresented: $showAdd) {
            CategoryEditSheet(category: nil)
        }
        .confirmationDialog("删除分类「\(pendingDelete?.name ?? "")」？",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let category = pendingDelete {
                    for expense in expenses where expense.categoryID == category.id {
                        expense.categoryID = nil
                    }
                    context.delete(category)
                    try? context.save()
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("该分类下的费用不会被删除，会变成「未分类」。")
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = categories
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in ordered.enumerated() {
            category.sortOrder = index
        }
        try? context.save()
    }
}

struct CategoryEditSheet: View {
    let category: ExpenseCategory?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ExpenseCategory.sortOrder) private var categories: [ExpenseCategory]
    @State private var name: String
    @State private var iconName: String

    static let icons = [
        "wrench.and.screwdriver", "hammer", "circle.circle", "checkmark.shield", "doc.text", "checkmark.seal",
        "parkingsign.circle", "road.lanes", "drop", "exclamationmark.triangle", "gearshape.2", "banknote",
        "ellipsis.circle", "car", "bolt.car", "fuelpump", "battery.100", "key", "creditcard", "cart",
        "sparkles", "paintbrush", "speaker.wave.2", "lightbulb", "bandage", "tag", "star", "house"
    ]

    init(category: ExpenseCategory?) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _iconName = State(initialValue: category?.iconName ?? "tag")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("分类名称", text: $name)
                }
                Section("图标") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                        ForEach(Self.icons, id: \.self) { icon in
                            Button {
                                iconName = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(iconName == icon ? Color.accentColor.opacity(0.2) : Color(uiColor: .tertiarySystemFill))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(category == nil ? "新分类" : "编辑分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if let category {
                            category.name = trimmed
                            category.iconName = iconName
                        } else {
                            let order = (categories.map(\.sortOrder).max() ?? -1) + 1
                            context.insert(ExpenseCategory(name: trimmed, iconName: iconName, sortOrder: order))
                        }
                        try? context.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
