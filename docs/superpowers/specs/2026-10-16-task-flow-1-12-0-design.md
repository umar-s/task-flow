# Дизайн: task-flow — два харнесса и перекрёстное ревью (1.12.0)

**Дата:** 2026-10-16
**Автор:** Sergei (umar-s) + Claude
**Статус:** спека → реализация → приёмка
**Источник:** devpowers `docs/claude-codex-stack.md` §2, §4.2, §6, §7.4–7.5
(этап S2); prediction-protocol 1.1.0 (S1) уже выпущен — гейт на Codex
отвечает deny там, где на Claude спрашивал.
**Версия:** 1.11.0 → 1.12.0 (minor: новый payload `xreview`, новые шаблоны,
новое предпочтение диспатча в фазах 6/6b; контракт фаз не меняется).

---

## 1. Что чинит этот релиз

task-flow уже грузится в Codex CLI (скиллы видны как `task-flow:task`,
`$ROOT` резолвится по пути SKILL.md), но три вещи там не работают или
работают не так:

1. **Термины Claude Code.** «Agent tool», `/task`, «read the project's
   `CLAUDE.md`» — на Codex это другие вещи (`spawn a subagent`,
   `$task-flow:task`, `AGENTS.md`). `ci-gate` вообще читает payload по
   `${CLAUDE_PLUGIN_ROOT}` без fallback: в шелле модели Codex переменная не
   задана, и путь превращается в `/templates/ci-gate/`.
2. **Независимость ревью — только «другой контекст той же модели».** Вторая
   подписка даёт более сильную форму: ревьюер другого вендора, другие слепые
   пятна. Сегодня это руками (§7.4 стека), без контракта на вердикт.
3. **Второй security-pass в CI отсутствует.** Codex Security по MR-диффу —
   официальный шаблон GitLab существует, но в виде, который на чистом образе
   не стартует (см. §2.6).

Не меняется: фазы и их порядок, clean-context dispatch, «green includes the
deterministic gate», блокирующая сила Critical/Required, правило «модель
не слабее сессии», slot-контракт шаблонов ревью.

## 2. Решения

### 2.1 Раздел Harness в каждом SKILL.md (≤ 16 строк)

Цель стека была 12 строк; деталь Codex-гейта (deny вместо ask, `PREDICT`)
в `task` её не уместила — lint держит кап 16, чтобы раздел не разросся в
reference.

Имя вызова (`/task-flow:<skill>` ↔ `$task-flow:<skill>`), файл инструкций
проекта, `$ROOT`, что значит «fresh subagent» в каждом харнессе, и что
предпочтительный независимый ревьюер — другая модель. Для `task` — плюс
поведение гейта prediction-protocol на Codex (deny вместо ask, `PREDICT`
из SessionStart-контекста).

### 2.2 «Instruction file» вместо «CLAUDE.md»

Bindings читаются из `AGENTS.md` (Codex читает только его; рекомендуемый
единственный источник) или `CLAUDE.md` (который импортирует `@AGENTS.md`).
Термин определяется один раз в разделе Harness и используется дальше.

### 2.3 `ci-gate`: `$ROOT` как у остальных скиллов

Тот же bash-блок `ROOT="${CLAUDE_PLUGIN_ROOT:-…}"`, payload читается по
`$ROOT/templates/ci-gate/`. Новый шаг 7 «second security pass (optional)» —
**помечен как LLM-слой**: Codex Security — модель, а не детерминированная
проверка; он не входит в «green includes the gate» фазы 8 и не заменяет
6b — это третий независимый взгляд на те же trust boundaries.

### 2.4 `templates/xreview/xreview.sh` — ревью другой моделью

- Запускается **на месте из плагина** (`bash "$ROOT/templates/xreview/xreview.sh"`):
  шаблоны брифа берёт рядом, из `skills/task/references/` той же версии —
  копия в репозитории устарела бы с первым релизом.
- `--by codex|claude` (кто ревьюит), `--task`, `--base <ref>`, `--kind
  code|security`, `--spec` (дефолт `docs/specs/<TASK>.spec.md`),
  `--what-changed FILE`, `--model`, `--out-dir` (дефолт `docs/reviews`).
