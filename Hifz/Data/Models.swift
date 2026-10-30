import Foundation
import SwiftData

struct Surah: Identifiable, Hashable {
    let id: Int
    let nameAr: String
    let nameRu: String
    let revelation: String
    let ayahCount: Int

    var revelationRu: String { revelation == "medinan" ? "Мединская" : "Мекканская" }
}

struct AyahKey: Hashable {
    let surah: Int
    let ayah: Int
}

struct Ayah: Identifiable, Hashable {
    let surah: Int
    let number: Int
    let text: String
    let translation: String?

    var id: AyahKey { AyahKey(surah: surah, ayah: number) }
}

struct Segment: Identifiable, Hashable {
    enum Role: String { case prefix, stem, suffix }

    let index: Int
    let text: String
    let role: Role
    let pos: String
    let features: [String: String]

    var id: Int { index }
}

struct Word: Identifiable, Hashable {
    let surah: Int
    let ayah: Int
    let position: Int
    let text: String
    let translit: String?
    let glossRu: String?
    let glossEn: String?
    let lemma: String?
    let lemmaID: Int?
    let root: String?
    let rootID: Int?
    let segments: [Segment]

    var id: String { "\(surah):\(ayah):\(position)" }
    var ref: String { "\(surah):\(ayah)" }
    var stem: Segment? { segments.first { $0.role == .stem } }
}

/// Аят, отмеченный выученным. Хранится на устройстве.
@Model
final class LearnedAyah {
    var surah: Int
    var ayah: Int
    var learnedAt: Date

    init(surah: Int, ayah: Int, learnedAt: Date = .now) {
        self.surah = surah
        self.ayah = ayah
        self.learnedAt = learnedAt
    }
}
