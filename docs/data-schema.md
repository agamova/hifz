# Схема данных `quran.sqlite` (схема 2)

Файл собирает `tools/build_data.py` (агент `data-pipeline`), приложение только читает его. Все тексты в UTF-8, арабский — как в источнике, без изменений.

```sql
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
-- schema_version = '1', built_at = ISO-дата

CREATE TABLE sources (
  id TEXT PRIMARY KEY,        -- 'tanzil', 'qac', 'qurancom_wbw', 'kuliev'
  name TEXT NOT NULL,
  url TEXT NOT NULL,
  license TEXT NOT NULL,
  attribution TEXT NOT NULL,  -- строка для экрана «Источники»
  retrieved_at TEXT NOT NULL,
  sha256 TEXT                 -- хэш сырого файла, если есть
);

CREATE TABLE surahs (
  id INTEGER PRIMARY KEY,     -- 1..114
  name_ar TEXT NOT NULL,      -- الفاتحة
  name_ru TEXT NOT NULL,      -- Аль-Фатиха
  revelation TEXT NOT NULL,   -- 'meccan' | 'medinan'
  ayah_count INTEGER NOT NULL
);

CREATE TABLE ayahs (
  surah INTEGER NOT NULL,
  ayah INTEGER NOT NULL,
  text TEXT NOT NULL,         -- Tanzil Uthmani, без номера аята
  translation_ru TEXT,        -- перевод смыслов
  translation_source TEXT,    -- id из sources
  PRIMARY KEY (surah, ayah)
);

CREATE TABLE roots (
  id INTEGER PRIMARY KEY,
  text TEXT NOT NULL UNIQUE   -- 'ر ب ب' (буквы через пробел)
);

CREATE TABLE lemmas (
  id INTEGER PRIMARY KEY,
  text TEXT NOT NULL,         -- лемма с огласовками, арабскими буквами
  root_id INTEGER REFERENCES roots(id),
  pos TEXT NOT NULL,          -- 'N','V','P','PRON',... как в QAC
  UNIQUE (text, pos)
);

CREATE TABLE words (
  surah INTEGER NOT NULL,
  ayah INTEGER NOT NULL,
  position INTEGER NOT NULL,  -- 1..N в аяте
  text TEXT NOT NULL,         -- слово как в Tanzil
  translit TEXT,              -- латиницей
  gloss_ru TEXT,              -- пословный перевод (пока может быть NULL)
  gloss_en TEXT,              -- запасной пословный перевод
  lemma_id INTEGER REFERENCES lemmas(id),   -- лемма основы (stem)
  root_id INTEGER REFERENCES roots(id),
  audio TEXT,                 -- относительный путь, напр. 'wbw/114_001_001.mp3'
  PRIMARY KEY (surah, ayah, position)
);

CREATE TABLE segments (
  surah INTEGER NOT NULL,
  ayah INTEGER NOT NULL,
  position INTEGER NOT NULL,
  seg INTEGER NOT NULL,       -- 1..K, порядок справа налево
  text TEXT NOT NULL,         -- текст сегмента с огласовками
  role TEXT NOT NULL,         -- 'prefix' | 'stem' | 'suffix'
  pos TEXT NOT NULL,          -- часть речи QAC: 'P','N','V','PRON',...
  features TEXT NOT NULL,     -- JSON: {"case":"GEN","gender":"M","number":"S","person":"3","aspect":"PERF","mood":"JUS","form":"IV","state":"DEF",...}
  lemma_id INTEGER REFERENCES lemmas(id),
  particle_id INTEGER REFERENCES particles(id),  -- значение служебной части (схема 2)
  PRIMARY KEY (surah, ayah, position, seg)
);

-- Наш словарь частиц, приставок и местоимений (data/particles.json, в git).
-- Сегмент находит запись по ключу: тег приставки QAC (bi+), местоимение (3MP)
-- или служебная лемма + pos (مِن, P).
CREATE TABLE particles (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,        -- «би»
  gloss TEXT NOT NULL,        -- «с, посредством; к»
  role_ru TEXT NOT NULL,      -- «предлог»
  note TEXT,
  draft INTEGER NOT NULL      -- 1, пока не проверено человеком
);

CREATE INDEX words_lemma ON words(lemma_id);
CREATE INDEX words_root ON words(root_id);
```

Правила:

- `words.text` — точная подстрока аята, слова по порядку; склеенные через пробел, они дают `ayahs.text` (без знаков остановки, если те в Tanzil отдельными токенами — тогда они остаются в `ayahs.text`, но не попадают в `words`).
- Знакомость «та же форма / та же лемма / тот же корень» приложение вычисляет само по `words.text` (сравнение без огласовок падежного окончания делаем позже), `lemma_id` и `root_id`.
- Формы слова (ед./дв./мн., спряжение) появятся в версии 0.2 отдельными таблицами.