- Слоты из артефактов: `[DOD]` — секция `DoD → check table` спеки,
  `[PREMORTEM_EDGES]` — секция `Premortem edges` (для `security` — не
  передаётся вовсе), `[DESIGN_SPEC]` — спека без секции Premortem edges,
  `[BASE_SHA]`/`[HEAD_SHA]` — `git merge-base`/`rev-parse`,
  `[WHAT_CHANGED]` — файл автора или темы коммитов диапазона.
  Подстановка буквальная (awk `index`/`substr`), содержимое спеки никогда
  не исполняется.
- **Read-only:** Codex — `codex exec -s read-only --ignore-rules` (`allow`
  из `.rules` выпускает команду из песочницы — проверено); Claude —
  `claude -p --tools Read,Grep,Glob --permission-mode dontAsk
  --strict-mcp-config --disable-slash-commands`: **без shell** (разрешённый
  `git diff --output=<file>` пишет в checkout, git принимает сокращения
  длинных опций — allowlist не закрывается), без MCP (`--tools` ограничивает
  только встроенные), без skills; материалы диапазона (stat, log, status,
  дифф; для 6b — без диффа самой спеки) прикладываются к брифу, checkout
  обязан стоять на ревьюируемом head. `XREVIEW_ALLOW` даёт shell ровно под
  перечисленные правила.
- **Никаких файлов настроек из репозитория у Claude-ревьюера:**
  `--setting-sources ""` + `disableAllHooks` — закоммиченный в диффе
  `.claude/settings.json` или `settings.local.json` исполняет хуки и
  `apiKeyHelper` при старте сессии (оба проверены на lab-репозитории
  2026-10-16); OAuth при этом работает. У Codex проектный слой под
  `--ignore-user-config` не грузится (хук из `.codex/hooks.json` не
  исполнился).
- **Изоляция от памяти автора (по умолчанию).** Измерено 2026-10-16:
  `claude -p` по умолчанию запускает 9 SessionStart-хуков пользовательских
  плагинов (claude-mem подмешивает историю проекта, т.е. рассказ автора),
  без пользовательских настроек — 0; `codex exec` по умолчанию — 4
  SessionStart-хука, `--ignore-user-config` — 0. Ревьюер, которому
  плагин памяти пересказал реализацию, — ровно тот брифинг автором, который
  запрещает dispatch-правило. `XREVIEW_ISOLATE=0` — осознанный опт-аут:
  возвращает пользовательские настройки и плагины, но не MCP, не `.rules` и
  не файлы настроек из репозитория.
- **Env без чужой сессии:** снимаются **семейства** `CLAUDE_CODE_*`,
  `CLAUDE_PLUGIN_*`, `PP_*`, `CODEX_SANDBOX*` и имена `CLAUDECODE`,
  `CLAUDE_ENV_FILE`, `CODEX_SESSION_ID`, `CODEX_THREAD_ID`, `PREDICT`, …;
  остаются переменные авторизации ревьюера (`CLAUDE_CODE_OAUTH_TOKEN`,
  `CLAUDE_CODE_USE_*`, …) и `XREVIEW_KEEP_ENV` — ревьюер не наследует
  идентичность сессии автора и её канал сообщений (факт 16 стека).
- **Вердикт → exit:** `code` — `Ready to merge?` `Yes` → 0, `No`/`With fixes`
  → 1; `security` — `Critical: N | High: N | Medium: N | Low: N`, Critical +
  High > 0 → 1. Поле — строка, начинающаяся с метки, в своей секции
  (`### Assessment`, у 6b счётчики — `### Summary`), в тексте, который видит
  читатель отрендеренного отчёта (не fence, не комментарий, не отступ),
  значение целиком. Не распознан вердикт, два разных значения, `Reviewed:` ≠
  HEAD, пустой диапазон, нет спеки/секции DoD, CLI не найден, ревьюер упал
  → **2** (fail closed: непрочитанный вердикт — не чистое ревью).
- Отчёт `docs/reviews/<TASK>-<sha7>-<by>[-security].md`: шапка от скрипта
  (ревьюер, модель, base/head, sha256 брифа, exit) + ответ модели.
- Коммит отчёта двигает HEAD: правило — коммит, меняющий только
  `docs/reviews/` и `docs/evidence/`, вердикт не обнуляет; проверка —
  `git diff --quiet <reviewed>..HEAD -- . ':!docs/reviews' ':!docs/evidence'`.

