# Дизайн: `prediction-protocol` — прогноз как условие действия

**Дата:** 2026-08-22 (v2 — после премортема, см. ниже)
**Автор:** Sergei (umar-s) + Claude
**Статус:** design-spec v2 → реализация (отдельный плагин линейки devpowers)
**Источники:** `~/tmp/task-flow/prediction-protocol.md` (постановка владельца),
статья «ARC-AGI-3 is a skill issue» / `pbshgthm/arc-skill`,
`docs/audits/2026-08-21-dmitriy-toolkit-v3-audit.md` §7 (связь с аудитом), §4 O4/O7,
`docs/premortem/2026-08-22-prediction-protocol-premortem.md` (панель по v1 этого
документа — 60 находок, 20 выживших; что и почему изменилось — в §11)
**Затрагивает:** новый плагин + routing в `task-flow:task` (1.11.0) и контракт
для `loop-foundry`

---

## 1. Что переносим и что — нет

ARC-скилл добился одного: **инструмент отказывался отправить действие без
письменного прогноза**, и прогноз потом грейдился машинно против того, что
вернула игра. Два следствия: каждое действие становится экспериментом, а
точность прогнозов — измеримым критерием «я понимаю систему» против «мне
везёт» (37,1 % промахов у одиночных проб против 2,9 % внутри подтверждённого
плана — наблюдение автора post-hoc, не рантайм-переключатель).

**Переносим:** цепочку `hypothesis → predicted observable → falsifier → action
→ actual → verdict`; отказ действия без прогноза на узком подмножестве;
halt-at-first-miss; журнал промахов; и — главное, чего не было в v1 — **harness,
который сам исполняет измерение и сам ставит вердикт**. У ARC прогноз был
аргументом команды действия (`arc act … --predict`), а грейдил код. Здесь то же:
прогноз — аргумент `predict open`, вердикт ставит `predict close`, модель не
пишет ни `actual`, ни `verdict`.

**Не переносим:** «предсказывай кадр» (следующее состояние не наблюдаемо
целиком); покрытие каждого действия (шум); веру в самогрейдинг.

**Отброшено из ARC осознанно:** (а) объект «batch» — у нас его заменяют правило
«один receipt в полёте» и halt по состоянию сессии; (б) заметки
Verified/Assumed с протуханием — список HIT-записей журнала и есть Verified,
протухание живёт в `checkpoint.md` (`⚠ VERIFY` / `⏱ TTL`); (в) клеточная
грамматика утверждений — заменена закрытой грамматикой наблюдаемых (§3).

Отличие среды, которое определяет дизайн: **мир недетерминирован и частично
наблюдаем**. Ценность держится не на «прогнозе», а на **наблюдаемом с командой
измерения**: `predicted observable` без команды — намерение, а не прогноз.

## 2. Форма поставки

Отдельный плагин `prediction-protocol` в маркетплейсе devpowers, собственный
репозиторий по макету линейки (`plugins/prediction-protocol/`, тег `vX.Y.Z`):

```
plugins/prediction-protocol/
  .claude-plugin/plugin.json
  skills/prediction-protocol/SKILL.md        # протокол, скоупинг, три команды, routing-контракт
  skills/prediction-protocol/references/
      journal.md                             # грамматика записи и утверждений, REFUTED, строка report
      hook-engineering.md                    # чеклист хуков (из §7 аудита + §5 здесь)
  hooks/hooks.json                           # PreToolUse, matcher "Bash", timeout 15
  hooks/predict-gate.sh                      # тонкий гейт: stdin → классификатор → состояние сессии → решение
  bin/predict                                # CLI: on | off | open | close | ack | retry | withdraw | report | lint | classify | selftest
  lib/classify.sh                            # классификатор команд (один файл, source из хука и CLI)
  tests/                                     # корпуса must-deny / must-pass, негативные контроли, platform-probe
```

Почему отдельный плагин: механика нужна `task`, `loop-foundry` и разовым
сессиям; `task-flow` подключает её routing-строками, не меняя ядра — та же
форма, что сработала у донора (canonical skill + routing).

