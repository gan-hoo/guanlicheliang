import SwiftUI

/// 页面标题：标题和按钮放在同一行（顶部那一行），内容紧接在下面
struct PageHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 48)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }
}

/// 标题行右侧的图标按钮
struct HeaderIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.tint)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// 一组标题行按钮，放在同一块玻璃上（和系统工具栏一样）
struct HeaderButtonGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, 2)
        .glassCapsule(interactive: true)
    }
}

struct PageHeaderModifier<Trailing: View>: ViewModifier {
    let title: String
    let trailing: () -> Trailing

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaBar(edge: .top) {
                    PageHeader(title: title, trailing: trailing)
                }
        } else {
            content
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    PageHeader(title: title, trailing: trailing)
                        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .top)
                }
        }
    }
}

extension View {
    /// 用自定义标题行代替系统导航栏的大标题
    func pageHeader<Trailing: View>(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) -> some View {
        modifier(PageHeaderModifier(title: title, trailing: trailing))
    }

    func pageHeader(_ title: String) -> some View {
        modifier(PageHeaderModifier(title: title, trailing: { EmptyView() }))
    }
}