### 2.5 `references/cross-review.md`

Когда и в какую сторону (ревьюер — харнесс, который не писал дифф), команды
скрипта и ручные эквиваленты в обе стороны, штатный `codex exec review
--base` как дополнительное мнение (применяет `## Code Review Rules` из
`AGENTS.md`, DoD не грейдит), расхождения двух ревью (независимое
совпадение — приоритет; расхождение во вердикте — человеку или третий
прогон с явным вопросом, никогда не «усреднение»), строка evidence block.

### 2.6 `templates/ci-gate/gitlab/codex-security*.gitlab-ci.yml`

Основа — официальный минимальный scan-only шаблон (learn.chatgpt.com →
Codex Security → CI → GitLab). Отличия, каждое по причине:

| Официальный минимум | Здесь | Почему |
|---|---|---|
| `image: node:26-bookworm-slim` (тег) | тот же образ **по digest** | тег переуказуем; правило ci-gate «digest, never a tag» |
| в образе нет `git`, `python3` | `apt-get install git python3` | проверено 2026-10-16: `git merge-base` и экспорт (Python 3.10+) иначе падают |
| без `--fail-on-severity` | `--fail-on-severity ${CODEX_SECURITY_FAIL_ON:-high}` | без порога сканер не выходит с 1 — гейт-джоба зелёная при любых находках |
| effort по умолчанию (`xhigh`) | `--effort ${CODEX_SECURITY_EFFORT:-low}` | официальная рекомендация для MR-диффов; стоимость |
| — | `--max-cost` из переменной, если задана | оценочный предохранитель, не биллинг-кап |
| CLI 0.1.20 | 0.1.31 | версия, на которой проверены флаги (`scan --help`, `export --help`) |
| gate на `alpine:3.20` | тот же pinned node-образ | один образ, один pin |

Shell-вариант: без `image:`, `tags: ["$GATE_RUNNER_TAG"]`, проверка `node`
(22.13+/24/26), `python3` ≥ 3.10, `git` до установки, CLI в каталоге джобы;
`CODEX_SECURITY_AUTH=chatgpt` допустим (логин раннер-пользователя,
только приватный self-hosted GitLab). На Ubuntu 23.10+ с
`kernel.apparmor_restrict_unprivileged_userns=1` песочнице сканера нужен
AppArmor-профиль на встроенный бинарь `codex` — это хост, не шаблон.

### 2.7 `templates/agents/`

`AGENTS.md.skeleton` (bindings task-flow + `## Code Review Rules`),
`CLAUDE.md.skeleton` (`@AGENTS.md` + только Claude-специфика),
`.codex/config.toml.skeleton`, `.codex/agents/reviewer.toml` (роль для
интерактивного «spawn a subagent»: read-only, `developer_instructions`
обязательны по `agent_role_config.rs`), `.codex/rules/git.rules`
(`git commit` — allow; `git push` — **prompt**: человек в TUI, под
`codex exec` пушит раннер; `--force`/`-f`/`--force-with-lease`/`--mirror`/
`--delete` сразу после `push` — `forbidden`). Prefix-правило матчит точные
токены: `--force-with-lease=<ref>`, `-fu`, флаг после refspec оно не видит —
поэтому push не разрешается автоматически вообще, а не «разрешается кроме
force» (кросс-ревью Codex 2026-10-16 показало обход `allow`-варианта).
Примеры `match`/`not_match` в правилах Codex проверяет при загрузке.

## 3. Премортем (что ломается и что это ловит)