**Платформа:** Linux/macOS, инструмент `Bash`. `PowerShell` и MCP-инструменты
вне области 1.0 — заявлено в SKILL.md и README, не подразумевается. Хук и CLI —
portable bash без сетевых вызовов; парсер stdin — `python3`, затем `jq`, иначе
deny с причиной «нет парсера».

## 3. Протокол и грамматика

```
HYPOTHESIS            убеждение о системе           --hypothesis '<одна строка>'
PREDICTED OBSERVABLE  команда измерения + утверждение  --observe '<cmd>' --expect '<claim>'
FALSIFIER             выводится из claim (дополнение), не авторится
ACTION                действие                      --action '<точная команда>'
ACTUAL                что вернула команда измерения — пишет predict close, усечённо и с редакцией
VERDICT               HIT | MISS | INCONCLUSIVE — ставит predict close
```

**Закрытая грамматика `--expect`** (всё остальное — ошибка `open`, не запись):
`exit=N` · `stdout==<literal>` · `stdout~=<ERE>` · `stdout-in=<a>..<b>` (число в
диапазоне) · `lines=N` · `http=NNN` (сахар: `stdout==NNN`) · `count=N` (сахар:
числовой `stdout==N`). Falsifier — дополнение на той же команде; `close` печатает
его рядом, чтобы читающий видел, чем прогноз мог провалиться.

**Правила:**
- Для `scope=destructive` команда `--observe` обязана **отличаться** от
  `--action`, и `--expect` не может быть только `exit=…`: «действие вернёт 0» —
  тавтология, а не прогноз о системе. Для `advisory` это WARNING в lint.
- `INCONCLUSIVE` — команда измерения не отработала (не найдена, таймаут,
  exit ≠ 0 при утверждении о stdout). Считается в знаменателе hit-rate и
  **останавливает** сессию так же, как MISS, до `predict retry <id>` (новая
  запись, тот же observe) или `predict withdraw <id> --reason`.
- `MISS` — несовпадение, **подтверждённое повторным прогоном** измерения
  (`close` перезапускает observe один раз: шумное совпадение не становится
  опровержением). MISS ⇒ сессия остановлена для всех one-way команд до
  `predict ack <id> --refuted '<опровергнутое убеждение одной строкой>'`,
  который пишет строку в `docs/evidence/REFUTED.md`. Это (а)+(б)+(г) из v1
  одним механизмом; (в) — правка спеки/модели мира — остаётся на модели и
  проверяется в ревью.
- Что не сравнимо машинно — не HIT по определению: `INCONCLUSIVE`. Внешний
  грейдер (co-rar Critic) из 1.0 убран.
- `--baseline` (опционально): `open` прогоняет observe до действия и хранит
  результат; `lint` помечает прогноз, равный baseline при state-changing
  действии («ничего не изменится»), как WARNING.

## 4. Где протокол обязателен (и где — вред)

**Обязателен (hard gate, класс one-way) — в области протокола (§5):**
миграции и запуск мигратора (`alembic upgrade`, `rails db:migrate`, `artisan
migrate`, `prisma migrate deploy`, `flyway`, `liquibase`, `manage.py migrate`,
…); SQL-клиенты (`psql`, `mysql`, `mongosh`, `redis-cli`, …) с inline-SQL не
из `SELECT/SHOW/EXPLAIN`, с `-f`/`<`/heredoc (непрозрачный ввод) или с
`FLUSH*`; history-rewrite и слияния: `git push --force*` (включая
`--force-with-lease`), `git push --delete`, `git branch -D`, `gh pr merge`,
`glab mr merge`, `gh release create`; инфраструктура: `kubectl
delete|apply|rollout restart|scale|drain`, `helm install|upgrade|uninstall|rollback`,
`terraform|tofu apply|destroy|import|state rm`, `pulumi up|destroy`, `docker
rm|rmi|system prune|volume rm|compose down`, `systemctl|service
restart|stop|disable|mask`, `pm2|supervisorctl restart|stop|delete`;
удалённое исполнение как непрозрачный исполнитель: `ssh <host> <cmd>`,
`kubectl exec`, `docker exec`; HTTP с побочным эффектом: `curl|http|wget` с
`-X POST|PUT|DELETE|PATCH` или `-d|--data*|--json|-F|-T` **не** на
localhost; права и секреты: `aws iam …`, `aws s3 rm|rb`, `aws ec2 terminate`,
`aws rds delete`, `gcloud|az … delete`, `vault delete|revoke`, `gh secret
set|delete`; публикация: `npm publish`, `twine upload`, `cargo publish`,
`docker push`; удаление файлов: `rm -r*`, `find … -delete`, `shred`, `dd
of=/dev/`, `mkfs` — **кроме** путей, целиком лежащих под `/tmp/` или
`$TMPDIR` (скретч сессии).

