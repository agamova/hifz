import Foundation

/// Перевод грамматических пометок Quranic Arabic Corpus на русский.
enum Grammar {
    static func posName(_ pos: String) -> String {
        posNames[pos] ?? pos
    }

    /// Строки «подпись — значение» для сегмента.
    static func rows(for s: Segment) -> [(String, String)] {
        var rows: [(String, String)] = [("Часть речи", posName(s.pos))]
        for (key, label) in featureOrder {
            guard let raw = value(s.features, key) else { continue }
            rows.append((label, valueNames[key]?[raw.uppercased()] ?? valueNames[key]?[raw] ?? raw))
        }
        return rows
    }

    /// Короткая сводка для свёрнутого блока: «предлог + имя, родительный».
    static func summary(_ w: Word) -> String {
        let parts = w.segments.map { posName($0.pos) }.joined(separator: " + ")
        guard let stem = w.stem, let c = value(stem.features, "case"),
              let name = valueNames["case"]?[c.uppercased()] else { return parts }
        return "\(parts), \(name.components(separatedBy: " ").first ?? name)"
    }

    private static func value(_ f: [String: String], _ key: String) -> String? {
        (f[key] ?? f[key.capitalized] ?? f[key.uppercased()]).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static let featureOrder: [(String, String)] = [
        ("form", "Порода"),
        ("aspect", "Время"),
        ("voice", "Залог"),
        ("mood", "Наклонение"),
        ("person", "Лицо"),
        ("gender", "Род"),
        ("number", "Число"),
        ("case", "Падеж"),
        ("state", "Определённость"),
    ]

    private static let valueNames: [String: [String: String]] = [
        "case": ["NOM": "именительный (марфӯʿ, مرفوع)", "ACC": "винительный (мансӯб, منصوب)",
                 "GEN": "родительный (мадж̣рӯр, مجرور)"],
        "gender": ["M": "мужской", "F": "женский"],
        "number": ["S": "единственное", "D": "двойственное", "P": "множественное"],
        "person": ["1": "1-е", "2": "2-е", "3": "3-е"],
        "aspect": ["PERF": "прошедшее (мāд̣ӣ)", "IMPF": "настоящее-будущее (муд̣āриʿ)", "IMPV": "повелительное (амр)"],
        "mood": ["IND": "изъявительное (марфӯʿ)", "SUBJ": "сослагательное (мансӯб)", "JUS": "усечённое (маджзӯм)"],
        "voice": ["ACT": "действительный", "PASS": "страдательный"],
        "state": ["DEF": "определённое", "INDEF": "неопределённое"],
    ]

    private static let posNames: [String: String] = [
        "N": "имя", "PN": "имя собственное", "ADJ": "прилагательное", "V": "глагол",
        "P": "предлог", "PRON": "местоимение", "DEM": "указательное местоимение",
        "REL": "относительное местоимение", "CONJ": "союз", "NEG": "отрицание", "DET": "артикль",
        "INTG": "вопросительная частица", "EMPH": "частица усиления", "SUB": "подчинительная частица",
        "ACC": "частица насба", "T": "наречие времени", "LOC": "наречие места", "VOC": "звательная частица",
        "CERT": "частица утверждения", "REM": "частица возобновления", "RES": "частица ограничения",
        "INL": "отдельные буквы", "COND": "условная частица", "FUT": "частица будущего",
        "PRO": "частица запрета", "EXP": "частица исключения", "AMD": "частица исправления",
        "ANS": "частица ответа", "AVR": "частица отвращения", "CAUS": "частица причины",
        "CIRC": "частица состояния", "COM": "частица сопровождения", "EQ": "частица уравнивания",
        "EXH": "частица побуждения", "EXL": "частица разъяснения", "IMPN": "глагольное имя",
        "IMPV": "частица повеления", "INC": "начинательная частица", "INT": "частица толкования",
        "PREV": "частица предотвращения", "PRP": "частица цели", "RET": "частица отступления",
        "RSLT": "частица следствия", "SUP": "дополнительная частица", "SUR": "частица удивления",
        "LOC/T": "наречие",
    ]
}
