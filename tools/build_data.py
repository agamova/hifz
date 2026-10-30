#!/usr/bin/env python3
"""Сборка data/build/quran.sqlite для приложения hifz (схема docs/data-schema.md).

Запуск (из любой папки):
    python3 tools/build_data.py                    # суры 1,112,113,114
    python3 tools/build_data.py --surahs 1,112     # другой список сур
    python3 tools/build_data.py --qac /путь/к/quranic-corpus-morphology-0.4.txt

Что делает:
  1. Берёт сырые файлы из data/raw/. Если файла quran.com нет, скачивает и
     кэширует его. Файл Quranic Arabic Corpus скачать автоматически нельзя
     (на сайте нужно ввести email), поэтому его один раз копируют из --qac.
  2. Собирает таблицы meta, sources, surahs, ayahs, roots, lemmas, words, segments.
  3. Сверяет источники и пишет расхождения в data/build/report.txt.
     Ничего не исправляет молча: текст Корана и морфология берутся как есть.

Повторный запуск с теми же сырыми файлами даёт побайтно тот же quran.sqlite:
дата сборки (built_at) берётся из SOURCE_DATE_EPOCH, а если её нет -
самая поздняя дата получения сырых файлов из data/raw/manifest.json.

Только стандартная библиотека Python 3.8+.
"""

import argparse
import datetime
import hashlib
import html
import json
import os
import re
import shutil
import sqlite3
import sys
import time
import unicodedata
import urllib.request

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = os.path.join(ROOT_DIR, "data", "raw")
BUILD_DIR = os.path.join(ROOT_DIR, "data", "build")
DB_PATH = os.path.join(BUILD_DIR, "quran.sqlite")
REPORT_PATH = os.path.join(BUILD_DIR, "report.txt")
MANIFEST_PATH = os.path.join(RAW_DIR, "manifest.json")
PARTICLES_PATH = os.path.join(ROOT_DIR, "data", "particles.json")

QAC_REL = "qac/quranic-corpus-morphology-0.4.txt"
API = "https://api.quran.com/api/v4"
KULIEV_ID = 45
USER_AGENT = "hifz-data-build/0.1 (personal project)"

SCHEMA_VERSION = "2"
DATA_VERSION = "0.1"
DEFAULT_SURAHS = [1, 112, 113, 114]

# Русские названия сур задаём сами (в quran.com их нет).
NAME_RU = {
    1: "Аль-Фатиха",
    112: "Аль-Ихлас",
    113: "Аль-Фаляк",
    114: "Ан-Нас",
}

REVELATION = {"makkah": "meccan", "madinah": "medinan"}

# Части речи QAC, у которых обязана быть лемма (имена и глаголы).
NOMINAL_VERBAL_POS = {"N", "PN", "ADJ", "V"}

SCHEMA_SQL = """
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);

CREATE TABLE sources (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  url TEXT NOT NULL,
  license TEXT NOT NULL,
  attribution TEXT NOT NULL,
  retrieved_at TEXT NOT NULL,
  sha256 TEXT
);

CREATE TABLE surahs (
  id INTEGER PRIMARY KEY,
  name_ar TEXT NOT NULL,
  name_ru TEXT NOT NULL,
  revelation TEXT NOT NULL,
  ayah_count INTEGER NOT NULL
);

CREATE TABLE ayahs (
  surah INTEGER NOT NULL,
  ayah INTEGER NOT NULL,
  text TEXT NOT NULL,
  translation_ru TEXT,
  translation_source TEXT,
  PRIMARY KEY (surah, ayah)
);

CREATE TABLE roots (
  id INTEGER PRIMARY KEY,
  text TEXT NOT NULL UNIQUE
);

CREATE TABLE lemmas (
  id INTEGER PRIMARY KEY,
  text TEXT NOT NULL,
  root_id INTEGER REFERENCES roots(id),
  pos TEXT NOT NULL,
  UNIQUE (text, pos)
);

CREATE TABLE words (
  surah INTEGER NOT NULL,
  ayah INTEGER NOT NULL,
  position INTEGER NOT NULL,
  text TEXT NOT NULL,
  translit TEXT,
  gloss_ru TEXT,
  gloss_en TEXT,
  lemma_id INTEGER REFERENCES lemmas(id),
  root_id INTEGER REFERENCES roots(id),
  audio TEXT,
  PRIMARY KEY (surah, ayah, position)
);

CREATE TABLE segments (
  surah INTEGER NOT NULL,
  ayah INTEGER NOT NULL,
  position INTEGER NOT NULL,
  seg INTEGER NOT NULL,
  text TEXT NOT NULL,
  role TEXT NOT NULL,
  pos TEXT NOT NULL,
  features TEXT NOT NULL,
  lemma_id INTEGER REFERENCES lemmas(id),
  particle_id INTEGER REFERENCES particles(id),
  PRIMARY KEY (surah, ayah, position, seg)
);

CREATE TABLE particles (
  id INTEGER PRIMARY KEY,     -- порядок записи в data/particles.json
  title TEXT NOT NULL,        -- короткая форма для плитки: «би»
  gloss TEXT NOT NULL,        -- основное значение
  role_ru TEXT NOT NULL,      -- грамматическая роль по-русски
  note TEXT,
  draft INTEGER NOT NULL      -- 1, пока не проверено человеком
);

CREATE INDEX words_lemma ON words(lemma_id);
CREATE INDEX words_root ON words(root_id);
"""