Список — один файл `lib/classify.sh`, **свой**, командной формы (по позиции
глагола после снятия `sudo`, `env`, `VAR=…`, `time`, `nohup`, `timeout N`;
разбиение составных команд по `;`, `&&`, `||`, `|`, переводу строки;
`bash -c`/`sh -c`/`eval` — рекурсивно по строке-аргументу, нераспарсенный
аргумент → one-way). `SQL_RE` из `migration-guard` здесь **не**
переиспользуется как есть: та регулярка матчит тело файла миграции, а хук
видит командную строку — другой объект. Общий у двух потребителей только
словарь DDL/DML-глаголов для ветки inline-SQL.

Проект расширяет список без правки плагина: `predict on … --also '<prefix>'`
(из биндингов `CLAUDE.md` потребителя: `make deploy`, `bash scripts/release.sh`)
— префиксы хранятся в состоянии сессии, хук сравнивает по началу команды.

**Известные пределы (как у `migration-guard`, названы, не парсятся):**
`bash file.sh`, `make <target>`, `npm run <script>` без `--also` — не
классифицируются; SKILL.md называет обёртывание команды ради обхода гейта
**обходом** (запись `bypass` обязательна), а `task` фаза 6 читает журнал и
диапазон диффа: скрипт, появившийся ради обхода, — находка ревью. Текст
команды в кавычках с `;` может разбиться на лишние сегменты — это даёт больше
сегментов для классификации, никогда меньше.

**Advisory (без гейта, через routing):** отладка, live-верификация,
восстановление после сбоя, разведка. Чтобы advisory не был невидимым
(отсутствие записи ничем не ловится), потребитель назначает **объект**, у
которого есть счётчик: в `task` фаза 7 каждый `live`-пункт DoD закрывается
через `predict open --scope advisory … ; predict close` **до** взгляда на
результат, а оценка `DoD-n → PASS` цитирует `predict <id>`; пункт без id
виден в evidence-блоке как пункт без улики.

**Исключено:** read-only команды, тесты, сборка, линт, локальные правки кода,
обычный `git push`, `git checkout --`, `git clean`, `git reset --hard` (локально,
reflog), `rm` в скретче. Тест уже является прогнозом с детерминированным
вердиктом; «протокол на каждый `ls`» превращает дисциплину в шум, и её
выключают целиком.

Из v1 убрано «удаление … вне рабочего каталога сессии»: границу «своё / не
своё» хук вычислить не может (у него `cwd` и строка команды), а правило
провенанса уже живёт в `land.md` §7 и глобальном `CLAUDE.md` владельца как
ответ человека на вопрос, не как вычисление хука.

## 5. Гейт, состояние сессии и режимы

**Состояние сессии** — вне репозитория, пишет только `predict`:
`${XDG_STATE_HOME:-$HOME/.local/state}/prediction-protocol/sessions/<session_id>/`
— файл `state` (`on|off`, журнал, task/loop, `--also`, `halted=<id>`) и
`receipts.jsonl` (записи со штампом UTC скрипта и sha тела). Хук получает
`session_id` на stdin (и `CLAUDE_CODE_SESSION_ID` в окружении) — ему не нужны
`TASK-ID`, путь к журналу, cwd-зависимости и доступ к репо. Субагенты той же
сессии имеют тот же `session_id` и отличаются полем `agent_id`.

