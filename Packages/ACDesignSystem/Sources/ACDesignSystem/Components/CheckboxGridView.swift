import SwiftUI

/// A generic multi-select checkbox grid over any `Hashable` item set — no
/// knowledge of `ProductionType`/`AttachmentType`/`ExploitationType` or any
/// other domain type, per `CLAUDE.md`'s Design System rule. A Feature-layer
/// caller supplies the items, a display-label closure, and a `Set<Item>`
/// selection binding — the same "local adapter at the call site" pattern
/// already established for `CueTableView`'s row protocol and `WaveformView`'s
/// `WaveformDisplayData`.
///
/// Built at the third real call site (`ROADMAP.md` D7's `ProductionType`/
/// `AttachmentType`/`ExploitationType` checkbox groups on `SetupView`),
/// per `CONTRIBUTING.md` §3's rule of three — the first two are fine as
/// near-duplicates, the third is when to extract.
public struct CheckboxGridView<Item: Hashable>: View {
    private let items: [Item]
    private let label: (Item) -> String
    @Binding private var selection: Set<Item>
    private let surface: Theme.Surface

    public init(
        items: [Item],
        label: @escaping (Item) -> String,
        selection: Binding<Set<Item>>,
        surface: Theme.Surface = .primary
    ) {
        self.items = items
        self.label = label
        _selection = selection
        self.surface = surface
    }

    public var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180), spacing: Theme.Spacing.sm)],
            alignment: .leading,
            spacing: Theme.Spacing.xs
        ) {
            ForEach(items, id: \.self) { item in
                Toggle(isOn: isSelected(item)) {
                    Text(label(item))
                        .font(Theme.Typography.font(.regular, size: 13))
                        .foregroundStyle(surface.foreground)
                }
                .toggleStyle(SharpCheckboxToggleStyle(surface: surface))
            }
        }
    }

    private func isSelected(_ item: Item) -> Binding<Bool> {
        Binding(
            get: { selection.contains(item) },
            set: { isOn in
                if isOn {
                    selection.insert(item)
                } else {
                    selection.remove(item)
                }
            }
        )
    }
}

#Preview("CheckboxGridView") {
    struct PreviewHost: View {
        @State private var selection: Set<String> = ["Cinema"]
        var body: some View {
            CheckboxGridView(
                items: ["Cinema", "TV", "Festival", "Other"],
                label: { $0 },
                selection: $selection
            )
            .padding(Theme.Spacing.lg)
            .background(Theme.Surface.primary.background)
        }
    }
    return PreviewHost()
}