# ---------------------------------------------------------------------------
# Транслитерация Бакуолтера (расширенная таблица QAC,
# https://corpus.quran.com/java/buckwalter.jsp) -> арабские буквы.
# ---------------------------------------------------------------------------
BUCKWALTER = {
    "'": "ء",  # ء hamza
    ">": "أ",  # أ
    "&": "ؤ",  # ؤ
    "<": "إ",  # إ
    "}": "ئ",  # ئ
    "A": "ا",  # ا
    "b": "ب",  # ب
    "p": "ة",  # ة
    "t": "ت",  # ت
    "v": "ث",  # ث
    "j": "ج",  # ج
    "H": "ح",  # ح
    "x": "خ",  # خ
    "d": "د",  # د
    "*": "ذ",  # ذ
    "r": "ر",  # ر
    "z": "ز",  # ز
    "s": "س",  # س
    "$": "ش",  # ش
    "S": "ص",  # ص
    "D": "ض",  # ض
    "T": "ط",  # ط
    "Z": "ظ",  # ظ
    "E": "ع",  # ع
    "g": "غ",  # غ
    "_": "ـ",  # tatweel
    "f": "ف",  # ف
    "q": "ق",  # ق
    "k": "ك",  # ك
    "l": "ل",  # ل
    "m": "م",  # م
    "n": "ن",  # ن
    "h": "ه",  # ه
    "w": "و",  # و
    "Y": "ى",  # ى
    "y": "ي",  # ي
    "F": "ً",  # fathatan
    "N": "ٌ",  # dammatan
    "K": "ٍ",  # kasratan
    "a": "َ",  # fatha
    "u": "ُ",  # damma
    "i": "ِ",  # kasra
    "~": "ّ",  # shadda
    "o": "ْ",  # sukun
    "^": "ٓ",  # maddah above
    "#": "ٔ",  # hamza above
    "`": "ٰ",  # dagger alif
    "{": "ٱ",  # ٱ alif wasla
    ":": "ۜ",  # small high seen
    "@": "۟",  # small high rounded zero
    '"': "۠",  # small high upright rectangular zero
    "[": "ۢ",  # small high meem isolated form
    ";": "ۣ",  # small low seen
    ",": "ۥ",  # small waw
    ".": "ۦ",  # small yeh
    "!": "ۨ",  # small high noon
    "-": "۪",  # empty centre low stop
    "+": "۫",  # empty centre high stop
    "%": "۬",  # rounded high stop with filled centre
    "]": "ۭ",  # small low meem
}


class UnknownChar(Exception):
    pass


def bw_to_ar(s):
    out = []
    for ch in s:
        if ch not in BUCKWALTER:
            raise UnknownChar("неизвестный символ Бакуолтера %r в %r" % (ch, s))
        out.append(BUCKWALTER[ch])
    return "".join(out)