**Область протокола** — сессия, в которой выполнен `predict on <journal>
[--task ID | --loop NAME] [--also …]`. Это то же правило, что `gate: absent`
в `task`: состояние устанавливается командой и печатается, а не
подразумевается по содержимому репо. `predict on` прогоняет selftest хука
(синтетический stdin → ожидаемый deny) и печатает
`predict-gate: active v<ver> (selftest: deny)`; selftest доказывает скрипт, а
не регистрацию хука платформой — регистрацию доказывает `tests/platform-probe.sh`
(§10) при релизе.

**Receipt** привязан к действию и одноразов: `predict open --action '<cmd>'
…` → хук нормализует `tool_input.command` (пробелы, хвостовые `;`) и ищет в
**этой сессии** открытый, не истёкший (30 мин от штампа скрипта), не
потреблённый receipt с **равной** командой. Совпал — хук дописывает
`consumed <utc> <tool_use_id>` и выпускает; вторая такая же команда требует
нового `open`. Пока потреблённый receipt не закрыт (`close`), любая другая
one-way команда — deny «close <id> first»: один receipt в полёте, и halt
становится свойством состояния, а не просьбой к модели.

**Таблица решений** (режим хук определяет сам по stdin/окружению;
флаг режима от `loop-foundry` не нужен):

| контекст | вне области (`predict on` не было) | в области, receipt нет | в области, receipt совпал |
|---|---|---|---|
| интерактив (`CLAUDE_CODE_ENTRYPOINT=cli`, нет `agent_id`) | **`ask`** — O7 аудита: вопрос человеку на необратимом, в причине — что такое `predict on` | **`deny`** + рецепт: версия, путь к `predict`, одна строка `predict open …` с уже подставленной командой | **`ask`** с гипотезой/наблюдаемым/falsifier в причине — клик человека остаётся; хук никогда не отвечает `allow` |
| субагент (`agent_id` в stdin) | `ask` (всплывает владельцу) | `deny` «report this as a finding, do not write a receipt» — ревьюер read-only | `deny` — субагент не открывает one-way дверь, это делает оркестратор |
| headless (`ENTRYPOINT≠cli`, `-p`) | exit 0, stdout пуст — решают permissions runner'а (`loop-foundry` security §4 и так запрещает необратимое в deliver) | `deny` + рецепт | exit 0, stdout пуст (`ask` в headless = блокировка, проверено) |

Нерелевантная команда → exit 0, stdout пуст, в любом режиме. Слово `allow` в
коде хука запрещено (lint-grep).

**Fail-closed структурно, а не обещанием.** Платформа fail-open: `exit 1`,
битый JSON и таймаут хука **пропускают** действие (проверено на 2.1.239).
Поэтому: `trap` на ERR/EXIT, печатающий deny-JSON и `exit 2`; единственный
путь к `exit 0` — явный; собственный внутренний дедлайн (≤ 10 с) короче
`timeout` в `hooks.json` (15 с); никакой сети и блокирующих локов; парсер
stdin — `python3` → `jq` → deny «no JSON parser». Негативные контроли §10
бьют именно по путям ошибок. Fail-closed действует **в области**: вне её
ошибка хука на нерелевантной команде — exit 0 (иначе сломанный хук блокирует
все проекты владельца), на one-way команде — `ask`.

**Обход.** Переменной окружения нет: она либо навсегда в `.bashrc`, либо в
строке команды, то есть её пишет та же модель. Обход — это (а) клик человека
на `ask` и (б) `predict off --reason '…'`, который пишет запись `bypass` в
журнал и переводит хук этой сессии в режим «вне области» (`ask`). Для
headless обхода нет — там нет человека.

**Хук не пишет ничего, кроме `consumed`** в state-файл сессии. `PostToolUse`
не может блокировать и не используется; грейдинг — в `predict close`.

