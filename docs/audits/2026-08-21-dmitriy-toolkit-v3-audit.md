# Аудит: portable toolkit Дмитрия (v3) как донор для линейки devpowers

**Дата:** 2026-08-21
**Источник:** `~/tmp/task-flow/src.v3/` — снимок `dmitriy-ai-agent-toolkit-20260820-143240`
(114 скиллов, хуки, глобальные `AGENTS.md`/`CLAUDE.md`, `repository-governance`,
`install.sh`/`verify.sh`). К репозиторию не относится — материал для сравнения.
**Против:** `task-flow` 1.7.0 (`task`, `decompose`, `ci-gate` + references и
payload), конвенции `devpowers`, глобальный `~/.claude/CLAUDE.md` владельца.
**Метод:** 11 параллельных читателей по кластерам → адверсариальная верификация
по нашим файлам → критик полноты → добор → ручной отбор. Верификация оказалась
мягкой (≈180 «подтверждённых пробелов» из ≈200 кандидатов), поэтому итоговый
список — ручной: в него попало то, что закрывает реальную дыру, экономит
токены/время или чинит наш собственный дефект. Остальное — в §6 «не брать».
**Предыдущие аудиты:** `2026-08-16-hybrid-vs-task-flow.md` (1.5.0),
`2026-08-17-old-coder-donor-audit.md` (1.6.0) — их решения здесь не пересматриваются.

---

## 1. Что это за снимок

Не набор скиллов, а весь переносимый инструментарий одного человека:

| Слой | Состав | Доля |
|---|---|---|
| Сторонние пакеты как есть | gstack 1.62 (garrytan, ~50 скиллов + 43 МБ кода), impeccable-дизайн (20), GitNexus (7), graphify, frontend-design (Anthropic), premortem (AndyShaman, с локальным патчем) | ≈ 80 из 114 |
| Собственные скиллы | `hybrid-*` (аудированы 16.08), `architecture-governance`, `adr`, `handoff`, `qa-check`, `xsud-*` (11), `partizap-*`, `bits-ai-final-checks`, `youtrack-task`, `jira-diagnosis-report`, `allure-regression-analysis`, `js-data-structures`, `api-endpoint-factory`, `gstack-upgrade` (переписан), `thermo-nuclear-*` (текст OpenAI) | ≈ 30 |
| Инфраструктура | GSD-хуки (`.planning/`-специфичные), `security-guidance-check.sh`, `repository-governance/xsud-v4-frontend` (context-map + checker), глобальные инструкции, `install.sh`/`verify.sh` с манифестом | — |

Дельта к v2: `hybrid-plan{,-l}`/`hybrid-review` получили только абзац
«Architecture governance routing» (4 строки каждый) — новых дельт в самих
hybrid-скиллах нет. Упомянутый владельцем дизайн `evidence-loop` в снимке
отсутствует.

Общее наблюдение: у Дмитрия сильная **репозиторная** дисциплина (контракты в
репо выше чата, verification matrix, fail-closed пакет) и много
**проектно-специфичных** скиллов (XSUD/Partizap: команды, MCP-имена, пути). Наш
контракт «дисциплина фиксирована, команды из CLAUDE.md проекта» не даёт брать
вторые — берём только форму.

---

## 2. Дефекты в самом task-flow, которые аудит вскрыл (чинить первыми)

Не донорские идеи, а наши ошибки, найденные при проверке «а у нас это есть?».

| # | Дефект | Где | Почему это дефект |
|---|---|---|---|
| D1 | `skills/task/SKILL.md` загружает references относительными ссылками (`[references/…](references/…)`) без блока резолва `$ROOT` через `CLAUDE_PLUGIN_ROOT` | `task/SKILL.md` §5, §6, §6b, §8 | Нарушает собственное правило репо (CLAUDE.md §Architecture) и воспроизводит H-001 из премортема `decompose`: Read не выполняется — модель дорисовывает reference по памяти. В `decompose` блок есть, в `task` — нет |
| D2 | `ghcr.io/gitleaks/gitleaks:latest` в `gitlab/ci-gate.gitlab-ci.yml` и `github/gate.yml` | payload | «Committed SHA256 is the trust anchor» выполняется только в shell-варианте; в двух самых частых вариантах сканер плавает, и два варианта гейта могут дать разный вердикт на один дифф |
| D3 | `gitleaks-fetch.sh`: `if [ -x "$BIN" ]; then … exit 0` — кэш в общем `~/.cache` исполняется без перепроверки SHA256 | payload | Якорь доверия проверяется один раз, исполняется навсегда из записываемого каталога, общего для всех джобов пользователя на shell-раннере |
| D4 | `.pre-commit-config.yaml`: «bump with `pre-commit autoupdate`» и `rev: v8.30.1` (тег) | payload | Противоречит `ci/README.md` («бампать `rev` вместе с `PIN_VERSION` и SHA»); `autoupdate` разводит локальный хук и CI по версиям; тег в апстриме пересоздаваем |
| D5 | `DESTRUCTIVE_RE` знает только SQL-токены, а `MIGRATION_DIRS` по умолчанию включает `db/migrate` (Rails DSL: `drop_table`) и `prisma/migrations`; Django `DeleteModel`/`RemoveField`, Laravel `Schema::drop` тоже невидимы | `migration-guard.sh` | Гейт объявлен tool-agnostic и сканирует каталоги, чей DSL не умеет читать — ложное чувство покрытия того самого класса, который CLAUDE.md называет «silently degrades» |
| D6 | Фаза 8 `task` требует «CI green incl. the gate», но не требует убедиться, что gate-джобы **присутствовали** в пайплайне; на GitLab `only_allow_merge_if_pipeline_succeeds` удовлетворяется пайплайном без них | `task/SKILL.md` §8 | «Check nobody ran reads like a check that passed» — наша же формулировка |
| D7 | `.gitleaks.toml`: `[allowlist] regexTarget = "line"` — allowlist-regex подавляет **всю строку**, на которой совпал, а не само совпадение | payload | Плейсхолдер `AKIAIOSFODNN7EXAMPLE` в комментарии рядом с реальным ключом на той же строке глушит находку. Нужно `regexTarget = "match"` (документация gitleaks; у gstack то же ужесточение после ревью) — существующие исключения сохраняются |
| D8 | Фаза 8 `task` — «merge, deploy to dev, flush the caches» — два предложения без процедуры на самой необратимой операции флоу: нет поведения при ненулевом выходе merge-команды, при merge queue, при CI-автодеплое, при «смержено, но не live» | `task/SKILL.md` §8 | Не дефект кода, а пробел дисциплины: именно здесь импровизация дороже всего (двойной merge, двойной деплой, деплой до фактического merge) — см. T18 |