# ---------------------------------------------------------------------------
# Нормализация только для СРАВНЕНИЯ (в базу не пишется).
# ---------------------------------------------------------------------------
def skeleton(s):
    """Скелет слова: без огласовок и малых коранических знаков, ٱ -> ا."""
    out = []
    for ch in unicodedata.normalize("NFC", s):
        cp = ord(ch)
        if 0x064B <= cp <= 0x065F:  # харакаты, шадда, сукун, мадда, хамза сверху/снизу
            continue
        if cp == 0x0670:  # кинжальный алиф
            continue
        if 0x06D6 <= cp <= 0x06ED:  # малые знаки и знаки остановки
            continue
        if cp == 0x0640:  # татвиль
            continue
        if ch.isspace():
            continue
        if ch == "ٱ":
            ch = "ا"
        out.append(ch)
    return "".join(out)


# ---------------------------------------------------------------------------
# Сырые файлы и манифест
# ---------------------------------------------------------------------------
def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_manifest():
    if os.path.exists(MANIFEST_PATH):
        with open(MANIFEST_PATH, encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_manifest(manifest):
    os.makedirs(RAW_DIR, exist_ok=True)
    tmp = MANIFEST_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, MANIFEST_PATH)


def today_utc():
    return datetime.datetime.utcnow().strftime("%Y-%m-%d")


def fetch_cached(rel, url, manifest):
    """Вернуть путь к сырому файлу; скачать, если его ещё нет."""
    path = os.path.join(RAW_DIR, rel)
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        print("  скачиваю %s" % url)
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT,
                                                   "Accept": "application/json"})
        last_err = None
        for attempt in range(3):
            try:
                with urllib.request.urlopen(req, timeout=60) as resp:
                    data = resp.read()
                break
            except Exception as e:  # сеть: пробуем ещё раз
                last_err = e
                time.sleep(2 * (attempt + 1))
        else:
            raise SystemExit("Не удалось скачать %s: %s" % (url, last_err))
        json.loads(data.decode("utf-8"))  # убеждаемся, что пришёл JSON
        tmp = path + ".tmp"
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, path)
        manifest[rel] = {"url": url, "retrieved_at": today_utc()}
        save_manifest(manifest)
    elif rel not in manifest:
        manifest[rel] = {"url": url, "retrieved_at": file_date(path)}
        save_manifest(manifest)
    return path


def file_date(path):
    return datetime.datetime.utcfromtimestamp(os.path.getmtime(path)).strftime("%Y-%m-%d")


def ensure_qac(qac_src, manifest):
    path = os.path.join(RAW_DIR, QAC_REL)
    if not os.path.exists(path):
        if not qac_src:
            raise SystemExit(
                "Нет файла морфологии %s.\n"
                "Скачайте Quranic Arabic Corpus v0.4 с https://corpus.quran.com/download/ "
                "(нужен email) и запустите скрипт с --qac /путь/к/файлу.txt" % path)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        shutil.copy2(qac_src, path)  # копия без изменений, с датой файла
    if QAC_REL not in manifest:
        manifest[QAC_REL] = {"url": "https://corpus.quran.com/download/",
                             "retrieved_at": file_date(path)}
        save_manifest(manifest)
    return path


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# quran.com
# ---------------------------------------------------------------------------
def load_chapters(manifest):
    path = fetch_cached("qurancom/chapters.json", API + "/chapters", manifest)
    data = load_json(path)
    return {c["id"]: c for c in data["chapters"]}, [path]


def load_verses(surah, manifest):
    verses, paths = [], []
    page = 1
    while True:
        url = ("%s/verses/by_chapter/%d?words=true&word_fields=text_uthmani"
               "&per_page=50&fields=text_uthmani&translations=%d&page=%d"
               % (API, surah, KULIEV_ID, page))
        rel = "qurancom/verses_%03d_p%02d.json" % (surah, page)
        path = fetch_cached(rel, url, manifest)
        paths.append(path)
        data = load_json(path)
        verses.extend(data["verses"])
        nxt = data.get("pagination", {}).get("next_page")
        if not nxt:
            break
        page = nxt
    return verses, paths


SUP_RE = re.compile(r"<sup\b[^>]*>.*?</sup>", re.S | re.I)
TAG_RE = re.compile(r"<[^>]+>")


def clean_translation(s):
    if s is None:
        return None
    s = SUP_RE.sub("", s)
    s = TAG_RE.sub("", s)
    s = html.unescape(s)
    s = re.sub(r"[ \t ]+", " ", s).strip()
    return s


# ---------------------------------------------------------------------------
# Quranic Arabic Corpus
# ---------------------------------------------------------------------------
LOC_RE = re.compile(r"^\((\d+):(\d+):(\d+):(\d+)\)$")
PGN_RE = re.compile(r"^([123])?([MF])?([SDP])?$")
FORM_RE = re.compile(r"^\(([IVX]+)\)$")