**Поставка и отзыв.** Версия плагина печатается в каждой причине deny/ask.
CI репозитория плагина прогоняет матрицу §10 до `main`; каталог devpowers
ref не пинит (конвенция линейки), поэтому аварийный выключатель — `predict
off` в сессии и выключение плагина глобально. `hook-engineering.md` —
чеклист: matcher литерал `Bash` (не regex), `timeout` явно, `LC_ALL=C`,
единственный exit-0 путь, фикстуры stdin с `agent_id` и без, `${CLAUDE_PLUGIN_ROOT}`
вместо префиксов установки, инвентарь инструментов платформы.

## 6. Журнал и метрики

- Записи в репо пишет только `predict close` (и `ack`/`withdraw`/`off`):
  `docs/evidence/<journal>.md` (для лупов — `loops/evidence/<loop>.md`;
  имя — аргумент `predict on`: `TASK-ID`, имя лупа или `session-<дата>`), путь
  от `git rev-parse --show-toplevel` текущего cwd `close`. Открытые receipt'ы
  в репо не попадают — ни шума коммитов, ни чужих гипотез в диффе ревью.
  Журнал коммитится в фазе 8 `task` при закрытии.
- Заголовок записи машинно-парсимый и версионированный:
  `### predict <session8>-<seq> · <utc> · scope=<destructive|advisory> · verdict=<HIT|MISS|INCONCLUSIVE|withdrawn|bypass> · contract=1`;
  тело — `hypothesis`, `action`, `observe → expect (falsifier: …)`, `actual`
  (`exit=`, `stdout=` ≤ 5 строк / ≤ 512 байт, `confirmed ×2` для MISS,
  `redaction: builtin|gitleaks`), `refuted:` после `ack`. Потребители не
  парсят файл — они вызывают `predict report`; смена контракта меняет номер.
- **Леджер убеждений** — один файл на репозиторий, `docs/evidence/REFUTED.md`,
  append-only: `| <дата> | <id> | <убеждение> | <пути/системы> |`. Пишет только
  `predict ack`; `lint` требует, чтобы у каждого MISS была ровно одна строка.
  **Читатель назван:** `task` фаза 0 читает файл и переносит строки, задевающие
  пути/системы задачи, в Context pack спеки; `loop-foundry` — в Phase 0 лупа.
- **hit-rate** печатает `predict report`, и только его строка идёт в
  evidence-блок: `predictions: H HIT / M MISS / I INCONCLUSIVE / B bypass / O open ·
  scope=destructive H/M · n=N · window=<journal|last K>` и
  `rate = HIT / (HIT + MISS + INCONCLUSIVE)`; при `n < K` (K = 20 по умолчанию)
  — `insufficient`, не процент. Это **второй сигнал**: порог предлагает
  эскалацию, решает человек или явная политика лупа.
- **Секреты и PII:** `actual` — значение наблюдаемого плюс усечённый фрагмент,
  через встроенный набор масок (`Authorization:`, `://user:pass@`, `-----BEGIN`,
  `AKIA…`, `ghp_…`, `key=value` с секретными именами) **всегда**, и через
  `ci/scan-text.sh` репозитория, когда он есть; `redaction:` в записи говорит,
  что именно сработало, молчаливого пропуска нет. Значения переменных
  окружения в запись не попадают (`$VAR` в `action` хранится как написано).

## 7. Подключение к линейке

**`task-flow:task` (1.11.0)** — список поставки, по дому:
- фаза 0: `docs/evidence/REFUTED.md` читается, релевантные строки → Context pack;
- фаза 5, преамбула (рядом с пином toolchain): `predict on <TASK-ID> [--also
  <из биндингов>]` → строка `predict-gate: active v… (selftest: deny)` либо
  `predict-gate: absent (predict → not found)`; state-changing шаги
  реализации (миграция на dev, сид, рестарт) — `open → действие → close`;
- фаза 7: каждый `live`-пункт DoD — advisory-цикл **до** взгляда, `DoD-n`
  цитирует `predict <id>`;
