# Дизайн: `ci-gate` hardening (1.8.0)

**Дата:** 2026-08-21
**Автор:** Sergei (umar-s) + Claude
**Статус:** спека → премортем → реализация
**Источник:** `docs/audits/2026-08-21-dmitriy-toolkit-v3-audit.md` §3.3 (G5–G11, G13), §8 п. 2
**Версия:** 1.7.1 → 1.8.0 (minor: новые слои и новое поведение маркера)

---

## 1. Назначение

Закрыть три класса дыр в детерминированном гейте, которые аудит назвал прямым
нарушением аксиомы «две независимые линии качества»:

1. **Гейт судит MR, который его же и правит** (G5) — сегодня исполнитель
   может ужать `SQL_RE` или расширить allowlist в том же MR.
2. **Секрет обнаружен, а что дальше — неизвестно** (G6): под стрессом делают
   scrub до revoke.
3. **Гейт видит не всё, что уходит наружу** (G8, G11, G13): текст
   close-комментария не сканируется; trojan-source в диффе не видит ни один
   слой; `commit --no-verify` / amend / история с другой машины доходят до
   remote без скана.

Плюс три мелких: повторяемый негативный контроль (G7), обязательная причина в
маркере (G9), скаффолд не перетирает чужой `.pre-commit-config.yaml` (G10).

Не меняется: аксиомы (гейт — пол, LLM — ревью; ни один слой не заявляет
покрытие другого), payload self-contained, discipline fixed / commands
project-specific, fail-closed (`exit 2`) на любой поломке инструмента.

## 2. Факты, на которые опирается дизайн (проверено 2026-08-21)

- gitleaks 8.30.1: `gitleaks dir <file>` сканирует одиночный файл
  (rc 0/1); `protect --staged` и `detect` — скрытые алиасы, работают; `git
  --staged` — новая форма. Существующие вызовы не трогаем (не цель релиза).
- pre-commit, stage `pre-push`: stdin хукам **не передаётся**; даётся
  `PRE_COMMIT_FROM_REF` / `PRE_COMMIT_TO_REF` (+ `REMOTE_NAME`, `REMOTE_URL`,
  `REMOTE_BRANCH`, `LOCAL_BRANCH`). Для новой ветки pre-commit сам
  вычисляет `from_ref` = родитель первого коммита, которого нет на remote;
  если на remote нет ни одного предка — `all_files=True` и `FROM_REF`/`TO_REF`
  **не выставлены**. Обрабатывает **только первую** строку stdin (один ref
  за push). Установка: `pre-commit install --hook-type pre-push`.
- Байтовые regex на code points: `LC_ALL=C awk` с `ENVIRON` матчит диапазоны
  байтов ≥0x80 одинаково на gawk 5 / mawk / busybox awk; **GNU grep в
  C-локали молча не матчит такие диапазоны (rc 1)** — grep для этого слоя
  запрещён как fail-open; gawk в UTF-8-локали падает (`fatal: invalid
  regexp`) — это rc 2, fail-closed, но локаль всё равно фиксируем.
- GitHub branch protection: `required_pull_request_reviews: {
  require_code_owner_reviews: true, required_approving_review_count: 1 }`.
  Автор не может аппрувить свой PR → на соло-репо это блокирует merge.
  GitLab: `code_owner_approval_required` на protected branch — **Premium**;
  на Free CODEOWNERS только назначает ревьюеров.

## 3. Решения по пунктам

### G5 — гейт защищён от MR, который он судит

- Новый файл payload `templates/ci-gate/CODEOWNERS` → корень репо
  (читается и GitHub, и GitLab): `/ci/`, `/.gitleaks.toml`,
  `/.pre-commit-config.yaml`, `/CODEOWNERS`, `/.github/workflows/gate.yml`
  (GitHub) / `/.gitlab-ci.yml` (GitLab) → `@OWNER` (плейсхолдер; скилл
  спрашивает владельца гейта, если не выводится из `CLAUDE.md`).
- SKILL.md шаг 2: копировать; если CODEOWNERS уже есть — дописать строки.
  Шаг 5: к protected-branch добавить required code-owner review (GitHub JSON
  с `require_code_owner_reviews`; GitLab — `code_owner_approval_required=true`
  с пометкой «Premium; на Free — advisory, назовите это вслух»). Соло-репо:
  честная оговорка — второй аккаунт или без enforce, но файл всё равно
  кладём (видимость + request-review).
- Шаг 6 (негативный контроль): MR, ужимающий `SQL_RE` / расширяющий
  allowlist, должен требовать аппрув владельца гейта.
- `ci/README.md`: абзац «Known limits» уже говорит «CODEOWNERS — следующий
  слой»; заменить на «вот он».
- Dogfood: `CODEOWNERS` и в этом репозитории (`/templates/ci-gate/`,
  `/scripts/`, `/tests/`, `/.github/` → `@umar-s`). Enforce на
  `umar-s/task-flow` — решение владельца, не этого релиза.

### G6 — плейбук «secret-scan сработал»

