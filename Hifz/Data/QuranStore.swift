import Foundation
import Observation
import SQLite3

/// Читает `quran.sqlite` (схема в docs/data-schema.md). Данных немного, поэтому всё грузится в память при запуске.
@MainActor
@Observable
final class QuranStore {
    private(set) var surahs: [Surah] = []
    private(set) var loadError: String?
    private var ayahsBySurah: [Int: [Ayah]] = [:]
    private var wordsByAyah: [AyahKey: [Word]] = [:]

    init() {
        guard let url = Bundle.main.url(forResource: "quran", withExtension: "sqlite") else {
            loadError = "Файл данных quran.sqlite не найден. Соберите его: python3 tools/build_data.py"
            return
        }
        do {
            try load(from: url)
        } catch {
            loadError = "Не удалось прочитать данные: \(error)"
        }
    }

    func ayahs(of surah: Int) -> [Ayah] { ayahsBySurah[surah] ?? [] }

    func words(of ayah: AyahKey) -> [Word] { wordsByAyah[ayah] ?? [] }

    /// Насколько слово знакомо по уже выученным аятам.
    func familiarity(of word: Word, learned: Set<AyahKey>) -> Familiarity {
        var best = Familiarity.new
        for key in learned {
            for other in words(of: key) where other.id != word.id {
                let f = Self.compare(word, other)
                if f.rank > best.rank { best = f }
                if best == .sameForm { return best }
            }
        }
        return best
    }

    /// Аяты из выученных, где встречается та же лемма.
    func occurrences(of word: Word) -> [Word] {
        guard let lemmaID = word.lemmaID else { return [] }
        return wordsByAyah.values.joined()
            .filter { $0.lemmaID == lemmaID && $0.id != word.id }
            .sorted { ($0.surah, $0.ayah, $0.position) < ($1.surah, $1.ayah, $1.position) }
    }

    private static func compare(_ a: Word, _ b: Word) -> Familiarity {
        if let sa = a.stem?.text, sa == b.stem?.text { return .sameForm }
        if let la = a.lemmaID, la == b.lemmaID { return .sameLemma }
        if let ra = a.rootID, ra == b.rootID { return .sameRoot }
        return .new
    }

    // MARK: SQLite

    private func load(from url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw StoreError.open
        }
        defer { sqlite3_close(db) }

        surahs = try query(db, "SELECT id, name_ar, name_ru, revelation, ayah_count FROM surahs ORDER BY id") { s in
            Surah(id: s.int(0), nameAr: s.text(1), nameRu: s.text(2), revelation: s.text(3), ayahCount: s.int(4))
        }

        let ayahs = try query(db, "SELECT surah, ayah, text, translation_ru FROM ayahs ORDER BY surah, ayah") { s in
            Ayah(surah: s.int(0), number: s.int(1), text: s.text(2), translation: s.optText(3))
        }
        ayahsBySurah = Dictionary(grouping: ayahs, by: \.surah)

        struct SegRow { let key: String; let segment: Segment }
        let segs = try query(db, """
            SELECT s.surah, s.ayah, s.position, s.seg, s.text, s.role, s.pos, s.features,
                   p.title, p.gloss, p.role_ru, p.note, p.draft
            FROM segments s
            LEFT JOIN particles p ON p.id = s.particle_id
            ORDER BY s.surah, s.ayah, s.position, s.seg
            """) { s in
            let particle = s.optText(8).map {
                Particle(title: $0, gloss: s.text(9), roleRu: s.text(10), note: s.optText(11), isDraft: s.int(12) != 0)
            }
            return SegRow(
                key: "\(s.int(0)):\(s.int(1)):\(s.int(2))",
                segment: Segment(index: s.int(3), text: s.text(4), role: Segment.Role(rawValue: s.text(5)) ?? .stem,
                                 pos: s.text(6), features: Self.parseFeatures(s.text(7)), particle: particle)
            )
        }
        let segsByWord = Dictionary(grouping: segs, by: \.key).mapValues { $0.map(\.segment) }

        let words = try query(db, """
            SELECT w.surah, w.ayah, w.position, w.text, w.translit, w.gloss_ru, w.gloss_en,
                   l.text, w.lemma_id, r.text, w.root_id
            FROM words w
            LEFT JOIN lemmas l ON l.id = w.lemma_id
            LEFT JOIN roots r ON r.id = w.root_id
            ORDER BY w.surah, w.ayah, w.position
            """) { s in
            let key = "\(s.int(0)):\(s.int(1)):\(s.int(2))"
            return Word(surah: s.int(0), ayah: s.int(1), position: s.int(2), text: s.text(3),
                        translit: s.optText(4), glossRu: s.optText(5), glossEn: s.optText(6),
                        lemma: s.optText(7), lemmaID: s.optInt(8), root: s.optText(9), rootID: s.optInt(10),
                        segments: segsByWord[key] ?? [])
        }
        wordsByAyah = Dictionary(grouping: words) { AyahKey(surah: $0.surah, ayah: $0.ayah) }
    }

    private static func parseFeatures(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj.mapValues { "\($0)" }
    }

    private func query<T>(_ db: OpaquePointer?, _ sql: String, _ row: (Row) -> T) throws -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.query(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        var result: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(row(Row(stmt: stmt)))
        }
        return result
    }

    private struct Row {
        let stmt: OpaquePointer?
        func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(stmt, i)) }
        func optInt(_ i: Int32) -> Int? { sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : int(i) }
        func text(_ i: Int32) -> String { optText(i) ?? "" }
        func optText(_ i: Int32) -> String? {
            guard let c = sqlite3_column_text(stmt, i) else { return nil }
            return String(cString: c)
        }
    }

    enum StoreError: Error {
        case open
        case query(String)
    }
}