- фаза 8 / `land.md` §1–§2: merge и deploy — receipt'ы, чьи наблюдаемые уже
  названы в `land.md` (`state == MERGED`, `headSha == merge SHA`, health-check
  200); `land.md` §6: «deny гейта прогнозов — не permission denied: открыть
  receipt и повторить ту же команду один раз»; evidence-блок — строка
  `predict report` дословно, допустимая только рядом с `predict-gate: active`;
  журнал коммитится при закрытии;
- шаблоны ревью 6/6b: «deny гейта — находка, ревьюер receipt не пишет»;
- `lint.sh` — grep на каждую строку выше, по секциям; пара README; CHANGELOG;
  тег; Release. Ядро `task` не меняется; без плагина строки дают `absent`
  и флоу идёт дальше.

**`loop-foundry`** (контракт; реализация — релиз loop-foundry): `run.sh`
вызывает `predict on <loop> --loop` из корня плагина на хосте runner'а —
пункт GAPS-чеклиста «CLI `predict` доступен в окружении runner'а, доказано
`predict selftest`»; в конце тика `predict report --json` сливается в запись
`loops/journal/<loop>.jsonl` полем `predictions` — **один журнал**, не два;
текст promotion в `ladder.md` читает approval rate и prediction rate вместе с
долей INCONCLUSIVE; halt — состояние `halted` в сессии (хук) плюс
`predict status` с exit-кодом для `gates.sh`. Никакого флага режима между
плагинами: режим хук читает из stdin.

**`co-rar`:** из 1.0 убран; несравнимое машинно — INCONCLUSIVE.

## 8. Что уже сделано в 1.8.x–1.10.0 и переиспользуется

- `ci-gate` — доказанная дисциплина fail-closed и негативных контролей, словарь
  DDL/DML-глаголов для inline-SQL ветки, `scan-text.sh` как scan-at-sink.
- `task` 1.9.0 — `DoD-n` с классом верифицируемости, `Reversibility` со
  stop-условием, evidence-блок с командой. Чтобы не вести одно правило в двух
  местах: `live`-строка DoD **цитирует** `predict <id>` вместо второй копии
  команды, а stop-условие deploy — это falsifier deploy-receipt'а.
- `checkpoint.md` — `⚠ VERIFY <команда>` / `⏱ TTL` для протухающих фактов.

## 9. Риски, оставшиеся после премортема

1. **Тавтологические прогнозы** — закрыты грамматикой и правилом
   «observe ≠ action, не только exit=» для destructive; доля WARNING'ов lint
   видна в `report`. Остаток: семантически пустой, но формально разный
   observe — это задача ревью 6.
2. **Обёртки (`bash file.sh`, `make`)** — названный предел, `--also` из
   биндингов, правило «обёртка ради обхода = bypass», ревью читает журнал.
3. **Хук как единая точка отказа** — структурный fail-closed в области, exit 0
   вне области на нерелевантных командах, `predict off` как аварийный выход.
4. **Журнал как утечка** — встроенные маски всегда, gitleaks когда есть,
   `redaction:` в записи.
5. **hit-rate как цель** — INCONCLUSIVE в знаменателе, `n<K → insufficient`,
   разбивка по scope, только строка `report`. Остаток: метрика ценна на N,
   которого одна задача не даёт — это сигнал для лупов, не для задач.
6. **Правка state-файла руками** — модель может отредактировать
   `~/.local/state/...` через Edit. Это осознанный обход, а не дыра формы:
   sha тела receipt'а при `consumed` ловит правку между open и действием;
   правка после — находка ревью по журналу.

## 10. Критерии приёмки — матрица фикстур

1. **must-deny** — по одной команде на каждый класс §4, в области, без
   receipt → deny-JSON; причина содержит версию и строку `predict open` с
   подставленной командой.
2. **must-pass** — по одной на каждый класс «Исключено» (grep с `DELETE FROM`,
   `git log --grep`, `git branch -d`, `git checkout --`, `truncate -s0 x.log`,
   `psql -c 'select …'`, `rm -rf /tmp/x`, `bash scripts/lint.sh`, `make test`,
   `curl localhost -X POST`) в области → exit 0, stdout пуст.