Секция в `ci/README.md`, порядок жёсткий:
1. **Revoke/rotate у провайдера — первым**, до любых действий в git: форки,
   клоны, CI-логи и кэши уже держат старую историю; вычищенная история с
   живым ключом — живой ключ.
2. Окно экспозиции: когда закоммичено (`git log -S'<prefix>' --all`), был ли
   репо публичным / зеркалился / форкался, попал ли секрет в CI-логи и
   артефакты.
3. Ещё не в shared-ветке → убрать из ветки (amend/rebase) и `push --force`
   **своей** ветки; default-ветка не тронута.
4. Уже в shared-ветке → scrub (`git filter-repo --replace-text`) — это
   force-push, который наш же protected-branch запрещает: снять защиту
   **осознанно, на время, с записью** (кто/когда/зачем), вернуть, всем
   re-clone.
5. Аудит: логи доступа провайдера за окно; если gitleaks пропустил вариант —
   правило в `.gitleaks.toml`, не allowlist.
6. Никогда не allowlist «потому что уже ротирован».

### G7 — `gate.sh --selftest`

Повторяемый негативный контроль шага 6, в payload:
- временный `git init`, фикстуры под **первым** каталогом реального
  `MIGRATION_DIRS`; предварительно: если **ни один** из `MIGRATION_DIRS` не
  существует в репо — `warn` «guard watches empty dirs» (это и есть детектор
  mis-set, который selftest внутри temp-репо иначе не видит);
- ожидания: unmarked `DROP TABLE` → rc 1 с текстом `FAIL [destructive]`;
  marked (с причиной) → rc 0; изменённая закоммиченная миграция → rc 1
  `FAIL [immutable]`; голый маркер без причины → rc 1 (G9); сломанный
  `awk` (PATH-стаб) → rc 2; строка-кредшл (AWS-форма, генерируется) →
  gitleaks rc 1 **с реальным `.gitleaks.toml` репо** (allowlist `.*` → selftest
  красный — это контроль на allowlist); чистая миграция → rc 0;
  unicode-guard: RLO в добавленной строке → rc 1, чистая → 0;
- вывод: таблица `ok/FAIL` по каждому контролю, итог rc 0 только при полном
  совпадении; rc 2 — если сам selftest не смог (нет git/mktemp).
- Наш репо: `tests/gate-selftest.sh` гоняет `--selftest` в temp-репо и
  **негативный контроль самого selftest**: `SQL_RE` опустошён → selftest
  red; allowlist `paths=['''.*''']` → red.

### G8 — `ci/scan-text.sh <file>` (scan-at-sink)

- `gitleaks dir <file> --config <repo>/.gitleaks.toml --redact --no-banner`
  тем же резолвом, что `gate.sh` (PATH / pinned, `GATE_PINNED_ONLY`);
  rc 0 чисто · 1 найдено · 2 инфра (нет файла, нет gitleaks, rc ≥2).
- Path-allowlist применяется к имени файла: временный файл называть
  нейтрально (не `*.example`). Документировать.
- `task` §8: close-комментарий и описание MR → файл → `scan-text.sh` (если в
  репо есть гейт) → постится **тот же файл**. Две строки в SKILL.md; в
  `implementation-integrity.md` §6 не трогаем.

### G9 — маркер обязан нести причину

- `APPROVAL_RE='destructive:[[:space:]]*approved[[:space:]]*\([^)]*[[:alnum:]][^)]*\)'`
  — хотя бы один буквенно-цифровой символ в скобках.
- FAIL-сообщение показывает форму: `-- destructive: approved (TICKET-123:
  data archived)`; голый маркер → отдельное сообщение «marker present but
  carries no reason».
- Фикстуры: голый, `()`, `(  )` → 1; `(T-1)` → 0. CHANGELOG «Changed».
- SKILL.md guardrail и README — форма с причиной.

### G10 — мерж, не перезапись

SKILL.md шаг 2: `.pre-commit-config.yaml` существует → добавить два
`repos:`-элемента в существующий; `.gitleaks.toml` существует → добавить
`[[allowlists]]` к существующему, не терять `[extend]`; `CODEOWNERS` —
дописать строки. То же правило, что для `.gitlab-ci.yml`.

### G11 — `ci/unicode-guard.sh`

- Вход: добавленные строки диффа (`git diff --cached -U0` при `--staged`,
  иначе `BASE...HEAD -U0`, резолв BASE как в migration-guard); бинарные
  файлы пропускаются (git их не показывает в `-U0` текстом).
- Набор: bidi `U+202A–202E`, `U+2066–2069`; zero-width `U+200B`, `U+2060`,
  `U+FEFF` (кроме BOM в позиции 1 строки); tag block `U+E0000–E007F`.
  **Не** в наборе: ZWJ/ZWNJ (`U+200C/200D` — emoji-последовательности,
  арабская/персидская типографика), LRM/RLM (`U+200E/200F`), SHY
  (`U+00AD`). Известный ложный плюс: subdivision-флаги (🏴 + tag-последовательность).
- Реализация: `LC_ALL=C awk`, regex через `ENVIRON` байтами; парсинг hunk
  `@@ … +c,d @@` → номер строки; вывод `path:line: <имя code point>`.
  Никакого grep для матчинга (факт §2). awk rc ≠ 0 → exit 2.
