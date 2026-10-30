import SwiftData
import SwiftUI

struct AyahListView: View {
    let surah: Surah
    @Environment(QuranStore.self) private var store
    @Query private var learned: [LearnedAyah]

    private var learnedNumbers: Set<Int> {
        Set(learned.filter { $0.surah == surah.id }.map(\.ayah))
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text(surah.nameAr).font(.quran(34, relativeTo: .largeTitle))
                    Text("\(surah.revelationRu) · \(surah.ayahCount) \(ayahWord(surah.ayahCount))")
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSecondary)
                    Text("Выучено \(learnedNumbers.count) из \(surah.ayahCount)")
                        .font(.footnote)
                        .foregroundStyle(Color.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(store.ayahs(of: surah.id)) { ayah in
                    NavigationLink(value: ayah) {
                        AyahRow(ayah: ayah, isLearned: learnedNumbers.contains(ayah.number))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.pageBg)
        .navigationTitle(surah.nameRu)
        .navigationDestination(for: Ayah.self) { AyahView(surah: surah, number: $0.number) }
    }
}

private struct AyahRow: View {
    let ayah: Ayah
    let isLearned: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(ayah.number)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Color.inkSecondary)
                Spacer()
                if isLearned {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.ink)
                }
            }
            Text(ayah.text)
                .font(.quran(24, relativeTo: .title2))
                .lineSpacing(8)
                .lineLimit(3)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)
            if let t = ayah.translation {
                Text(t)
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Аят \(ayah.number)\(isLearned ? ", выучен" : ""). \(ayah.translation ?? "")")
    }
}