def parse_features(role, tokens, unknown):
    """Разобрать столбец FEATURES QAC в словарь с понятными ключами.
    Исходная строка сохраняется целиком в ключе "qac"."""
    feat = {}
    lemma = root = None
    for t in tokens:
        if t in ("PREFIX", "STEM", "SUFFIX"):
            continue
        if t.startswith("POS:"):
            continue  # часть речи хранится в segments.pos
        if t.startswith("LEM:"):
            lemma = t[4:]
            continue
        if t.startswith("ROOT:"):
            root = t[5:]
            continue
        if t.startswith("SP:"):
            feat["special"] = bw_to_ar(t[3:])  # группа كان / إنّ / كاد
            continue
        if t.startswith("MOOD:"):
            feat["mood"] = t[5:]
            continue
        if t in ("PERF", "IMPF", "IMPV"):
            feat["aspect"] = t
            continue
        if t in ("ACT", "PASS"):
            feat["voice"] = t
            continue
        if t in ("PCPL", "VN"):
            feat["derivation"] = t  # причастие / масдар
            continue
        if t in ("NOM", "ACC", "GEN"):
            feat["case"] = t
            continue
        if t == "INDEF":
            feat["state"] = t
            continue
        m = FORM_RE.match(t)
        if m:
            feat["form"] = m.group(1)
            continue
        if role == "prefix" and t.endswith("+"):
            feat["prefix"] = t
            continue
        if role == "suffix" and t.startswith("PRON:"):
            feat["suffix"] = "PRON"
            t = t[5:]
        elif role == "suffix" and t.startswith("+"):
            feat["suffix"] = t
            continue
        m = PGN_RE.match(t)
        if t and m:
            if m.group(1):
                feat["person"] = m.group(1)
            if m.group(2):
                feat["gender"] = m.group(2)
            if m.group(3):
                feat["number"] = m.group(3)
            continue
        feat.setdefault("other", []).append(t)
        unknown.add(t)
    return feat, lemma, root


def load_qac(path, surahs):
    """{(s,a,w): [segment dict, ...]} только для нужных сур."""
    wanted = set(surahs)
    words = {}
    unknown = set()
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\r\n")
            if not line.startswith("("):
                continue
            loc, form, tag, features = line.split("\t")
            m = LOC_RE.match(loc)
            if not m:
                raise SystemExit("Не разобран адрес QAC: %r" % loc)
            s, a, w, k = (int(x) for x in m.groups())
            if s not in wanted:
                continue
            tokens = features.split("|")
            role = {"PREFIX": "prefix", "STEM": "stem", "SUFFIX": "suffix"}.get(tokens[0])
            if role is None:
                raise SystemExit("Неизвестная роль сегмента в %s: %r" % (loc, tokens[0]))
            feat, lemma, root = parse_features(role, tokens, unknown)
            feat["qac"] = features
            words.setdefault((s, a, w), []).append({
                "seg": k, "form_bw": form, "text": bw_to_ar(form), "role": role,
                "pos": tag, "features": feat, "lemma_bw": lemma, "root_bw": root,
                "loc": loc,
            })
    for segs in words.values():
        segs.sort(key=lambda x: x["seg"])
    return words, unknown


def root_text(root_bw):
    return " ".join(bw_to_ar(ch) for ch in root_bw)


def lemma_text(lemma_bw):
    # В QAC омографы различаются цифрой (EaAd2). В арабском тексте цифры нет,
    # совпадения таких лемм выводятся в отчёт.
    return bw_to_ar(re.sub(r"\d+$", "", lemma_bw))


# ---------------------------------------------------------------------------
# Сборка
# ---------------------------------------------------------------------------
def particle_key(seg, lemma):
    """Ключ сегмента в словаре частиц: тег приставки, местоимение или служебная лемма."""
    f = seg["features"]
    if seg["role"] == "prefix" and f.get("prefix"):
        return ("prefix", f["prefix"])
    if seg["pos"] == "PRON" and f.get("person"):
        return ("pron", f.get("person", "") + f.get("gender", "") + f.get("number", ""))
    return ("lemma", lemma or "", seg["pos"])