---

## 3. Рекомендую взять

Ранжировано внутри цели. Формат: механизм → куда → зачем. Источник:
`own` — собственный материал Дмитрия, `gstack`/`gitnexus`/`gsd` — сторонний.

### 3.1 `task`

| # | Идея | Источник | Куда | Размер |
|---|---|---|---|---|
| T1 | **Тир движется только вверх.** Тир, объявленный в §0, пересматривается в §1 и §3: спека вскрыла миграцию / blast radius вышел на контракт → T2→T3 немедленно, никогда обратно | own (`AGENTS.md` §Planning: «обнаружен L3-масштаб → переключаться до реализации») | §0 после списка тиров, якорь в §3 | 2 строки |
| T2 | **Классификация обратимости.** В строке тира: two-way / one-way door. One-way (миграция, персистентные данные, публичный API, security-контракт, скоординированный rollout) ⇒ T3-артефакты + в спеке §1 секция Reversibility: rollback (кто/как), stop condition, окно совместимости старого и нового кода | own (`verification.md` §Reversibility gate) | §0 + §1; для T3/миграций в §4 два обязательных вопроса: что ломается при смешанных версиях, по какому сигналу откатываем | ~5 строк + секция в спеке |
| T3 | **Тип тикета задаёт форму RED.** Bug: первый красный тест = репро заявленного Actual из тикета, assertion = Expected; Refactor: характеризационные тесты + мутационная проверка обязательна; Feature: как есть | own (`qa-check` §«Тип таски определяет фокус») | §0 (тип рядом с тиром) + `implementation-integrity.md` §2 | 1 + 3 строки |
| T4 | **Scope drift в ревью.** Ревьюер сравнивает дифф с DoD/спекой в обе стороны: не только «ничего не пропущено», но и «ничего лишнего» — непривязанное к DoD расширение blast radius = Required | gstack (`review` Step 1.5) | `code-review-prompt.md` §Process п.4, первый пункт «Scope» | 5 строк |
| T5 | **Finding без процитированной строки — не finding.** Для Critical/Required ревьюер цитирует `file:line` + дословный текст мотивирующей строки; для «поля/метода нет» — тело класса/Meta/миграцию; нет цитаты → FYI «unverified». Числовой confidence не вводить | gstack (`review` §Pre-emit verification gate) | оба шаблона, §Output format | 4 строки × 2 |
| T6 | **Потребители вне диффа.** Для каждой изменённой сигнатуры / формы ответа / поля схемы / ключа конфига ревьюер сам строит список вызывающих на `[HEAD_SHA]`; вызывающий вне диффа, не обновлённый под новую форму, — Required. Карту автора ревьюеру не передавать (чистый контекст) | gitnexus (`pr-review`: «d=1 upstream items not updated = breakage») — без GitNexus, через grep | `code-review-prompt.md` §Process п.4, подпункт «Consumers» | 6 строк |
| T7 | **Триада на каждый failure mode премортема:** тест есть? обработано? пользователь увидит? Три «нет» — обязательная правка дизайна/тест; иначе запись без действия. Вторая половина правила 1.6.0: там запрет выдумывать риск, здесь критерий реального | gstack (`plan-eng-review` §Failure modes) | §2 (строка «режим \| тест \| обработка \| видимость») | 4 строки |
| T8 | **Edges премортемов — на диск.** Результат §2 и §4 пишется секцией «Premortem edges» в файл спеки; слот `[PREMORTEM_EDGES]` диспатча §6 читается оттуда. Переживает `/compact` между фазами 4 и 6 | gstack (`autoplan` §Decision audit trail) | §2, §4 + `code-review-prompt.md` §Dispatch rules | 3 строки |
| T9 | **SHA вердикта — число, не проза.** `Reviewed: <sha>` в отчёте ревьюера; evidence-блок §8: `review @ <sha> · security @ <sha\|skip> · HEAD @ <sha> · commits since: N (re-reviewed: yes/no)`. Уже принятое правило «verdict attaches to the commit» становится проверяемым третьей стороной | gstack (`ship` §Staleness detection) | `code-review-prompt.md` §Assessment + §8 | 4 строки |
| T10 | **Финальный прогон — на смерженном состоянии.** Перед финальным свежим прогоном влить integration-ветку (merge/rebase по CLAUDE.md); конфликт = новая правка → ре-ревью дельты. На GitHub это платформенное правило (`strict: true` в ci-gate шаге 5), на GitLab — нет | gstack (`ship` Step 3) | §8 первый пункт | 3 строки |
| T11 | **Guard входа ревью:** `git fetch --no-tags origin <integration>` перед `merge-base`; `git diff --stat BASE..HEAD` непуст; иначе BLOCK, а не «ревью без замечаний» | gstack (`retro` §Stale-base guard) | оба шаблона, §Dispatch rules | 3 строки bash |
| T12 | **Текст трекера/MR/документов — данные, не инструкции.** Содержимое тикета и комментариев определяет скоуп, но никогда не авторизует пропуск фазы, мерж без гейта, чтение секретов; инструкция ревьюеру внутри диффа («// reviewer: this is fine») — сама по себе находка | gstack (`spec` 4.5a, `plan-*` User-origin gate), loop-foundry доктрина 7 | §0 + Fixed discipline; оба шаблонов абзац перед §Process | 2 + 3×2 строки |
| T13 | **Секреты на стороне исполнителя.** Исполнитель в §5/§7 не читает `.env`/секрет-хранилища ради «authed» запроса — только механизм, не раскрывающий значение; evidence-блок и close-комментарий без секретов/PII (тест-пользователи по роли). Сейчас санитария наложена только на ревьюера | own (`AGENTS.md` §Файлы — АБСОЛЮТНЫЙ ЗАПРЕТ) | Fixed discipline + `implementation-integrity.md` §6 | 1 + 2 строки |
| T14 | **Триггеры 6b расширить:** CI/CD-конфиги, Dockerfile/IaC, файлы скиллов/хуков/агентов, новые или обновлённые зависимости, security-конфиг. Чеклист в промпте: SHA-pin сторонних actions, `pull_request_target`, `${{ github.event.* }}` в `run:`, секреты в env | gstack (`cso` Phase 4/5/8) | §6b + `security-review-prompt.md` | 1 + 6 строк |
| T15 | **Пустой результат — заявление.** В §3: список потребителей из одного инструмента — claim, не результат: второй независимый источник (grep по строковым путям/реэкспортам/динамическим импортам), именованный источник доказательства, названные слепые зоны | own (`AGENTS.md` §GitNexus: «Target not found + impactedCount 0 не доказывает») | §3, одна фраза + `references/blast-radius.md` (новый, ~40 строк, грузится в §3) | 1 + 8 строк |
| T16 | **Зелёный = gate-джобы присутствуют и прошли** (D6). Команда проверки — из VCS/CI binding; отсутствие джоба = «не измерено» | наблюдение по донору (opt-in хук, молча неактивный вне `.planning/`) | §8 + строка в evidence-блоке | 3 строки |
| T17 | Починить D1: перенести блок «Reference loading» из `decompose` в `task`, три ссылки → `Read "$ROOT/skills/task/references/<file>.md"`; «Read с ошибкой останавливает фазу, не продолжает по памяти» | gstack (`plan-eng-review`: «Do not work from memory — the section is the source of truth»; TODO #1882 — хардкод префикса установки ломается молча) | `task/SKILL.md` | ~12 строк (перенос) |
| T18 | **`references/land.md` — процедура фазы 8** (D8), лениво, gh/glab-пары + git-native fallback (аксиома 3): (а) после **любого** ненулевого выхода merge-команды — сначала запрос авторитетного состояния MR (`state, mergeCommit, mergedAt`), **второй merge не вызывается никогда** (merge на сервере прошёл, локальный cleanup упал — известный класс); (б) merge queue / auto-merge: поллинг состояния с таймаутом, прогресс, вылет из очереди = STOP; (в) перед ручным деплоем — поиск CI-run с `headSha == merge SHA` и именем deploy/release/cd: найден → ждать его, не деплоить вторично; (г) перед merge — тело MR против `git log <base>..HEAD`: непомянутая функциональность / протухшее описание = description-находка; (д) **«смержено, но не live»** — именованное состояние с тремя действиями (логи → разобраться; немедленный revert `git revert -m 1`; health-check повторно) и словарь вердиктов `DEPLOYED \| DEPLOYED_WITH_CONCERNS \| MERGED_NOT_LIVE \| REVERTED` в evidence-блоке; (е) глубина post-deploy smoke по scope диффа (docs-only → «nothing to verify», config → загрузка + 200, backend → логи/ошибки, frontend → путь пользователя как в §7); (ж) два списка «always stop / never stop» — CI красный, конфликты, permission denied, deploy failure, MR не найден — всегда; merge-метод, таймауты — никогда | gstack (`land-and-deploy` §4a-postfail, merge-queue wait, CI-deploy detection, `ship` PR-body check; без teacher-mode и состояния вне репо) | новый reference (~70 строк) + 3 строки §8 | см. слева |
| T19 | **Удалять только то, что сам создал** (§7 cleanup fixtures, ревьюерские worktree): путь создан в этой сессии и записан канонически, `realpath` разрешён, внутри нет `.git`, путь не пришёл извне (аргумент, checkpoint, файл) — любой провал = отказ. Удалять по каноническому пути, не по входному (TOCTOU через symlink) | gstack (`staging-guard.ts`, инцидент #1802: отравленный checkpoint указал на корень репо → `rm -rf` рабочего дерева) | §7, одна строка + 4 строки в `land.md`/`blast-radius.md` | 5 строк |
| T20 | **Форма ответа на развилку с высокой ценой ошибки:** не меню, а 2–4 направления + компактная таблица трейдоффов (3–6 аспектов под природу развилки) + рекомендация с условием («Б, если спайк X подтвердится, иначе А»). Только когда варианты дают разные последствия **и** цена ошибки высока; иначе — как сейчас: выбрать, записать допущение | own (патч premortem §5 этого документа, перенесённый на наши точки «если скоуп раздваивается») | §0 после «Ask from the frontier», §1 «scope forks»; `decompose` §0 — одна строка-ссылка | 3 строки |
| T21 | **Биндинг «Deploy / Merge policy» в Project bindings** с фиксированными полями: платформа, URL среды, триггер деплоя («CI auto-deploy on merge» \| команда), команда статуса (или HTTP health-check), merge-метод, merge policy (`self \| mr-approval-required`; если CLAUDE.md молчит — `git shortlog -sn --since=90.days` по default-ветке: один автор ≥ 80 % → self, иначе approval). В §0 — дешёвый probe биндинга (status-команда, health URL): нерабочий биндинг обнаруживается до фазы 8 | gstack (`setup-deploy` §Deploy Configuration, `gstack-repo-mode`) | §Project bindings (6–8 строк) + 1 строка §0 | ~8 строк |

| T22 | **DoD как нумерованный чеклист с грейдингом.** §0 рестейтмент — `DoD-1..n` (непроверяемый пункт — вопрос с frontier, не допущение); §8 и ревьюер — матрица `DoD-n → PASS \| FAIL \| PARTIAL` с `file:line`/командой; PASS без ссылки на код запрещён; класс верифицируемости на пункт: `diff` / `live` / `external` — внешнее состояние (DNS, провайдер, чужой репо) = `UNVERIFIABLE` с названной ручной проверкой, а не DONE «потому что код это обрабатывает». Это грейдинг `truths` из decompose при закрытии | own (`qa-check`: PASS/FAIL/PARTIAL с file:line, «PASS без ссылки» — red flag), gstack (`review` §Verification Mode: DIFF-VERIFIABLE / CROSS-REPO / EXTERNAL-STATE, «honesty rule») | §0, §8 + `code-review-prompt.md` §Output («DoD traceability») + `implementation-integrity.md` §6 | ~10 строк |
| T23 | **`references/design-spec-template.md`**, масштабируемый тиром: Problem / Scope + Not in scope / Context pack (что прочитано, `path:line`) / Decisions & assumptions (отброшенные варианты названы) / Reversibility (T2: классификация; T3: rollback, stop condition, окно совместимости) / DoD → check table / Premortem edges (T8) / Failure signal («как узнаем, что сломалось в проде»). Ревьюер видит отсутствие секции, а не додумывает | own (`spec-template.md`, `architecture-governance` §Required architecture spec), gstack (`plan-eng-review` §Failure signal) | новый reference, грузится в §1; T1 — три предложения в тикете, как сейчас | ~50 строк |
| T24 | **Терминальный статус первой строкой** close-комментария и ответа скилла: `DONE \| DONE_WITH_CONCERNS \| BLOCKED \| MERGED_NOT_LIVE \| ABANDONED` + одна строка причины. Контракт для loop-foundry (runner читает первую строку) и для человека | gstack (`ship`/`land-and-deploy` §Completion status) | §8 + `implementation-integrity.md` §6; `decompose` — то же для своего возврата | 4 строки |
| T25 | **Toolchain-пин — предусловие доказательности.** До baseline: резолв проектного пина (`.nvmrc`/`.node-version`/`volta`, `.python-version`, `.tool-versions`, `composer.json platform`) и активация; прогон на другой версии — не evidence, повторить; в evidence-блок — фактические `node --version`/`php -v`. Плюс ловушка «stale `node_modules` выше по дереву»: `require.resolve` обязан указывать внутрь клона | own (`AGENTS.md` §Project Runtime Version; XSUD `AGENTS.md` §Local vs CI) | `implementation-integrity.md` §1 и §6 | ~6 строк |
| T26 | **Мелкие однострочники** (каждый закрывает известный отказ): stage by path, никогда `git add -A` (Fixed discipline); свой `git diff <base>..HEAD` перед диспатчем ревью — leftover стоит раунд (§5); правка вне списка файлов плана §3 = scope-событие, не «заодно» (§5); один фикс Critical/Required — один коммит `fix(review): <id>` (§6); новое значение enum/status → прочитать (не grep) всех потребителей соседних значений вне диффа (§Correctness ревьюера, вместе с T6); ревьюер диспатчится моделью не ниже сессии (dispatch rules); priority тикета ≠ тир (§0); id задачи выводится из ветки/последних коммитов, вопрос — только если не вывелся (§Argument); спека после сохранения проверяется `git ls-files`/`check-ignore` — переживёт ли checkout (§1); legacy-нарушение рядом: чинить, если ≤ одной строки и покрыто тестом, иначе follow-up с ссылкой (ref §1) | own + gstack | по 1 строке в указанных местах | ~10 строк |

Итого по `task`: ≈ 70 строк в SKILL.md (+~22 % веса on-invoke) и ≈ 180 строк в
references (`land.md` ~70, `design-spec-template.md` ~50, `blast-radius.md` ~40).
Дороже всего T2/T7/T18/T22 — они же и самые ценные. Вес SKILL.md — главный
риск батча: всё, что можно, уходит в ленивые references, и `claude plugin
details` меряется до и после.

### 3.2 `decompose`

| # | Идея | Источник | Куда | Размер |
|---|---|---|---|---|
| C1 | **Код читается до первого вопроса.** Перед первым вопросом пользователю — Grep/Read по коду, которого касается вход; первый вопрос цитирует `path:line`; «текущее состояние» — проверенный факт, не пересказ тикета. Память и handoff-заметки — recall, не authority: датированное сверять с живым кодом | gstack (`spec` Phase 3 «read code first»), own (`AGENTS.md` §Разграничение с memory) | §0 | 3 строки |
| C2 | **Секция `## Out of scope` в драфте** — таблица «фрагмент входа / решение \| почему»: и сознательно исключённое, и вырезанное из исходного текста. Артефакт, по которому ревьюер T4 ловит creep, а исполнитель не «дохардивает сверх DoD» | gstack (`spec` Phase 2), own (`xsud-sre-task`: перечислить вырезанное) | `draft-template.md` между Traceability и Risks + §6 | ~8 строк |
| C3 | **`context` заканчивается строкой `Not in this task: <what> — <TASK-ID> owns it`**, когда есть соседняя задача с близким скоупом. Внутрь существующего поля — шестипольный контракт не трогается | own (`xsud-task-decomposition`) | `task-schema.md` (строка `context` + worked example) | 2 строки |
| C4 | **Новые shape/категории в `edge-probe.md`:** `authorization \| actor-facing` (кто может вызвать, что получает не имеющий права — 403/скрыто/read-only); shape `ui`: `surface states` (loading/empty/error/success; i18n и адаптивность — только если проект их декларирует) и `interaction` (двойной сабмит, уход со страницы посреди операции, протухшая сессия, две вкладки); shape `infra`: `grants` (кто × на что × в какой среде), `secrets` (путь/имя по средам), `environments` (порядок и кто создаёт) | own (`xsud-req-review` §Полнота, `xsud-sre-task`), gstack (`ship` test-coverage §UI interactions) | `edge-probe.md` | ~10 строк таблицы |
| C5 | **Check 2 → «Field completeness and quality».** WARNING за глагол-цель без артефакта (`ensure/support/handle/properly/correctly/improve`), субъективное прилагательное без метрики, «и т.д.» в перечислении; каждое существительное в `context`/`dod` локализуемо (path / symbol / endpoint). Счётчик «8 checks» не меняется | own (`xsud-req-review` §Тестируемость), gstack (`spec` 4.5 «executability by an unfamiliar implementer») | `qa-checklist.md` Check 2 | ~12 строк |
| C6 | **Плейсхолдер вместо придуманного идентификатора.** Путь, таблица, env-var, хост, команда, не найденные в репо/доках, пишутся как `<placeholder>` и попадают в «Заполнить перед отправкой»; QA-субагент проверяет разрешимость `@`-ссылок (`test -e`, grep символа). Тот же механизм, что «manufactured risk» из 1.6.0, только для идентификаторов | own (`xsud-sre-task` §Что запрещено) | `task-schema.md` + `qa-checklist.md` Check 2 | 3 + 4 строки |
| C7 | **Check 5: контракт producer → consumer.** Артефакт, как он назван в `dod.done` родителя, совпадает с тем, что ожидает `context` потомка (имя, форма, поля) | own (`xsud-req-review` §Непротиворечивость) | `qa-checklist.md` Check 5 | 3 строки |
| C8 | **Convergence guard в revision loop:** один и тот же набор BLOCKER (task + check + description) два check-run подряд → правка не работает или ревьюер не согласен; досрочная эскалация к пользователю, не третий раунд. Уточнение, не ослабление: PASS по-прежнему только с чистого прогона | gstack (`plan-ceo-review` §Convergence guard); правило владельца «два одинаковых фейла → стоп» | `qa-checklist.md` §Revision loop | 3 строки |
| C9 | **Read-back после записи в трекер.** Третья операция адаптера `read_issue(<TASK-ID>)`; §9 шаг после всех create/link: перечитать каждую созданную сущность и сверить summary/description/links/estimate; расхождение — в отчёт как partial failure. Возвращённое `ok` — заявление записывающей стороны (аксиома 5) | own (`xsud-jira-task` §Flow п.5, `AGENTS.md` §MCP only: «после мутации подтверждать повторным чтением»), `verification.md` (read-after-write для one-way) | `tracker-sync.md` §1, §9 | ~15 строк |
| C10 | **Preflight до dry-run:** одно чтение проекта/эпика (доказывает токен и проект) + типы issue, поля, типы связей, шкала estimate. Dry-run перестаёт обещать ступень estimate и тип связи, которых в проекте нет | own (`youtrack-task`, `xsud-jira-task`) | `tracker-sync.md` §9 шаг 2b | ~6 строк |
| C11 | **Адаптер объявляет разметку description:** `markup: markdown \| jira-wiki \| adf-via-markdown \| plain` (default markdown). Jira Server/DC принимает wiki-markup; Markdown даёт нечитаемый тикет | own (`xsud-bug-task`, `jira-diagnosis-report` §Писать в Markdown / wiki ломается) | `tracker-sync.md` §1, §7 | 3 строки |
| C12 | **REST-транспорт как опция биндинга.** Нет MCP, но `CLAUDE.md` проекта называет REST-эндпоинт и **имя** env-переменной токена → использовать как транспорт адаптера (YouTrack: `/api/commands` для связей и estimate одним вызовом — иллюстрация). Значение токена агент не видит | own (`youtrack-task`: REST primary) | `tracker-sync.md` §3 | ~5 строк |
| C13 | **Поиск дубликатов перед созданием:** опциональная `search_issues(query)`; в dry-run блок «possible duplicates» (≤3 на задачу, только открытые); любая ошибка поиска — печатается, не блокирует | gstack (`spec` --dedupe) | `tracker-sync.md` §1, §5 | ~6 строк |
| C14 | **Ссылка на драфт в description** (`Source: docs/decompose/…, epic <ID>`) и URL созданных issue в отчёте, не только id | own (`youtrack-task`) | `tracker-sync.md` §7 | 2 строки |

### 3.3 `ci-gate`

| # | Идея | Источник | Куда | Размер |
|---|---|---|---|---|
| G1 | Починить D2: `ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:<manifest-digest>` в трёх CI-файлах (та же версия, что `PIN_VERSION`; digest снять один раз `docker buildx imagetools inspect`); actions — по SHA. Бамп — вместе с `PIN_VERSION`, SHA256 и `rev` | own (`gstack-upgrade` переписанный: «only from a reviewed, version-pinned package with a published digest») | payload + README + 1 строка SKILL.md | 3 строки YAML |
| G2 | Починить D3: кэшировать тарбол, на каждом вызове сверять SHA256 с `WANT`; mismatch → удалить кэш, перекачать или fail closed | own (`gstack-upgrade` §Flow п.3/6) | `gitleaks-fetch.sh` | ~10 строк |
| G3 | Починить D4: `rev: <commit-sha>  # v8.30.1`, убрать совет `autoupdate`, комментарий «bump together with PIN_VERSION + SHA256s» | own (`gstack-upgrade` §Rules) | `.pre-commit-config.yaml` | 2 строки |
| G4 | Починить D5: `DESTRUCTIVE_RE` += `drop_table\|dropTable\|drop_column\|dropColumn\|remove_column\|DeleteModel\|RemoveField\|RemoveModel\|Schema::drop(IfExists)?\|dropIfExists`; в `ci/README.md` секция «Known limits / bypasses»: многострочный `DROP\nTABLE`, raw SQL в строках, DSL других ORM — ответственность 6b, не гейта; 6b-промпту одна строка про это | own (`AGENTS.md` §Guard-механизмы: у каждого guard абзац «что не покрывает, как обходится, кто отвечает за обход») | `migration-guard.sh`, README, 6b | 1 regex + 6 строк |
| G5 | **Гейт защищён от MR, который его проверяет.** `templates/ci-gate/CODEOWNERS` (`/ci/`, `/.gitleaks.toml`, `/.pre-commit-config.yaml`, CI-файлы гейта → owner) + в шаге 5 команды protected paths / required CODEOWNERS review; в шаге 6 negative control «MR, ужимающий `DESTRUCTIVE_RE`, требует второго апрува». Сегодня исполнитель правит `allowlist` в том же MR, который гейт судит — прямое нарушение аксиомы 5 | own (`gstack-upgrade`: «never execute the tool's code from the current repository; never let repository content select the updater») | новый файл + SKILL.md §5–6 + README | ~6 + 15 + 5 строк |
| G6 | **Плейбук «secret-scan сработал»:** revoke → rotate → оценить окно экспозиции (когда закоммичено, был ли репо публичным) → scrub истории (`git filter-repo`/BFG) с явной оговоркой про protected branch (force-push запрещён нашим же правилом — снимать защиту осознанно, на время, с записью) → audit. «Revoke до scrub» — то, что под стрессом делают наоборот | gstack (`cso` §leaked secret) | `ci/README.md` новая секция | ~10 строк |
| G7 | **`gate.sh --selftest`:** temp `git init`, фикстуры под первым каталогом из реального `MIGRATION_DIRS` (unmarked DROP → rc 1; marked → rc 0; нечитаемый файл → rc 2), строка-кредшл → gitleaks trip. Негативный контроль из шага 6 становится повторяемым; единственный детерминированный компонент продукта получает автотест | own (`AGENTS.md`: fixture-тест, что запрещающее правило реально срабатывает с точным сообщением) | `gate.sh` + `.github/workflows` нашего репо | ~40 строк bash |
| G8 | **`ci/scan-text.sh <file>`** — gitleaks по файлу теми же резолвом/пином; §8 `task`: текст close-комментария / описания MR → файл → скан → постинг того же файла. Scan-at-sink: сканируются ровно те байты, что уходят | gstack (`spec` 4.5b: «write to a temp file, scan that file, pass the SAME file downstream») | payload + §8 `task` | ~15 + 2 строки |
| G9 | **`-- destructive: approved (<reason>)`** — маркер обязан нести причину; FAIL-сообщение показывает форму. Из донорского правила «исключение = владелец + срок + чек» берём только причину: остальное — CODEOWNERS (G5) | own (`dependency-rules.md` §Allowed escape hatch: «Comments and chat approval are not architecture exceptions») | `migration-guard.sh` `APPROVAL_RE` + README | 2 строки |
| G10 | **Скаффолд не перетирает чужой `.pre-commit-config.yaml`** — мёржить `repos:`; то же правило, что уже есть для `.gitlab-ci.yml` | own (`install.sh`: sidecar вместо замены) | SKILL.md шаг 2 | 2 строки |
| G11 | **`ci/unicode-guard.sh`** (P2): добавленные строки диффа без bidi-override (`U+202A–202E`, `U+2066–2069`), zero-width (`U+200B–200D`, `U+2060`, `U+FEFF`) и Unicode tag block (`U+E0000–E007F`); без ZWJ/ZWNJ/LRM/RLM/SHY — иначе emoji и арабские цитаты владельца дадут ложные срабатывания. Trojan-source в диффе — класс, который ни тесты, ни ревью не видят | gsd (`gsd-read-injection-scanner.js`, только набор кодовых точек; advisory-на-Read не берём) | payload + CI-файлы (commented job) | ~30 строк |
| G12 | Починить D7: `regexTarget = "match"` + комментарий «a placeholder on the same line must not excuse a real secret» | gstack (`redact-engine`: «suppressed only if the MATCHED SPAN itself is a placeholder») | `.gitleaks.toml` | 1 слово |
| G13 | **Pre-push-слой** (P2): `ci/pre-push.sh` читает refs со stdin, сканирует **добавленные** строки per ref; диапазон: новая ветка → `merge-base` с default-веткой, нет merge-base → empty-tree (сканировать больше, никогда меньше); remote-sha отсутствует локально → тот же fallback; **упавший `git diff` = BLOCK** (fail-closed там, где лежит большой секретоносный blob); обход только через env с записью причины в журнал. Ловит `commit --no-verify`, amend, историю с другой машины — до того, как секрет стал скомпрометированным | gstack (`gstack-redact-prepush`, #1946) | payload + `.pre-commit-config.yaml` (`stages: [pre-push]`) + README | ~40 строк bash |

### 3.4 Конвенции репозитория task-flow (не плагин, не payload)

| # | Идея | Источник | Куда |
|---|---|---|---|
| R1 | **`scripts/lint.sh` — grep-инварианты как Tier-1 линт** (<2 с, без LLM): reference-link loop для обоих скиллов; `~/.claude` в `skills/` только в «never»-контексте; `\|\| true` и `2>/dev/null` в `templates/ci-gate/ci/*.sh` только в allowlist-строках; фаза 8 `task` содержит «deterministic gate»; 6 имён полей + 4 члена `dod` совпадают в пяти файлах; `bash -n`; `jq -e`. Fail-open в migration-guard нашли руками именно потому, что такого линта не было | gstack (`CLAUDE.md`: static tripwire tests), own (`verify.sh`: grep-assert'ы load-bearing фраз AGENTS.md) |
| R2 | **`scripts/release-check.sh`:** версия `plugin.json` == первая `## [` в CHANGELOG; заголовки монотонно убывают; тег `v<версия>` ещё не существует; `git diff <prev-tag>..HEAD -- skills templates` непуст; `git grep '/home/[a-z]'` по tracked-файлам пуст (сейчас утечки есть: `docs/superpowers/plans/2026-07-18-decompose-skill-plan.md:27`, в `devpowers/CLAUDE.md:22` и двух docs research-pipeline — личный путь, не секрет, но в публичном репо лишнее). Закрывает «бамп сделан, CHANGELOG/тег забыты» | gstack (`ship` Step 12 classify), без его state-machine; own (`verify.sh`: скан на персональные абсолютные пути) |
| R3 | **Dogfood: `.github/workflows/check.yml`** — собственный `templates/ci-gate/github/gate.yml` (secret-scan по диффу PR) + job `lint.sh` + `gate.sh --selftest`. Продукт, который шипит gitleaks-гейт, сам под ним не стоит | own (`verify.sh`: пакет сканируется перед передачей) |
| R4 | **CHANGELOG правится только Edit с точным `old_string`, никогда Write поверх файла**; перед релизом проверить, что бамп покрывает весь дифф с прошлого тега (вторая фича, приехавшая после бампа) | gstack (`document-release`: задокументированный инцидент перезаписи CHANGELOG агентом) → `devpowers/CLAUDE.md` §Релизы, п. 2 + `task-flow/CLAUDE.md` |
| R5 | **Датированный документ в `docs/` — point-in-time**, обязан ссылаться на актуальный контракт, который затрагивает; шапка `status/owner/last_verified` для контрактных документов (у нас — `CLAUDE.md` и references) — опционально | own (`docs/architecture/README.md` §Required metadata) |
| R6 | **`actionlint` для `templates/ci-gate/github/gate.yml`, `yamllint` для GitLab-вариантов** — в «Commands» и в self-CI (R3); shellcheck внутри `run:` бесплатно ловит инъекционные паттерны. Гигиена там же: значения `${{ … }}` в `run:` передавать через `env:` и `"$VAR"` (в нашем шаблоне сейчас только repo-controlled поля — `base_ref`, `sha`, `event.before`, — инъекции нет, но шаблон учит паттерну) | gstack (`.github/workflows/actionlint.yml`, `pr-title-sync.yml` — дисциплина `pull_request_target`) |
| R7 | **`scripts/readme-parity.sh`:** сравнение структуры `README.md` ↔ `README.ru.md` (заголовки, блоки кода, таблицы, бейджи — не текст); расхождение = fail с подсказкой. Конвенция lockstep сейчас держится на памяти | gstack (freshness-tripwire `git diff --exit-code` после регенерации) |

### 3.5 Линейка devpowers

| # | Идея | Источник | Куда |
|---|---|---|---|
| L1 | **Self-check поставляемых скиллов/хуков перед релизом любого плагина:** `git diff <prev-tag>..HEAD -- skills/ hooks/ templates/ commands/ agents/` + grep на сеть (`curl\|wget\|fetch\|http`), креды (`_API_KEY\|process.env\|~/.ssh`), `rm -rf`, `eval`, base64 — каждое попадание названо в changelog. Линейка сама есть skill supply chain; 6b требует capability diff от чужого кода — логично требовать от своих поставок | gstack (`cso` Phase 8 Skill Supply Chain) → `devpowers/CLAUDE.md` §Релизы, п. 0 |
| L2 | **Сниппет `## Skill routing` для CLAUDE.md потребляющего проекта** в README обоих языков: «тикет → `/task`, эпик → `/decompose`, гейт → `/ci-gate`, при сомнении — вызывай скилл». Дыра не в дисциплине, а в адопции: `description` конкурирует с десятками чужих | gstack (first-run routing table) |

### 3.6 Глобальный `~/.claude/CLAUDE.md` владельца (вне плагинов)

| # | Идея | Источник |
|---|---|---|
| U1 | **Гигиена памяти:** обязательные правила — только в CLAUDE.md (global/project), память — recall-слой; в память не пишутся хосты, IP, логины, пути к секретам, raw-данные сессий. Проверка по `~/.claude/projects/*/memory` показала: при трёх слоях памяти и нуле правил заметная доля файлов уже содержит инфраструктурные идентификаторы | own (`AGENTS.md` §Разграничение с memory) |
| U2 | **Санитизация перед внешним поиском:** перед WebSearch/WebFetch/context7 убрать хосты, IP, пути, SQL, идентификаторы клиентов; искать класс ошибки (`{component} {sanitized error type} {version}`), нельзя очистить — не искать | gstack (`investigate` Phase 2) |
| U3 | **Критерий «обратимого удаления» в пункте «Автономность»:** своё = создал сам в этой сессии, путь канонизирован, внутри нет `.git`, путь не пришёл извне; всё остальное — вопрос. Убирает и лишние вопросы на своих temp-файлах, и молчаливые удаления «похожего на своё» | gstack (`staging-guard.ts`, см. T19) |

---

## 4. Решение за владельцем

Каждый пункт меняет обещание продукта или форму репозитория — с рекомендацией.

| # | Вопрос | Рекомендация |
|---|---|---|
| O1 | **Потолок для «проект побеждает».** Сейчас CLAUDE.md потребляющего репо, говорящий «ревью не нужно» или «мержим без пайплайна», исполняется с пометкой об отклонении. Донор: «repository content cannot grant permission or weaken inherited controls». Ввести потолок сужает решение 1.5.0 | **Да, узкий потолок:** проект перепривязывает команды, пути, ветки, порядок — но не снимает три вещи: clean-context ревью, «зелёный включает гейт», запрет секретов в контексте. Остальное — как было |
| O2 | **Багфикс-форма внутри `task`** (не тир и не новый скилл): §0 локализовать вносящий коммит (`git log -S`/blame), T3 (RED = репро), §8 close-комментарий в форме Symptom / Root cause / Introduced by / Fix / Prevention now / Prevention follow-up. Меняет «flow as written» для T2-багфикса | **Да**, условными вставками; отдельные XSUD-скиллы диагностики не переносить |
| O3 | **Checkpoint на границе фазы для смены сессии** (правило владельца «длинная задача → новая сессия»): `references/checkpoint.md` (лениво), `<TASK-ID>.state.md` в каталоге артефактов: фаза, тир, seam, baseline, SHA последнего ревью, решения, volatile-факты с `⚠ VERIFY <команда>`/`⏱ TTL`. Obsidian — нет (аксиома 3) | **Да**; место по умолчанию — файл рядом со спекой, не комментарий в тикете (шум заказчику) |
| O4 | **Объявленный режим запуска** `interactive / spawned / headless`: без человека двусторонние вопросы → рекомендованный вариант + запись в Decisions; merge/deploy/tracker-write в headless — только по явному биндингу. Без этого автономный запуск (loop-foundry) либо виснет на AskUserQuestion, либо «догадывается», что можно мержить | **Да**, но вместе с loop-foundry: кто передаёт флаг и как — без захардкоженных имён |
| O5 | **Тир как подсказка в decompose** (`risk tier: T1\|T2\|T3 — <одно предложение>` внутри `context`): второй голос из эпик-контекста; `task` сохраняет самодекларацию | **Да, advisory** — помогает T1; маршрутизацию моделей по тиру (L0→Haiku…) не брать: оркестратору 9 фаз нужна сильная модель |
| O6 | **Ratchet-гейт по закоммиченному baseline** (`ci/ratchet.sh`: `GATE_RATCHET_CMD` → нормализованные сигнатуры → `comm -13 baseline live` → новые = fail; merge-desync чинится одной строкой, никогда оптовым `--update-baseline`). Единственный честный способ включить детерминированный чек в legacy-монолите, но расширяет тезис ci-gate с «floor под тремя категориями» до harness | **Скорее да**, как четвёртый опциональный слой по образцу diff-coverage («судит отчёт, не производит»); description скилла обновить |
| O7 | **Плагин `guardrails` в линейке** — PreToolUse-хук на Bash: деструктивные паттерны (`rm -rf`, `DROP`, `TRUNCATE`, `push --force`, `reset --hard`, `kubectl delete`, `terraform destroy`, revoke/rotate креды) → `permissionDecision: ask`. Переводит правило владельца «спрашивай только при необратимом» из прозы в механизм, не зависящий от модели | **Да — но не отдельно, а как второй слой `prediction-protocol`** (см. §7): тот же хук, тот же список паттернов (`one-way-doors.ts` донора даёт готовый) |
| O8 | **Deny-хук Edit/Write вне объявленной области** (структурный read-only ревьюера). Действует на всю сессию, оставляет stale-маркер при падении субагента, меняет «no runtime code» | **Нет сейчас**; пересмотреть вместе с O7, если хук-плагин появится |
| O9 | **Кросс-модельное второе мнение в §6** (Codex read-only по тому же диффу; совпадение = high confidence). Единственный способ снизить корреляцию LLM-слоя по модели; требует второго CLI | **Условный мост** по образцу premortem: есть в CLAUDE.md проекта — используем, нет — `cross-model: n/a` в evidence-блоке |
| O10 | **Скилл `accept <TASK-ID> [range]`** — приёмка чужого MR по DoD без полного флоу (PASS/FAIL/PARTIAL на каждый пункт с `file:line`; PASS без ссылки на код запрещён). ~250 токенов always-on | **Да, если** владелец регулярно принимает чужие MR; иначе — режим `task` «только фаза 0 + 6» |
| O11 | **`context-map.yaml`** (изменённые пути → минимальный набор документов) + валидатор | **Нет как формат**; взять минимум: опциональный биндинг «Architecture docs — где ADR/карта; читать только относящееся к изменённым путям» в §Project bindings |

---

## 5. Premortem: патч Дмитрия к vendored-скиллу

`src.v3/skills/premortem/SKILL.md` отличается от апстрима одним местом — шаг 2
«Варианты решения»: 2–4 направления (было 2–3), **обязательная таблица
трейдоффов** (6–10 аспектов под природу дыры: root cause vs симптом, объём,
зависимости, UX, тестируемость, maintenance, совместимость, каскады, cognitive
load, bundle) и **рекомендация скилла с одной фразой обоснования**, показанные
сразу, без просьбы «давай трейдоффы». Совпадает с правилом владельца
«рекомендация одной строкой вместо меню».

Наш форк `umar-s/premortem` держит апстримные файлы нетронутыми ради
бесконфликтных мержей. Решение: **(b) предложить патч в апстрим
(`AndyShaman/premortem`) как PR**; до принятия — **(a) один отдельный коммит в
форке** поверх `plugin.json`-коммита (два патч-коммита ребейзятся так же легко,
как один). Вариант (c) — перенести дисциплину в `task` §2 — не брать: там
премортем inline и без вариантов решения, таблица раздует фазу.

---

## 6. Не брать

- **Сторонние пакеты целиком** (gstack, impeccable, GitNexus, graphify): чужая
  модель доверия (всё у проверяемой стороны), 40+ КБ преамбулы на скилл, bun/
  Node-рантайм. Брались только механизмы.
- **«Любой красный тест — твоя задача, независимо от того, кто внёс баг»**
  (`AGENTS.md` §Completion checklist): ломает baseline
  `implementation-integrity.md` §1 («ноль НОВЫХ падений», чужие падения —
  записать и вынести), решено в аудите old-coder. Берётся только трёхчастное
  правило для соседней грязи (T26).
- **Числовой confidence 1–10 у находок** (gstack): ложная точность; бинарный
  критерий (цитата строки, PoC) сильнее — T5.
- **Fix-first ревьюер** (gstack: авто-правка механических находок ревьюером) и
  **red team, брифованный найденным** — ломают clean-context (аксиома 2);
  «второй независимый» у нас — 6b, и совпадение двух линз — сигнал, а не
  дубликат.
- **AI-assessed coverage с генерацией тестов** (gstack `ship` Step 7):
  gameable, fail-open («undetermined → skip»); у нас `diff-coverage.sh` +
  мутанты.
- **GSD-хуки** (`gsd-*`): завязаны на `.planning/`, advisory, `exit 0` на любой
  ошибке. Из `read-injection-scanner` взят только набор Unicode-точек (G11).
- **`thermo-nuclear-code-quality-review`** (текст OpenAI): числовой порог «файл
  перевалил за 1000 строк = презумптивный блокер» — конвенция одного репо;
  противоречит «не ужесточать сверх DoD без названного требования». Структурные
  remedies у нас уже есть в `code-review-prompt.md`.
- **Маршрутизация моделей по L0–L3 и строка «Рекомендация: модель · effort»**:
  оркестратору 9 фаз нужна сильная модель; экономия возможна только на
  субагентах — а это уже есть (`model:` в диспатче).
- **Obsidian/ADR/handoff как интеграция** (`OBSIDIAN_VAULT`, `dev/decisions/`):
  аксиома 3. Берётся только форма (O3 checkpoint, volatile-факты с командой
  проверки).
- **Conventional-Commits-хук, `npm run final`-скиллы, `xsud-docker-worktree`,
  `xsud-extract-dev-data`, `allure-regression-analysis`, `api-endpoint-factory`,
  `js-data-structures`**: проектные биндинги; форма «final checks» уже покрыта
  §5/§8 и `implementation-integrity.md` §5–6.
- **MCP-only для внешних сервисов** (запрет REST/curl): у нас обратное решение
  (C12) — транспорт из биндинга, значение токена агенту не виден.
- **Слепая верификация находок свежими сабагентами, диспатчнутыми
  исполнителем** (gstack): организованный ребаттал собственных находок; T5
  (цитата строки) убивает тот же класс FP без конфликта с аксиомой 5.
- **Hermetic acceptance через `claude -p` с чистым `CLAUDE_CONFIG_DIR`**: чинит
  то же, что R1/R3 + правило «acceptance только через installed plugin», но
  требует инфраструктуры (у gstack — bun-тесты + Docker); репо объявлен без
  рантайма. Вернуться, если R1 окажется недостаточно.
- **Все скиллы уровня «документ для человека»** (incident report 9 секций,
  diagnosis report, bug-task в wiki-markup): формы сильные, но это отдельный
  жанр; взяты только правила (O2 close-форма, C11 разметка).
- **Эвристика «сигнатура падения не найдена в диффе → причина на стенде»**
  (`allure-regression-analysis`): ложный вывод во второй половине.
- **Design-suite как плагин линейки**: дыра есть (в devpowers нет
  design-quality), но impeccable — 20 скиллов чужого формата; если нужно —
  отдельный аудит.

---

## 7. Связь с `prediction-protocol` (второе задание)

Четыре находки этого аудита — готовые блоки дизайна протокола прогнозов:

- **T2 Reversibility / verification matrix** (`требование → evidence → команда →
  rollback signal`) — это hypothesis / predicted observable / falsifier для
  архитектурных решений; one-way door = класс действий, где прогноз обязателен.
- **T5 «цитата или unverified»** и **T9 `review @ sha`** — та же дисциплина
  «claim → evidence», что у протокола, только для ревью.
- **O7 хук на деструктивные команды** — второй слой протокола (deny без
  receipt); список паттернов `gstack/scripts/one-way-doors.ts` переносится в
  оба.
- **O3 checkpoint с `⚠ VERIFY <команда>` / `⏱ TTL`** — секция
  Verified / Assumed / Refuted из NOTES.md ARC, один к одному.
- **T18 `land.md`** — фаза 8 становится последовательностью state-changing
  шагов с именованными наблюдаемыми (`state == MERGED`, `headSha == merge SHA`,
  health-check 200) — естественные claim/falsifier для протокола; «второй merge
  не вызывается никогда» — halt-at-first-miss в чистом виде.
- **Чеклист hook-инженерии** (gstack spike + TODO #1882): matcher с
  метасимволами — JS-regex, MCP-варианты инструмента (`mcp__.*__<Tool>`) должны
  покрываться явно; хук не должен зависеть от cwd и захардкоженного префикса
  установки (`${CLAUDE_PLUGIN_ROOT}`); решение хука тестируется синтетическим
  stdin; `PostToolUse` не блокирует — грейдинг только в обёртке. Кладётся в
  design-spec протокола до первого `hooks.json` в линейке.

Поэтому оба задания идут одним design-spec и одним премортемом: правки §0/§1/§3/
§7/§8 `task` делаются один раз.

---

## 8. Что сделал бы первым

Один релиз на одну поверхность — так changelog и ревью остаются читаемыми, а
вес промпта `task` меряется отдельно от остального.

1. **1.7.1 — дефекты D1–D7** (T17, G1–G4, G12, T16) + чистка личных путей в
   `docs/`: без новых идей, только починка своего. Параллельно без бампа —
   `scripts/lint.sh`, `release-check.sh`, `readme-parity.sh`,
   `.github/workflows/check.yml` (R1–R3, R6–R7): они защищают все следующие
   шаги.
2. **1.8.0 — `ci-gate` hardening:** G5–G11, G13; каждый пункт — с негативным
   контролем до коммита; в CHANGELOG «Changed» для G4/G9 (MR в полёте с голым
   маркером начнут падать).
3. **1.9.0 — `task`:** T1–T16, T18–T26, O1 (узкий потолок), O2 (багфикс-форма),
   O3 (checkpoint), O5 (тир-подсказка — приёмная сторона) + три новых
   reference. `claude plugin details` до и после; README×2 в lockstep.
4. **1.10.0 — `decompose` + tracker-sync:** C1–C14, O5 (авторская сторона);
   счётчик «8 checks» и контракт 6 полей не меняются — закрепить инвариантом в
   `lint.sh`.
5. **Линейка:** R4/L1 в `devpowers/CLAUDE.md`; L2 в README плагинов; PR в
   апстрим premortem + патч-коммит в форке (`plugin-v1.0.1`); U1–U3 — три
   правки руками владельца в `~/.claude/CLAUDE.md`.
6. **Design-spec `prediction-protocol`** с O4/O7 (и чеклистом хук-инженерии)
   внутри → премортем → отдельный плагин + routing-абзацы в `task` (1.11.0) и
   `loop-foundry`.