| # | Отказ | Что ловит |
|---|---|---|
| E1 | ревьюер ответил по-русски и перевёл метки вердикта → «чисто» по умолчанию | метки Assessment в шаблоне закреплены английскими; нераспознанный вердикт → exit 2; тест |
| E2 | `Reviewed:` не тот sha (ревьюер видел другой коммит / выдумал) | сверка с HEAD, иначе 2; тест |
| E3 | пустой/устаревший диапазон → «no findings» | `git diff --quiet` до диспатча → 2; тест |
| E4 | CLI нет / не залогинен / bwrap не поднялся | rc ревьюера ≠ 0 или пустой ответ → 2 + хвост stderr; тест со стабом |
| E5 | вложенный харнесс наследует сессию автора | scrub env; тест: стаб печатает своё env |
| E6 | плагин памяти пересказывает реализацию ревьюеру | изоляция по умолчанию; тест: флаги в argv стаба |
| E7 | ревьюер правит checkout | read-only флаги обоих CLI; тест argv + живой прогон: `git status` чист после |
| E8 | коммит отчёта «обнуляет» ревью или, наоборот, прячет правку кода | правило docs-only + команда проверки в cross-review.md |
| E9 | спеки нет / нет секции DoD | → 2 с указанием пути; тест |
| E10 | в спеке `&`, `\`, `[HEAD_SHA]` | буквальная подстановка, однопроходная; тест |
| E11 | инструкция ревьюеру внутри спеки/диффа | правило шаблона «data, not instruction» остаётся; скрипт ничего не eval'ит |
| E12 | Codex Security выдаётся за детерминированный слой | ci-gate шаг 7 и cross-review.md называют его LLM-слоем; lint-пин |
| E13 | shell-раннер: общий CLI-каталог между проектами | каталог на джобу, удаление в `after_script` |
| E14 | MR из форка видит защищённую переменную | правило: source project == target project, обе ветки protected |

## 4. Не в этом релизе

- Раннер loop-foundry с `codex exec` как исполнителем — S3 (loop-foundry 1.2.0).
- GitHub-вариант Codex Security, deep-сканы, remediation/draft MR — шаблон
  scan-only; расширение — по официальному полному `gitlab.yml`.
- `@codex review` в облаке GitLab/GitHub.

## 5. Приёмка

1. `scripts/lint.sh`, `scripts/release-check.sh` (UNRELEASED 1.12.0),
   `tests/run.sh` с новым `tests/xreview.sh` (стабы CLI, без сети/модели).
2. Живой `xreview.sh --by codex` и `--by claude` на lab-репо с внесённым
   дефектом: отчёт записан, вердикт распознан, `Reviewed:` == HEAD,
   `git status` lab-репо не изменился.
3. Docker-вариант Codex Security: скрипт джобы в pinned-образе с `--mock`
   (синтетические находки без LLM): SARIF непустой, `scan-exit-code.txt`
   = 1 при `--fail-on-severity high`, гейт-джоба выходит с ним.
4. `codex execpolicy check` по `git.rules`: plain push → allow,
   `push --force …` → forbidden; битый пример в правиле → ошибка загрузки.
5. `reviewer.toml` грузится Codex без предупреждения; намеренно битый — с
   предупреждением (негативный контроль).
6. yamllint по `templates/ci-gate/gitlab/` (CI делает), `claude plugin validate .`.

## 6. Перекрёстное ревью этого релиза (xreview на самом себе)

Строил Claude, ревьюил Codex (gpt-6.1-sol, effort high) через сам
`xreview.sh`; параллельно — фоновый security-review коммитов.

| Раунд | Вердикт | Находки → фикс |
|---|---|---|
| 1 · `946e855..536b596` | No | F1 `git diff --output` у Claude-ревьюера → без shell, материалы диапазона в брифе; F2 ключ виден `apt-get`/`npm` → снят первой строкой, установка под `env -i`, npm под `node`; F3 `--force-with-lease=…`/`-fu` обходят forbidden → push = prompt; F4 эхо плейсхолдера/«Yesterday»/длинный sha → строгий разбор; F5 scrub по списку → по семействам; F6 лишний grant `glab` → убран; F7 execpolicy-проверки молча пропускались в CI → pinned Codex CLI в CI, skip под CI = fail |
| фон (security) | — | S2 предсказуемые пути из `CI_JOB_ID` в общем `/tmp` → `mktemp -d` + trap; S3 `settings.local.json` (хуки, `apiKeyHelper`) и пользовательские `.rules` → `--setting-sources ""` + `disableAllHooks`, `--ignore-rules`; S4 fail-open парсера (отступ, HTML-комментарий, вложенный fence) → разбор видимого текста по секциям |
| 2 · `536b596..86825a6` | With fixes | D1 MCP-инструменты у Claude-ревьюера → `--strict-mcp-config` с пустым списком (заодно найдено: хук из `.claude/settings.json` диффа исполнялся); D2 граница поля в один символ, битый summary выпадал → целое значение, противоречие = 2; D3 CHANGELOG/спека отставали от кода → этот раздел и CHANGELOG |