def load_particles(problems):
    """data/particles.json → строки таблицы particles и индекс ключ → id."""
    if not os.path.exists(PARTICLES_PATH):
        problems.append("Нет словаря частиц %s" % os.path.relpath(PARTICLES_PATH, ROOT_DIR))
        return [], {}
    with open(PARTICLES_PATH, encoding="utf-8") as f:
        entries = json.load(f)
    rows, index = [], {}
    for i, e in enumerate(entries, start=1):
        k = e["key"]
        if "prefix" in k:
            key = ("prefix", k["prefix"])
        elif "pron" in k:
            key = ("pron", k["pron"])
        else:
            key = ("lemma", k["lemma"], k["pos"])
        if key in index:
            problems.append("Словарь частиц: повтор ключа %s" % (key,))
            continue
        index[key] = i
        rows.append((i, e["title"], e["gloss"], e["role_ru"], e.get("note") or None,
                     1 if e.get("draft", True) else 0))
    return rows, index


def build(surahs, qac_src):
    os.makedirs(RAW_DIR, exist_ok=True)
    os.makedirs(BUILD_DIR, exist_ok=True)
    manifest = load_manifest()
    problems = []   # расхождения (ошибки сверки)
    notes = []      # известные особенности, не ошибки

    print("Сырые файлы:")
    qac_path = ensure_qac(qac_src, manifest)
    chapters, chapter_paths = load_chapters(manifest)
    verses_by_surah, verse_paths = {}, []
    for s in surahs:
        v, p = load_verses(s, manifest)
        verses_by_surah[s] = v
        verse_paths.extend(p)
    qac, unknown_feats = load_qac(qac_path, surahs)
    for t in sorted(unknown_feats):
        problems.append("QAC: нераспознанный признак %r (сохранён в features.other)" % t)

    # --- суры ---
    surah_rows = []
    for s in surahs:
        if s not in chapters:
            raise SystemExit("Суры %d нет в quran.com /chapters" % s)
        if s not in NAME_RU:
            raise SystemExit("Нет русского названия суры %d: добавьте в NAME_RU" % s)
        c = chapters[s]
        rev = REVELATION.get(c["revelation_place"])
        if rev is None:
            raise SystemExit("Неизвестное место ниспослания %r" % c["revelation_place"])
        surah_rows.append((s, c["name_arabic"], NAME_RU[s], rev, c["verses_count"]))

    # --- аяты и слова quran.com ---
    ayah_rows, qc_words = [], {}
    for s in surahs:
        verses = sorted(verses_by_surah[s], key=lambda v: v["verse_number"])
        nums = [v["verse_number"] for v in verses]
        if nums != list(range(1, len(nums) + 1)):
            problems.append("%d: номера аятов quran.com не подряд: %s" % (s, nums))
        if len(verses) != chapters[s]["verses_count"]:
            problems.append("%d: аятов в /chapters %d, в /verses %d"
                            % (s, chapters[s]["verses_count"], len(verses)))
        qac_ayahs = sorted({a for (ss, a, _) in qac if ss == s})
        if len(qac_ayahs) != len(verses):
            problems.append("%d: аятов у quran.com %d, у QAC %d" % (s, len(verses), len(qac_ayahs)))
        for v in verses:
            a = v["verse_number"]
            raw_text = v["text_uthmani"]
            text = raw_text.strip()  # в API в начале стоит пробел
            tr = [t for t in v.get("translations", []) if t.get("resource_id") == KULIEV_ID]
            tr_text = clean_translation(tr[0]["text"]) if tr else None
            if not tr_text:
                problems.append("%d:%d: нет перевода Кулиева" % (s, a))
            ayah_rows.append((s, a, text, tr_text, "kuliev" if tr_text else None))
            ws = [w for w in sorted(v["words"], key=lambda w: w["position"])
                  if w.get("char_type_name") == "word"]
            others = [w for w in v["words"] if w.get("char_type_name") not in ("word", "end")]
            for w in others:
                notes.append("%d:%d: токен quran.com типа %r (%s) не включён в words"
                             % (s, a, w.get("char_type_name"), w.get("text_uthmani")))
            positions = [w["position"] for w in ws]
            if positions != list(range(1, len(ws) + 1)):
                problems.append("%d:%d: позиции слов quran.com не подряд: %s" % (s, a, positions))
            joined = " ".join(w["text_uthmani"] for w in ws)
            if joined != text:
                problems.append("%d:%d: слова через пробел не дают текст аята\n    аят:   %s\n    слова: %s"
                                % (s, a, text, joined))
            for w in ws:
                qc_words[(s, a, w["position"])] = w

    # --- сверка слов и морфологии ---
    ayah_keys = sorted({(k[0], k[1]) for k in qc_words} | {(k[0], k[1]) for k in qac})
    for (s, a) in ayah_keys:
        n_qc = len([1 for k in qc_words if k[0] == s and k[1] == a])
        qac_pos = sorted(k[2] for k in qac if k[0] == s and k[1] == a)
        if qac_pos != list(range(1, len(qac_pos) + 1)):
            problems.append("%d:%d: позиции слов QAC не подряд: %s" % (s, a, qac_pos))
        if n_qc != len(qac_pos):
            problems.append("%d:%d: слов у quran.com %d, у QAC %d" % (s, a, n_qc, len(qac_pos)))

    # --- корни и леммы: id по порядку первого появления (детерминированно) ---
    root_ids, lemma_ids, lemma_rows = {}, {}, []
    lemma_by_text = {}   # (text,pos) -> lemma_bw, для поиска омографов
    lemma_root_seen = {}

    def get_root(root_bw):
        if root_bw is None:
            return None
        if root_bw not in root_ids:
            root_ids[root_bw] = len(root_ids) + 1
        return root_ids[root_bw]

    def get_lemma(seg):
        lb = seg["lemma_bw"]
        if lb is None:
            return None
        key = (lb, seg["pos"])
        rid = get_root(seg["root_bw"])
        if key not in lemma_ids:
            text = lemma_text(lb)
            prev = lemma_by_text.get((text, seg["pos"]))
            if prev is not None and prev != lb:
                problems.append("%s: леммы QAC %r и %r дают один арабский текст %s (%s); "
                                "во второй оставлен номер QAC" % (seg["loc"], prev, lb, text, seg["pos"]))
                text = text + re.search(r"\d*$", lb).group(0)
            lemma_by_text[(text, seg["pos"])] = lb
            lemma_ids[key] = len(lemma_ids) + 1
            lemma_rows.append((lemma_ids[key], text, rid, seg["pos"]))
            lemma_root_seen[key] = seg["root_bw"]
        elif lemma_root_seen[key] != seg["root_bw"]:
            problems.append("%s: у леммы %r разные корни: %r и %r"
                            % (seg["loc"], lb, lemma_root_seen[key], seg["root_bw"]))
        return lemma_ids[key]

    # --- словарь частиц (наш, data/particles.json) ---
    particle_rows, particle_index = load_particles(problems)

    word_rows, seg_rows = [], []
    for key in sorted(qc_words):
        s, a, p = key
        w = qc_words[key]
        segs = qac.get(key)
        addr = "%d:%d:%d" % key
        if not segs:
            problems.append("%s: у слова %s нет морфологии QAC" % (addr, w["text_uthmani"]))
            segs = []
        seg_ids = [x["seg"] for x in segs]
        if segs and seg_ids != list(range(1, len(segs) + 1)):
            problems.append("%s: номера сегментов QAC не подряд: %s" % (addr, seg_ids))

        lemma_id = root_id = None
        stems = [x for x in segs if x["role"] == "stem"]
        if segs and len(stems) == 0:
            problems.append("%s: в QAC нет сегмента-основы (stem)" % addr)
        if len(stems) > 1:
            notes.append("%s: %d основы в QAC (%s); лемма слова взята по первой основе"
                         % (addr, len(stems), "+".join(x["pos"] for x in stems)))
        for x in segs:
            lid = get_lemma(x)
            if x["role"] == "stem":
                if x["pos"] in NOMINAL_VERBAL_POS and x["lemma_bw"] is None:
                    problems.append("%s: у основы %s (%s) нет леммы" % (addr, x["text"], x["pos"]))
                if x is stems[0]:
                    lemma_id = lid
                    root_id = get_root(x["root_bw"])
            pid = None
            if x["role"] != "stem" or x["pos"] not in NOMINAL_VERBAL_POS:
                pkey = particle_key(x, lemma_text(x["lemma_bw"]) if x["lemma_bw"] else None)
                pid = particle_index.get(pkey)
                if pid is None:
                    notes.append("%s:%d: нет записи в словаре частиц для %s (%s)"
                                 % (addr, x["seg"], x["text"], pkey))
            seg_rows.append((s, a, p, x["seg"], x["text"], x["role"], x["pos"],
                             json.dumps(x["features"], ensure_ascii=False, sort_keys=True,
                                        separators=(",", ":")),
                             lid, pid))

        if segs:
            concat = "".join(x["text"] for x in segs)
            if skeleton(concat) != skeleton(w["text_uthmani"]):
                problems.append("%s: скелет не совпадает: quran.com %s [%s] / QAC %s [%s]"
                                % (addr, w["text_uthmani"], skeleton(w["text_uthmani"]),
                                   concat, skeleton(concat)))
            elif concat != w["text_uthmani"]:
                notes.append("%s: орфография различается (скелет совпал): quran.com %s / QAC %s"
                             % (addr, w["text_uthmani"], concat))

        translit = (w.get("transliteration") or {}).get("text")
        gloss_en = (w.get("translation") or {}).get("text")
        audio = w.get("audio_url")
        if not translit:
            problems.append("%s: нет транскрипции" % addr)
        if not gloss_en or not gloss_en.strip():
            problems.append("%s: пустой английский пословный перевод" % addr)
        if not audio:
            problems.append("%s: нет пути к аудио" % addr)
        word_rows.append((s, a, p, w["text_uthmani"], translit, None, gloss_en,
                          lemma_id, root_id, audio))

    for key in sorted(qac):
        if key not in qc_words:
            problems.append("%d:%d:%d: слово есть в QAC, но нет у quran.com" % key)

    root_rows = sorted((rid, root_text(rb)) for rb, rid in root_ids.items())
    lemma_rows.sort()

    # --- источники ---
    def combined_sha(paths):
        h = hashlib.sha256()
        for pth in sorted(paths):
            h.update(os.path.relpath(pth, RAW_DIR).encode("utf-8"))
            h.update(b"\0")
            h.update(sha256_file(pth).encode("ascii"))
            h.update(b"\n")
        return h.hexdigest()

    def latest_date(paths):
        return max(manifest[os.path.relpath(pth, RAW_DIR)]["retrieved_at"] for pth in paths)

    qc_paths = chapter_paths + verse_paths
    qc_sha = combined_sha(qc_paths)
    qc_date = latest_date(qc_paths)
    qac_sha = sha256_file(qac_path)
    qac_date = manifest[QAC_REL]["retrieved_at"]

    source_rows = [
        ("qurancom_text", "Quran.com API v4: текст аятов и слов (Uthmani), сведения о сурах",
         "https://quran.com", "Условия использования API не уточнены (см. docs/sources.md)",
         "Текст аятов и слов: Quran.com (api.quran.com)", qc_date, qc_sha),
        ("qurancom_wbw", "Quran.com API v4: пословный перевод (англ.), транскрипция, озвучка слов",
         "https://quran.com", "Условия не уточнены; для личного использования",
         "Пословный перевод, транскрипция и озвучка слов: Quran.com", qc_date, qc_sha),
        ("kuliev", "Перевод смыслов Корана, Эльмир Кулиев (quran.com, translation 45)",
         "https://quran.com", "Авторское право; для App Store нужно разрешение",
         "Перевод смыслов: Эльмир Кулиев", qc_date, qc_sha),
        ("qac", "Quranic Arabic Corpus, morphology v0.4 (Kais Dukes)",
         "http://corpus.quran.com", "GNU GPL; копировать без изменений, указывать источник со ссылкой",
         "Морфология: Quranic Arabic Corpus (Kais Dukes), corpus.quran.com", qac_date, qac_sha),
        ("tanzil", "Tanzil Quran Text (Uthmani, 1.0.2), в составе файла QAC: текст сегментов",
         "http://tanzil.net", "CC BY-ND 3.0 (по шапке файла QAC); текст не изменять",
         "Текст Корана: Tanzil Project, tanzil.net", qac_date, qac_sha),
    ]

    # --- дата сборки: детерминированно ---
    sde = os.environ.get("SOURCE_DATE_EPOCH")
    if sde:
        built_at = datetime.datetime.utcfromtimestamp(int(sde)).strftime("%Y-%m-%dT%H:%M:%SZ")
    else:
        built_at = max(qc_date, qac_date)

    meta_rows = [
        ("schema_version", SCHEMA_VERSION),
        ("data_version", DATA_VERSION),
        ("built_at", built_at),
        ("surahs", ",".join(str(s) for s in surahs)),
    ]
    for pth in sorted([qac_path] + qc_paths):
        rel = os.path.relpath(pth, RAW_DIR)
        meta_rows.append(("sha256:" + rel, sha256_file(pth)))
        meta_rows.append(("retrieved_at:" + rel, manifest[rel]["retrieved_at"]))
    meta_rows.sort()

    # --- запись базы ---
    tmp_db = DB_PATH + ".tmp"
    if os.path.exists(tmp_db):
        os.remove(tmp_db)
    con = sqlite3.connect(tmp_db)
    con.executescript(SCHEMA_SQL)
    con.executemany("INSERT INTO meta VALUES (?,?)", meta_rows)
    con.executemany("INSERT INTO sources VALUES (?,?,?,?,?,?,?)", source_rows)
    con.executemany("INSERT INTO surahs VALUES (?,?,?,?,?)", surah_rows)
    con.executemany("INSERT INTO ayahs VALUES (?,?,?,?,?)", ayah_rows)
    con.executemany("INSERT INTO roots VALUES (?,?)", root_rows)
    con.executemany("INSERT INTO lemmas VALUES (?,?,?,?)", lemma_rows)
    con.executemany("INSERT INTO words VALUES (?,?,?,?,?,?,?,?,?,?)", word_rows)
    con.executemany("INSERT INTO particles VALUES (?,?,?,?,?,?)", particle_rows)
    con.executemany("INSERT INTO segments VALUES (?,?,?,?,?,?,?,?,?,?)", seg_rows)
    con.commit()
    fk = con.execute("PRAGMA foreign_key_check").fetchall()
    for row in fk:
        problems.append("Нарушение внешнего ключа: %r" % (row,))
    con.execute("VACUUM")
    con.close()
    os.replace(tmp_db, DB_PATH)

    # --- отчёт ---
    counts = [("surahs", len(surah_rows)), ("ayahs", len(ayah_rows)), ("words", len(word_rows)),
              ("segments", len(seg_rows)), ("lemmas", len(lemma_rows)), ("roots", len(root_rows)),
              ("sources", len(source_rows)), ("meta", len(meta_rows))]
    lines = ["Сборка quran.sqlite, данные %s, схема %s" % (DATA_VERSION, SCHEMA_VERSION),
             "Суры: %s" % ", ".join(str(s) for s in surahs),
             "Дата (built_at): %s" % built_at, "",
             "Строк в таблицах:"]
    lines += ["  %-9s %d" % c for c in counts]
    lines += ["", "Слов по сурам (quran.com / QAC):"]
    for s in surahs:
        lines.append("  %3d: аятов %d, слов %d / %d" % (
            s, len([r for r in ayah_rows if r[0] == s]),
            len([k for k in qc_words if k[0] == s]), len([k for k in qac if k[0] == s])))
    lines += ["", "РАСХОЖДЕНИЯ (%d):" % len(problems)]
    lines += ["  - " + p for p in problems] if problems else ["  нет"]
    lines += ["", "Известные особенности, не ошибки:",
              "  - gloss_ru пуст у всех %d слов: ждём разрешения Quran Academy" % len(word_rows)]
    lines += ["  - " + n for n in notes]
    lines.append("")
    with open(REPORT_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("\n".join(lines))
    print("База: %s\nОтчёт: %s" % (DB_PATH, REPORT_PATH))
    return len(problems)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--surahs", default=",".join(str(s) for s in DEFAULT_SURAHS),
                    help="номера сур через запятую (по умолчанию 1,112,113,114)")
    ap.add_argument("--qac", help="путь к скачанному файлу QAC v0.4 (нужен один раз)")
    ap.add_argument("--strict", action="store_true",
                    help="код выхода 1, если есть расхождения")
    args = ap.parse_args()
    try:
        surahs = sorted({int(x) for x in args.surahs.split(",") if x.strip()})
    except ValueError:
        raise SystemExit("--surahs: нужны номера через запятую")
    if not surahs or any(s < 1 or s > 114 for s in surahs):
        raise SystemExit("--surahs: номера от 1 до 114")
    n = build(surahs, args.qac)
    if n and args.strict:
        sys.exit(1)


if __name__ == "__main__":
    main()