- `UNICODE_GUARD_EXCLUDE` — ERE по путям (vendored шрифты, i18n), по
  умолчанию пусто.
- Wiring: **активен** везде, где есть гейт — `gate.sh`, pre-commit hook,
  три CI-файла (job `unicode-guard`), required contexts. Отклонение от
  аудита («commented job»): слой, включённый наполовину, — «green by
  omission», наш же принцип из `task` §8; ложные плюсы набора ≈ 0, стоимость
  ≈ 0.

### G13 — pre-push-слой

- `ci/pre-push.sh`: два режима. (a) **native hook** — строки
  `<local ref> <local sha> <remote ref> <remote sha>` со stdin, все refs;
  (b) **pre-commit** — `PRE_COMMIT_FROM_REF`/`TO_REF`; если `TO_REF` не
  задан (pre-commit: `all_files`) → полная история `HEAD`.
- Диапазон на ref: delete (local sha = 0⁴⁰) → пропуск; remote sha ≠ 0 и есть
  локально → `remote..local`; иначе merge-base с default-веткой
  (`refs/remotes/<remote>/HEAD` → `main`/`master`) → `mb..local`; нет
  merge-base → вся история `local` (сканировать больше, никогда меньше).
- Скан: `gitleaks detect --log-opts=<range>` тем же резолвом/пином.
- **Fail-closed:** любой `git` rc ≠ 0 или gitleaks rc ≥ 2 → BLOCK (rc 2).
- Обход: `GATE_PREPUSH_SKIP="<reason>"` — непустая причина; запись
  `date user ref reason` в `$(git rev-parse --git-dir)/gate-bypass.log`;
  пустая причина → не обход.
- Wiring: `.pre-commit-config.yaml` — hook `stages: [pre-push]`; README —
  `pre-commit install --hook-type pre-push`, либо без pre-commit
  `cp ci/pre-push.sh .git/hooks/pre-push`. Ограничение pre-commit (один ref)
  — документировать.
- Тесты (`tests/pre-push.sh`): bare remote; секрет в новом коммите → 1;
  чистый → 0; amend поверх запушенного (remote sha не предок) → 1; remote sha
  неизвестен локально → fallback, 1; новая ветка без merge-base → полная
  история, 1; delete → 0 без скана; `git` сломан → 2; `GATE_PREPUSH_SKIP`
  с причиной → 0 + строка в журнале, без причины → 1; режим env
  (`PRE_COMMIT_*`).

## 4. Что меняется в файлах

| Файл | Изменение |
|---|---|
| `templates/ci-gate/ci/gate.sh` | `--selftest`; шаг unicode-guard |
| `templates/ci-gate/ci/migration-guard.sh` | `APPROVAL_RE` с причиной; сообщения |
| `templates/ci-gate/ci/scan-text.sh` | новый |
| `templates/ci-gate/ci/unicode-guard.sh` | новый |
| `templates/ci-gate/ci/pre-push.sh` | новый |
| `templates/ci-gate/CODEOWNERS` | новый |
| `templates/ci-gate/.pre-commit-config.yaml` | hooks unicode-guard, pre-push |
| `templates/ci-gate/{gitlab,github}/*` | job `unicode-guard` |
| `templates/ci-gate/ci/README.md` | таблица слоёв, G6 плейбук, G9 форма, selftest, scan-text, pre-push, CODEOWNERS |
| `skills/ci-gate/SKILL.md` | шаги 2/3/5/6, guardrails |
| `skills/task/SKILL.md` | §8 scan-at-sink (2 строки) |
| `CODEOWNERS` (репо) | dogfood |
| `tests/{gate-selftest,unicode-guard,pre-push}.sh`, `tests/migration-guard.sh`, `tests/run.sh` | негативные контроли |
| `scripts/lint.sh` | новые payload-скрипты в check 3/4 автоматически (`ci/*.sh`); инвариант «unicode-guard не использует grep для матчинга»; SKILL.md перечисляет все файлы payload |
| `README.md` / `README.ru.md` | слои гейта (lockstep) |
| `CHANGELOG.md`, `plugin.json` | 1.8.0; «Changed» для G9 и активного unicode-guard |

## 5. Не делаем

- Парсер вместо regex в migration-guard (residue → 6b).
- Advisory-скан на Read (gsd) — не наш класс.
- Enforce CODEOWNERS на `umar-s/task-flow` — owner.
- Переход `protect`/`detect` → `git`/`dir` в существующих вызовах — работает,
  не цель релиза.

## 6. Критерии приёмки

- `scripts/lint.sh`, `scripts/release-check.sh`, `tests/run.sh` зелёные
  локально и в `check.yml`; новые фикстуры падают на версии 1.7.1 guard'а
  (проверено руками хотя бы для G9 и unicode-guard).
- Чистое ревью (code + security) по артефактам — «Ready: Yes».
- `claude plugin validate .` без новых ошибок; `claude plugin details` — вес
  `ci-gate` SKILL.md вырос не более чем на ~15 %.
- Релиз: bump + CHANGELOG + тег + GitHub Release; README×2 lockstep.
