import SwiftUI

/// Фон и черта знакомости под арабским словом. Черта отдельным overlay, чтобы не резать огласовки снизу.
struct FamiliarityMark: ViewModifier {
    let state: Familiarity
    var isFocus = false
    var isSelected = false
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(state.background ?? (isFocus ? Color.focusNeutral : .clear),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .bottom) {
                if state != .new {
                    Line()
                        .stroke(state.line, style: StrokeStyle(lineWidth: contrast == .increased ? 3.5 : 2.5,
                                                               lineCap: .round, dash: state.dash))
                        .frame(height: 3)
                        .padding(.horizontal, 6)
                        .offset(y: 3)
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.ink, lineWidth: 2)
                }
            }
    }
}

struct Line: Shape {
    func path(in r: CGRect) -> Path {
        Path {
            $0.move(to: CGPoint(x: r.minX, y: r.midY))
            $0.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        }
    }
}

struct FamiliarityChip: View {
    let state: Familiarity

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state.symbol)
                .foregroundStyle(state == .new ? Color.inkDim : state.line)
            Text(state.title)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(state.background ?? Color.focusNeutral, in: Capsule())
    }
}

/// Раскладывает элементы строками с переносом. В окружении `.rightToLeft` SwiftUI сам зеркалит x.
struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        rows(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in rows(b.width, subviews).points.enumerated() {
            subviews[i].place(at: CGPoint(x: b.minX + p.x, y: b.minY + p.y), proposal: .unspecified)
        }
    }

    private func rows(_ maxW: CGFloat, _ s: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var pts: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, w: CGFloat = 0
        for v in s {
            let sz = v.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 {
                x = 0
                y += rowH + lineSpacing
                rowH = 0
            }
            pts.append(CGPoint(x: x, y: y))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            w = max(w, x - spacing)
        }
        return (CGSize(width: w, height: y + rowH), pts)
    }
}

/// Плашка-блок оборота карточки, сворачивается по нажатию на заголовок.
struct CollapsibleBlock<Content: View>: View {
    let title: String
    var summary: String?
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.smooth(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(title).font(.headline)
                    Spacer(minLength: 8)
                    if !isExpanded, let summary {
                        Text(summary).font(.subheadline).foregroundStyle(Color.inkSecondary).lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(Color.inkSecondary)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isExpanded ? "раскрыто" : "свёрнуто")

            if isExpanded { content.transition(.opacity) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.cardStroke, lineWidth: 0.5))
    }
}
