# Дизайн: `decompose` — проверяемые задачи и честная запись в трекер (1.10.0)

**Дата:** 2026-08-22
**Автор:** Sergei (umar-s) + Claude
**Статус:** спека → премортем → реализация
**Источник:** `docs/audits/2026-08-21-dmitriy-toolkit-v3-audit.md` §3.2 (C1–C14),
§4 O5 (авторская сторона), §8 п. 4
**Версия:** 1.9.0 → 1.10.0 (minor: новые проверки QA и новые операции адаптера)

---

## 1. Что чинит этот релиз

`decompose` режет эпик на связанные задачи и (опционально) заливает их в
трекер. Аудит нашёл два класса дыр:

1. **Задача выглядит поставленной, но не исполнима.** Цель без артефакта
   («обеспечить корректную обработку»), прилагательное без метрики, «и т.д.»
   в перечислении, придуманный путь или env-переменная, которых нет в репо, —
   всё это проходит текущие 8 проверок и всплывает на фазе 0 у `task`.
2. **Запись в трекер верит своей же стороне.** `ok` от адаптера — заявление
   записывающей стороны: ни read-back, ни preflight (типы issue, поля, шкала
   estimate, типы связей), ни объявленной разметки description. Частичный
   отказ посреди создания N задач сегодня не отличим от успеха.

Не меняется: контракт **6 авторских полей** и 4 членов `dod`, счётчик
«8 checks», `wave` как вычисляемое поле, `story_points` как аннотация, а не
триггер дробления, и generic-адаптер (YouTrack — иллюстрация, не контракт).

## 2. Решения по пунктам

### 2.1 Черновик и схема (C1, C2, C3, C6, O5)

- **C1 код читается до первого вопроса.** Перед первым вопросом — Grep/Read по
  коду, которого касается вход; первый вопрос цитирует `path:line`. Память и
  handoff-заметки — recall, не authority.
- **C2 `## Out of scope`** в `draft-template.md`: таблица «фрагмент входа →
  решение · почему», и для сознательно исключённого, и для вырезанного из
  исходного текста.
- **C3** `context` может заканчиваться строкой
  `Not in this task: <what> — <TASK-ID> owns it`.
- **C6 плейсхолдер вместо выдумки:** путь, таблица, env-var, хост, команда, не
  найденные в репо/доках, пишутся как `<placeholder>` и попадают в раздел
  «Заполнить перед отправкой».
- **O5 авторская сторона:** `context` может нести
  `risk tier: T1|T2|T3 — <почему>` (принимающая сторона уже сделана в 1.9.0 —
  пол, не потолок).

### 2.2 QA-чеклист (C5, C7, C8) — счётчик остаётся 8

- **Check 2 → «Field completeness and quality»:** WARNING за глагол-цель без
  артефакта (`ensure/support/handle/properly/correctly/improve`), субъективное
  прилагательное без метрики, «и т.д.» в перечислении; каждое существительное
  в `context`/`dod` локализуемо (path / symbol / endpoint); `@`-ссылки
  разрешимы (`test -e`, grep символа).
- **Check 5** дополняется контрактом producer → consumer: артефакт, как он
  назван в `dod.done` родителя, совпадает с тем, что ожидает `context`
  потомка.
- **C8 convergence guard:** один и тот же набор BLOCKER два прогона подряд →
  эскалация к пользователю, а не третий раунд. PASS по-прежнему только с
  чистого прогона.

### 2.3 Edge-probe (C4)

Новые shape/категории: `authorization | actor-facing`; `ui`: `surface states`
(loading/empty/error/success; i18n и адаптивность — только если проект их
декларирует) и `interaction` (двойной сабмит, уход со страницы, протухшая
сессия, две вкладки); `infra`: `grants`, `secrets`, `environments`.

### 2.4 Трекер-адаптер (C9–C14)

- **C9 read-back после записи** — третья операция адаптера
  `read_issue(<TASK-ID>)`; после всех create/link перечитать каждую сущность и
  сверить summary/description/links/estimate; расхождение — partial failure в
  отчёте.
- **C10 preflight до dry-run:** одно чтение проекта/эпика + типы issue, поля,
  типы связей, шкала estimate. Dry-run перестаёт обещать то, чего в проекте нет.
- **C11 разметка description** объявляется адаптером:
  `markdown | jira-wiki | adf-via-markdown | plain`.
- **C12 REST как транспорт биндинга**, когда MCP нет, а `CLAUDE.md` называет
  эндпоинт и **имя** env-переменной токена (значение агент не видит).
- **C13 поиск дубликатов** перед созданием (опционально): блок «possible
  duplicates» в dry-run, ошибка поиска печатается и не блокирует.
- **C14 ссылка на драфт** в description (`Source: …, epic <ID>`) и URL
  созданных issue в отчёте.

## 3. Что меняется в файлах

| Файл | Изменение |
|---|---|
| `skills/decompose/SKILL.md` | фаза 0 (C1), фаза 1 (out-of-scope пишется вместе с REQ), фаза 3 (C6 + две advisory-строки, O5), фаза 5 (бриф чекера, convergence guard), фаза 6 (C2, плейсхолдеры), фаза 7 (REST, preflight, read-back, URL), Project bindings |
| `references/draft-template.md` | `## Out of scope`, `## Placeholders`, `Checked against:`, слот advisory-строк в карточке |
| `references/task-schema.md` | C3 (строка + worked example), C6 (секция «Identifiers you could not confirm»), авторская сторона C5, `risk tier` (1.9.0) |
| `references/qa-checklist.md` | Check 1 (вход + out-of-scope), Check 2 (C5, C6), Check 5 (C7), Check 6 (исключение плейсхолдера, владелец `Not in this task:`), output contract (слаги, `repeat`), revision loop (C8) |
| `references/edge-probe.md` | C4 + surface в relevance filter |
| `references/tracker-sync.md` | C9–C14; §1 контракт (`read_issue`, `search_issues`, `describe_project`, `markup`), §3 REST, §5 dry-run, §6 lookup по ключу, §7 маппинг + YouTrack, §8 форма read-back, §9 шаги 1–9, §10 URL |
| `skills/task/SKILL.md` | фаза 0: `Not in this task:` и строки Out of scope → *Not in scope* спеки |
| `scripts/lint.sh` | инварианты, привязанные к секциям/строкам/code-block (не word-grep) |
| `README.md` / `README.ru.md` | lockstep |

*Таблица приведена к фактическим местам после премортема (в первой редакции стояло «§9» в SKILL.md, которого там нет).*

## 4. Не делаем

- Седьмое авторское поле — контракт 6 полей закреплён линтом.
- Смена счётчика проверок (8) — он тоже инвариант.
- Хардкод YouTrack/Jira-специфики вне иллюстраций.

## 5. Критерии приёмки

- `scripts/lint.sh` зелёный, включая старые инварианты словаря `decompose`.
- Каждый новый контракт проверяем грепом или назван как claim.
- README×2 в lockstep; `release-check` UNRELEASED → RELEASED.
- Чистое ревью без blocker'ов.
