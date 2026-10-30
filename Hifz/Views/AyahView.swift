import SwiftData
import SwiftUI

struct AyahView: View {
    let surah: Surah
    @State var number: Int

    @Environment(QuranStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query private var learned: [LearnedAyah]

    @State private var selectedWord: Word?
    @State private var detent: PresentationDetent = .medium

    init(surah: Surah, number: Int) {
        self.surah = surah
        _number = State(initialValue: number)
    }

    private var key: AyahKey { AyahKey(surah: surah.id, ayah: number) }
    private var ayah: Ayah? { store.ayahs(of: surah.id).first { $0.number == number } }
    private var learnedKeys: Set<AyahKey> { Set(learned.map { AyahKey(surah: $0.surah, ayah: $0.ayah) }) }
    private var learnedRecord: LearnedAyah? { learned.first { $0.surah == surah.id && $0.ayah == number } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                wordsCard
                if let t = ayah?.translation {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Перевод").font(.headline)
                        Text(t).font(.body).lineSpacing(4)
                        Text("Перевод смыслов: Э. Кулиев").font(.caption2).foregroundStyle(Color.inkSecondary)
                    }
                }
                learnedButton
            }
            .padding(16)
        }
        .background(Color.pageBg)
        .navigationTitle("\(surah.nameRu), \(number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Пред.", systemImage: "chevron.backward") { go(-1) }
                    .disabled(number <= 1)
                Spacer()
                Button("След.", systemImage: "chevron.forward") { go(1) }
                    .disabled(number >= surah.ayahCount)
            }
        }
        .sheet(item: $selectedWord) { word in
            NavigationStack {
                WordCardView(word: word,
                             familiarity: store.familiarity(of: word, learned: learnedKeys),
                             detent: $detent)
            }
            .presentationDetents([.medium, .large], selection: $detent)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationCornerRadius(20)
        }
    }

    private var wordsCard: some View {
        FlowLayout(spacing: 10, lineSpacing: 14) {
            ForEach(store.words(of: key)) { word in
                Button {
                    detent = .medium
                    selectedWord = word
                } label: {
                    Text(word.text)
                        .font(.quran(34, relativeTo: .title))
                        .foregroundStyle(Color.ink)
                        .modifier(FamiliarityMark(state: store.familiarity(of: word, learned: learnedKeys),
                                                  isSelected: selectedWord?.id == word.id))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(word.translit ?? word.text)
                .accessibilityHint("Открывает карточку слова")
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(20)
        .background(Color.cardBg, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.cardStroke, lineWidth: 0.5))
    }

    @ViewBuilder private var learnedButton: some View {
        if let record = learnedRecord {
            Menu {
                Button("Снять отметку", role: .destructive) { context.delete(record) }
            } label: {
                Label("Выучен", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.ink)
        } else {
            Button {
                context.insert(LearnedAyah(surah: surah.id, ayah: number))
            } label: {
                Label("Отметить выученным", systemImage: "checkmark.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(Color.ink)
        }
    }

    private func go(_ delta: Int) {
        selectedWord = nil
        number = min(max(1, number + delta), surah.ayahCount)
    }
}