3. **вне области** — one-way команда: интерактивный stdin → `ask`; headless
   → exit 0 пусто; нерелевантная → exit 0 пусто.
4. **receipt-путь** — `open` → та же команда → `ask` (интерактив) / exit 0
   (headless), `consumed` дописан; вторая та же команда → deny; другая
   one-way при открытом → deny «close first»; истёкший (штамп −31 мин) → deny.
5. **halt** — `close` с несовпадением дважды → MISS, `halted`; следующая
   one-way → deny до `ack`; `ack` пишет одну строку в `REFUTED.md`;
   INCONCLUSIVE → тот же halt до `retry`/`withdraw`.
6. **пути ошибок** — нет state-каталога, state нечитаем, stdin не JSON, нет
   `python3` и `jq` в PATH, внутренний дедлайн (индуцированный sleep под
   `timeout`) — каждый → deny-JSON или exit 2 **в области**; вне области на
   нерелевантной команде — exit 0.
7. **субагент** — stdin с `agent_id`: one-way без receipt → deny с «report as
   a finding»; с receipt → deny.
8. **lint журнала** — запись без observe-команды; `expect` вне грамматики;
   verdict без actual; verdict без штампа скрипта; `actual` с секретной
   формой; MISS без строки в REFUTED — каждая падает; чистая запись проходит.
9. **report** — счётчики с INCONCLUSIVE в знаменателе; `n<K` → `insufficient`.
10. **platform-probe** (`tests/platform-probe.sh`, ручной, нужен `claude -p`):
    deny / ask / exit 0 через настоящую платформу — таблица из премортема
    воспроизводится на текущей версии Claude Code.
11. **без плагина** — `task` 1.11.0: строки routing дают `predict-gate:
    absent`, флоу продолжается; `lint.sh` task-flow проверяет условную
    формулировку.
12. **selftest** — `predict on` без рабочего хука печатает не `active`, а
    причину.

## 11. Что изменил премортем (v1 → v2)

Коротко; полный список с голосами — в `docs/premortem/2026-08-22-prediction-protocol-premortem.md`.

- Receipt не был привязан ни к команде, ни к сессии: один открытый receipt
  открывал любую one-way команду на 30 минут → `--action`, сравнение с
  `tool_input.command`, одноразовость, один в полёте.
- «Машинный грейдинг» не имел машины: `actual`/`verdict` писала модель →
  CLI `predict close` исполняет измерение и ставит вердикт; закрытая грамматика
  утверждений; falsifier выводится.
- «Один список, два потребителя» — категориальная ошибка: `SQL_RE` матчит
  файл, хук видит команду → свой классификатор командной формы с корпусами.
- Глобальный хук + fail-closed + журнал по `TASK-ID` = deny во всех проектах
  без задачи → область сессии через `predict on`, состояние вне репо, таблица
  режимов, `ask` как O7 вне области.
- Платформа fail-open при падении хука → структурный trap/exit 2, дедлайн,
  негативные контроли на пути ошибок.
- Ветка «с receipt» не была описана, `allow` снял бы клик человека → `ask` с
  прогнозом в причине; `allow` запрещён.
- Обход через переменную → клик на `ask` и `predict off --reason`.
- Фаза 8 (merge/deploy) — там гейт срабатывает, а routing туда не шёл, и
  `land.md` велит «стоп на permission denied» → routing в `land.md` §1–§2 и §6.
- Хук срабатывает в субагентах-ревьюерах → ветка `agent_id`.
- hit-rate нечем считать, INCONCLUSIVE — лазейка → `predict report`,
  знаменатель, `n<K`.
- Леджер Refuted был write-only → один файл на репо, читатель назван (фаза 0).
- `actual` «дословно» vs «усечённо», скан «если есть» → бюджет, маски всегда.
- MCP-matcher обещал то, чего нет → Bash-only, заявлено.
- Режим от loop-foundry → режим из stdin/окружения; один журнал лупа.
- §10 проверял только «отказал» → матрица из 12 строк, включая must-pass и
  пути ошибок.
