import SwiftUI

/// Карточка слова в режиме «Просмотр»: на половине экрана лицевая сторона, растянутая вверх — оборот.
struct WordCardView: View {
    let word: Word
    let familiarity: Familiarity
    @Binding var detent: PresentationDetent

    @Environment(QuranStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("block.inAyah.expanded") private var inAyahExpanded = true
    @AppStorage("block.where.expanded") private var whereExpanded = false

    private var showsBack: Bool { detent == .large }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if showsBack {
                    compactHeader
                    breakdown
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    front
                }
            }
            .padding(16)
        }
        .animation(.smooth(duration: 0.3), value: showsBack)
        .background(Color.cardBg)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Закрыть", systemImage: "xmark") { dismiss() }
            }
        }
    }

    // MARK: Лицевая сторона

    private var front: some View {
        VStack(spacing: 8) {
            HStack {
                FamiliarityChip(state: familiarity)
                Spacer()
                Text(word.ref).font(.footnote.monospacedDigit()).foregroundStyle(Color.inkSecondary)
            }
            Text(word.text)
                .font(.quran(56, relativeTo: .largeTitle))
                .foregroundStyle(Color.ink)
                .modifier(FamiliarityMark(state: familiarity, isFocus: true))
                .padding(.vertical, 4)
            if let t = word.translit {
                Text(t).font(.title3).italic().foregroundStyle(Color.inkSecondary)
            }
            gloss.font(.title2.weight(.semibold))
            Button("Разбор", systemImage: "chevron.up") { detent = .large }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(Color.ink)
                .padding(.top, 8)
        }
    }

    @ViewBuilder private var gloss: some View {
        if let ru = word.glossRu {
            Text(ru).foregroundStyle(Color.ink).multilineTextAlignment(.center)
        } else if let en = word.glossEn {
            VStack(spacing: 2) {
                Text(en).foregroundStyle(Color.ink).multilineTextAlignment(.center)
                Text("пока на английском").font(.caption).foregroundStyle(Color.inkSecondary)
            }
        }
    }

    // MARK: Оборот

    private var compactHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                gloss.font(.headline)
                if let t = word.translit {
                    Text(t).font(.subheadline).italic().foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer()
            coloredWord.font(.quran(34, relativeTo: .title))
        }
        .frame(minHeight: 64)
    }

    private var coloredWord: Text {
        word.segments.reduce(Text("")) { acc, s in
            acc + Text(s.text).foregroundColor(color(for: s.role))
        }
    }

    private func color(for role: Segment.Role) -> Color {
        switch role {
        case .prefix: .segPrefix
        case .stem: .ink
        case .suffix: .segSuffix
        }
    }

    private var breakdown: some View {
        VStack(spacing: 12) {
            CollapsibleBlock(title: "В этом аяте", summary: Grammar.summary(word), isExpanded: $inAyahExpanded) {
                inAyah
            }
            CollapsibleBlock(title: "Где ещё встречалось", summary: occurrencesSummary, isExpanded: $whereExpanded) {
                occurrences
            }
            Text("Морфология: Quranic Arabic Corpus (corpus.quran.com) · Текст и пословный перевод: quran.com")
                .font(.caption2)
                .foregroundStyle(Color.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inAyah: some View {
        VStack(alignment: .leading, spacing: 16) {
            if word.segments.count > 1 {
                HStack(spacing: 8) {
                    ForEach(Array(word.segments.enumerated()), id: \.element.id) { i, s in
                        if i > 0 { Text("+").font(.title3).foregroundStyle(.tertiary) }
                        SegmentTile(segment: s, color: color(for: s.role))
                    }
                }
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity)
            }

            ForEach(word.segments) { s in
                VStack(alignment: .leading, spacing: 6) {
                    if word.segments.count > 1 {
                        Text(s.text).font(.quran(24, relativeTo: .title2)).foregroundStyle(color(for: s.role))
                    }
                    if let p = s.particle {
                        ParticleNote(particle: p)
                    }
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                        ForEach(Grammar.rows(for: s), id: \.0) { label, value in
                            GridRow {
                                Text(label).font(.subheadline).foregroundStyle(Color.inkSecondary)
                                Text(value).font(.body)
                            }
                        }
                        if s.role == .stem, let root = word.root {
                            GridRow {
                                Text("Корень").font(.subheadline).foregroundStyle(Color.inkSecondary)
                                Text(root).font(.quran(22, relativeTo: .title3))
                            }
                        }
                        if s.role == .stem, let lemma = word.lemma {
                            GridRow {
                                Text("Лемма").font(.subheadline).foregroundStyle(Color.inkSecondary)
                                Text(lemma).font(.quran(22, relativeTo: .title3))
                            }
                        }
                    }
                }
            }
        }
    }

    private var occurrenceList: [Word] { store.occurrences(of: word) }

    private var occurrencesSummary: String? {
        let list = occurrenceList
        return list.isEmpty ? nil : list.prefix(3).map(\.ref).joined(separator: ", ")
    }

    @ViewBuilder private var occurrences: some View {
        let list = occurrenceList
        if list.isEmpty {
            Text("В доступных сурах это слово встречается только здесь")
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
        } else {
            VStack(spacing: 0) {
                ForEach(list) { w in
                    HStack {
                        Text(w.ref).font(.subheadline.monospacedDigit()).foregroundStyle(Color.inkSecondary)
                        Spacer()
                        Text(w.text).font(.quran(22, relativeTo: .title3))
                    }
                    .frame(minHeight: 44)
                    if w.id != list.last?.id { Divider() }
                }
            }
        }
    }
}

/// Значение частицы из словаря: «би — предлог: с, посредством» и пояснение, с тегом «Черновик».
private struct ParticleNote: View {
    let particle: Particle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(particle.title) — \(particle.roleRu)").font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if particle.isDraft {
                    Label("Черновик", systemImage: "pencil.line")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.cardBg, in: Capsule())
                }
            }
            Text(particle.gloss).font(.body)
            if let note = particle.note {
                Text(note).font(.callout).foregroundStyle(Color.inkSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.focusNeutral, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SegmentTile: View {
    let segment: Segment
    let color: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 4) {
            Text(segment.text).font(.quran(34, relativeTo: .title)).foregroundStyle(color)
            // На плитке только начало: роль без арабского термина и первое значение. Полностью — в пояснении ниже.
            Text(segment.particle.map { Self.head($0.roleRu, upTo: " (") } ?? Grammar.posName(segment.pos))
                .font(.caption)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
            if let p = segment.particle {
                Text("\(p.title): \(Self.head(p.gloss, upTo: ";"))")
                    .font(.footnote)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 150)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(color.opacity(scheme == .dark ? 0.18 : 0.10),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12).fill(color).frame(height: 3)
        }
        .accessibilityElement(children: .combine)
    }

    private static func head(_ s: String, upTo separator: String) -> String {
        s.components(separatedBy: separator).first ?? s
    }
}
