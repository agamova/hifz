import SwiftData
import SwiftUI

struct SurahListView: View {
    @Environment(QuranStore.self) private var store
    @Query private var learned: [LearnedAyah]

    var body: some View {
        NavigationStack {
            Group {
                if let error = store.loadError {
                    ContentUnavailableView("Нет данных", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    list
                }
            }
            .navigationTitle("Суры")
            .navigationDestination(for: Surah.self) { AyahListView(surah: $0) }
        }
    }

    private var list: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.title2)
                        .foregroundStyle(Color.ink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Повторение").font(.headline)
                        Text("Появится в версии 0.2: добавляйте слова из карточек")
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
                .frame(minHeight: 64)
            }

            Section("Суры") {
                ForEach(store.surahs) { surah in
                    NavigationLink(value: surah) {
                        SurahRow(surah: surah, learnedCount: learned.filter { $0.surah == surah.id }.count)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.pageBg)
    }
}

private struct SurahRow: View {
    let surah: Surah
    let learnedCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(surah.id)")
                .font(.footnote.monospacedDigit())
                .frame(width: 32, height: 32)
                .background(Color.focusNeutral, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(surah.nameRu).font(.body.weight(.semibold))
                Text("\(surah.revelationRu) · \(surah.ayahCount) \(ayahWord(surah.ayahCount))")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                if learnedCount == surah.ayahCount {
                    Label("Выучена", systemImage: "checkmark.seal").font(.caption)
                } else {
                    ProgressView(value: Double(learnedCount), total: Double(surah.ayahCount))
                        .tint(Color.ink)
                    Text("Аятов \(learnedCount) из \(surah.ayahCount)")
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
            }

            Spacer(minLength: 8)

            Text(surah.nameAr)
                .font(.quran(24, relativeTo: .title2))
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// «аят», «аята», «аятов» по правилам русского языка.
func ayahWord(_ n: Int) -> String {
    let m10 = n % 10, m100 = n % 100
    if m10 == 1 && m100 != 11 { return "аят" }
    if (2...4).contains(m10) && !(12...14).contains(m100) { return "аята" }
    return "аятов"
}
