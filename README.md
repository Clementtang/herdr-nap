<div align="center">

# herdr-nap

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/github/v/tag/Clementtang/herdr-nap?label=version)](CHANGELOG.md)
[![herdr](https://img.shields.io/badge/herdr-%3E%3D0.9.0-7aa2f7)](https://herdr.dev/)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)](herdr-plugin.toml)
[![Bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25)](herdr-nap)

[English](#english) | [繁體中文](#繁體中文)

</div>

## English

A native [herdr](https://herdr.dev/) plugin that puts idle coding agents to sleep and wakes them up where they were. herdr's session persistence relaunches every parked agent when the server starts and never releases them (14 `claude --resume` processes spawned in the same second, about 2 GB after a day idle), and herdr has no hibernate feature (Discussion #631 is still an idea). `herdr-nap` is manual and interactive: you pick, you confirm, nothing runs on a timer.

### Usage

```
herdr-nap            interactive picker (TAB to multi-select, Enter to nap, Esc to cancel)
herdr-nap --list     list only, no changes
herdr-nap --restore  bring back every napped herdr agent
```

- The list is sorted by **idle time**, longest idle first. Idle time comes from the last timestamp in the conversation transcript (claude: `~/.claude/projects/*/<session>.jsonl` plus its `subagents/*.jsonl`; grok: `~/.grok/sessions/*/<session>/updates.jsonl`), not from process age, so a resumed old session does not look fresh. RSS is the whole process tree (MCP servers and tool children included). A notes column flags `children:N`, `subagent-active`, `just-started` and `no-transcript`. It only marks, it never blocks.
- A preview window under the fzf list shows the current screen of the highlighted pane (`herdr pane read --source visible`), Ctrl-/ toggles it.
- **Pinned exclusions**: `~/.config/herdr-nap/exclude` holds one substring per line (`#` starts a comment). Agents whose pane title or tab label contains one are left out of the picker so they cannot be picked by mistake; `--list` still shows them, marked and dimmed. Substrings are used instead of pane or tab ids because ids change when a workspace is closed and reopened.
- herdr-managed agents (claude, grok, and so on) are asked to exit with `herdr agent prompt <pane> /exit`: the process ends, the pane stays, herdr's state stays in sync. Verified with claude and grok.
- After napping, the pane runs a small stub that shows how much memory was freed and the session id. **Press Enter to resume in place**, Ctrl-C to drop to a normal shell. While waiting, the stub sets the terminal title to `[nap] <original title>` (an OSC title sequence, not `herdr tab rename`, so nothing needs cleaning up afterwards). `--restore` handles every record at once: it sends Enter to panes still holding a stub and runs `herdr agent start <name> --kind <kind> --pane <pane> -- <original flags> --resume <session-id>` for panes that went back to a shell prompt. Neither path loses the conversation.
- **Original launch flags are replayed on restore** (for example `--dangerously-skip-permissions`, `--model`). When napping, the agent's argv is read from `ps`, session-continuation flags (`--resume`, `-r`, `-c`, `--session-id`, `--fork-session`) and bare positionals (usually a startup prompt, which would be sent as a new message) are dropped, and the rest is stored as the sixth column of the record. Old five-column records still load with an empty argv.
- If a pane was closed (or its whole workspace is gone), `--restore` says so, prints the command to restore into a fresh pane, and keeps the record.
- Restore is not always hands-off: `claude --dangerously-skip-permissions --resume` first shows the workspace trust prompt, which herdr reports as blocked. Both restore paths detect that state and tell you to answer in the pane; the record is kept until the session is really back. The tool never answers a prompt for you.
- Resuming by pressing Enter needs no cleanup. On the next run, stale records and stub files are removed once herdr reports that the recorded session id is running in that pane. Having some agent of the same kind in the pane does not count.
- A pane taken over by a different session is not treated as restored: the conflict is reported, the record stays, and the command to restore elsewhere is printed. The napped session id only lives in that record.
- Agents for which herdr reports no session id are exited without a record or stub, and the tool says plainly that the conversation cannot be restored automatically.
- claude / grok processes started outside herdr fall back to SIGTERM; `claude --resume` brings them back.
- Safety: the tool's own pane is excluded, every nap is confirmed with y/N, each exit is verified and reported, records live in `~/.local/state/herdr-nap/napped.tsv`, stubs in `~/.local/state/herdr-nap/panes/`.
- `--list` is read-only. Dependency checks follow the mode, so `--list` and `--restore` work without fzf.
- **Language**: messages are English unless `LC_ALL`, `LC_MESSAGES` or `LANG` starts with `zh`, which selects Traditional Chinese. `HERDR_NAP_LANG=en|zh` overrides. A stub keeps the language it was written in.

### Install

Requires `jq` and `fzf` (`brew install jq fzf`). herdr's plugin manifest has no dependency field, so install them yourself.

Two ways, both sharing `~/.local/state/herdr-nap/`:

- **herdr plugin**: `herdr plugin install Clementtang/herdr-nap --yes`. The plugin action menu gets three entries (pick agents to nap, restore all, list only), each opening in an overlay pane. To update, run install again (herdr 0.9 has no `plugin update`).
- **Direct**: symlink `~/bin/herdr-nap` to `herdr-nap` in this repository.

For local plugin development use `herdr plugin link ~/herdr-nap` (no build step, the manifest points at the working tree) and `herdr plugin unlink clementtang.herdr-nap` to remove it. The interactive picker needs a TTY for fzf, so all three entry points are declared as `[[panes]]`; each action just calls `herdr plugin pane open`. Pane commands run with the user's working directory as cwd, so scripts are referenced through `$HERDR_PLUGIN_ROOT` and herdr through `$HERDR_BIN_PATH`.

Development setup (once per clone, `core.hooksPath` is local config):

```
git config core.hooksPath githooks
```

`githooks/pre-commit` rejects a bash variable directly followed by a non-ASCII character (see the bash 3.2 note below).

Tests are pure-function tests that run on the stock bash 3.2, no bats needed:

```
tests/run-tests.sh
```

`HERDR_NAP_LIB_ONLY=1 source herdr-nap` loads only the functions. Tests cover flag replay, record format and merging, single-quote wrapping, timestamp parsing, descendant RSS summing and risk markers.

### What happens after a herdr server restart (measured, 2026-09-18)

- herdr's persisted `~/.config/herdr/session.json` stores only cwd per pane, plus `agent_session` when an agent is present. Napped panes (stub waiting or back at a shell) have no `agent_session`.
- Panes napped on 8/26 and 9/4 went through restarts on 9/1 and 9/9: same pane id (session.json keeps a `public_pane_numbers` map), same cwd, empty shell, stub gone, no agent relaunched.
- So a restart does not bring napped agents back to eat memory; you only lose the in-pane Enter shortcut. `--restore` already handles panes at a shell prompt through `herdr agent start`, so no shell hook is needed.
- herdr relaunches live agents with plain `claude --resume <uuid>`, dropping their original flags. That is herdr's behaviour, outside this tool's reach.
- For experiments that need an isolated server, use a named session (`herdr --session <name>`: separate directory and socket, the CLI follows `HERDR_SOCKET_PATH`) instead of restarting the main one.

### Implementation notes (lessons learned)

- **Data source is `herdr agent list`** (`.result.agents[]`): agent kind, `agent_status` (idle / working / done / blocked / unknown), `pane_id`, `cwd`, `agent_session.value` (the session id used for resume), optional `name` (a renamed agent, restored with it), terminal title. No PID.
- **The agent PID is the direct child of the pane shell**: `herdr pane process-info --pane <id>` gives `shell_pid`, then match ppid in `ps`. Its `foreground_processes` is a grandchild while the agent runs a tool, so PID and RSS would be wrong and the agent itself would be misread as a stray process.
- **Rows are TSV all the way, no padding**: values later passed to herdr stay untouched, alignment is the display layer's job (`column -t` for `--list` and the confirmation list, `--header-lines=1` and tab stops for fzf). fzf hides columns with `--delimiter=$'\t' --with-nth`; a selected line still carries every field, no lookup afterwards.
- **"Pane is at an interactive shell" means `shell_pid == foreground_processes[0].pid`**; do not guess shell names from argv0. "Agent has exited" means its PID is gone.
- **`herdr agent prompt <pane> /exit --wait` returns `agent_not_running`**: the prompt landed, the agent exited, the wait found nothing. That is the success signal; then verify the PID is gone.
- **Stray process scan matches argv0 only**: matching the whole args string is tripped by text inside arguments (a message containing "claude/grok" sent through `herdr agent prompt` did exactly that).
- **macOS bash 3.2 and UTF-8**: `$var` directly followed by a full-width punctuation mark swallows the multibyte character into the variable name and dies under `set -u`. Always write `${var}` next to non-ASCII text.
- `herdr pane release-agent` only unregisters the agent, the process keeps running; it does not free memory (confirmed in #631).
- Self exclusion: herdr rows are compared with `herdr pane current`; stray rows walk the ancestor PID chain (also the fallback when the tool runs outside herdr).
- `napped.tsv` accumulates: several nap batches merge (latest wins per pane) and `--restore` keeps only the failures.
- **The stub must be a child of the pane shell, never `exec` in its place**: the stub `exec`s into the agent, so the agent lands as the pane shell's direct child and the next nap does not take the whole pane with it. Design borrowed from [bengemine/herdr-hibernate](https://github.com/bengemine/herdr-hibernate).
- **While the stub waits, the pane is not at a shell prompt** and `herdr agent start` refuses it, so `--restore` sends `herdr pane send-keys <pane> enter` and lets the stub exec.
- **bash 3.2 `printf %q` escapes CJK text byte by byte**: the stub still runs but is unreadable. Wrapping in single quotes by hand (`sq()`) is enough.
- **"This session is back" can only be decided by `agent_session.value` from `herdr agent list`**: a live process proves only that some agent of that kind is running, maybe a completely different session. Treating that as success would wipe the only copy of the session id.
- **One `ps` snapshot per run**, and every lookup (direct child, RSS, etime, stray processes) reads it with awk; refresh explicitly when current state matters (after `/exit` or resume). Scanning per pane meant 20 scans for 20 agents.
- **In bash 3.2 a `while` in a pipeline runs in a subshell**, so `return` inside only ends the subshell. Never write helpers as `ps | while ... return`.
- **`ps` shows argv without the original quoting**: a flag value with spaces splits into several tokens and only the first survives. Bare positionals are dropped, and so is a positional after a known boolean flag (the boolean list is separated by spaces or newlines, so matching must accept both). Globbing is off while replaying argv so `--add-dir *` is not expanded into file names.
- **Transcript jsonl mtime is not idle time**: Claude Code rewrites idle transcripts (a file whose last message was 9/15 had an mtime of 9/18), so every agent looked active minutes ago. Read the largest `timestamp` among the last lines instead (ISO 8601 UTC for claude, epoch seconds for grok); the tail may hold a few ledger lines without a timestamp.
- **Find session files by globbing the session id**, not by re-deriving the cwd encoding: claude turns `/` into `-`, grok percent-encodes, and grok's code-review sessions live under a `~/.grok/worktrees/...` encoding that does not match the cwd herdr reports. The uuid is unique, one glob is enough.
- **`cut -f` always outputs fields in ascending order**, so the display order is the column order: shown columns first, hidden ones last; the fzf preview reads the pane from `{3}`, adjust it when reordering. The same field list feeds `cut -f` and fzf `--with-nth`, so it must be a comma list: cut's `1-10` is rejected by fzf (the interactive mode fails outright while `--list` looks fine). A `fzf --filter` test guards the expression.
- **herdr honours OSC 0 titles sent from a pane** (`terminal_title` in `herdr pane list` follows a `printf '\033]0;...\007'`). zsh resets the title at every prompt, so only a title set by a process that stays in the foreground survives; the stub blocked on `read` fits.
- **`herdr agent start`'s exit code does not tell whether restore worked**: when the agent stops at a prompt during startup (workspace trust, for example), herdr returns `agent_not_ready` at once even though the process is up. Success is judged by the session id reported in `herdr agent list`; blocked gets its own message.
- **Testing the interactive mode without a TTY**: `FZF_DEFAULT_OPTS="--exact --filter=<pane>" herdr-nap <<< y` runs the full nap flow (fzf in filter mode does not need a terminal), handy for end-to-end tests on one pane.
- Idle claude agents have no long-lived children (14 measured, zero descendants) and `/exit` leaves no orphaned MCP process, so the tool never kills a process tree. Descendant sums only affect the RSS column and the child-process marker.

### Known limitations

- Resuming by pressing Enter starts the agent from the stub's `exec`, so herdr names it after the agent kind and a custom agent name is lost. `--restore` brings the name back.
- Agents in `working` state are listed too (the fzf header warns); whether to nap them is your call.
- Idle time is only available for claude and grok; other kinds show process age and `no-transcript`.

## 繁體中文

herdr 原生的 agent 清理工具。herdr 的 session persistence 會在 server 啟動時把所有 parked pane 的 agent 批次拉活且永不釋放（實測 14 個 `claude --resume` 同秒 spawn、閒置一天約 2 GB），官方沒有 hibernate 功能（Discussion #631 未實作）。`herdr-nap` 提供手動、互動挑選式的清理，是 `~/bin/claude-prune` 的 herdr 升級版。

### 用法

```
herdr-nap            互動挑選（TAB 多選、Enter 清理、Esc 取消）
herdr-nap --list     只列出，不清理
herdr-nap --restore  復原先前清理掉的 herdr agent
```

- 清單依**閒置時間**排序，閒置最久的在最上面。閒置取對話紀錄最後一筆的 timestamp（claude 讀 `~/.claude/projects/*/<session>.jsonl` 與其 `subagents/*.jsonl`，grok 讀 `~/.grok/sessions/*/<session>/updates.jsonl`），不是 process 年齡，resume 過的舊 session 不會顯示成很新。RSS 是整棵 process 樹（含 MCP 與工具子行程）的合計。備註欄標記「子行程N」「subagent活動中」「剛啟動」「無對話紀錄」，只標記不擋。
- fzf 下方有預覽窗，顯示游標所在 pane 的目前畫面（`herdr pane read --source visible`），Ctrl-/ 切換。
- **釘選排除**：`~/.config/herdr-nap/exclude` 一行一個字樣（`#` 開頭是註解），pane 標題或 tab 標籤含該字樣的 agent 不進 fzf 清單，連誤點的機會都沒有；`--list` 仍列出，備註標「釘選」並灰顯（輸出到終端時才上色）。用字樣不用 pane id 或 tab id，因為 id 在 workspace 關開後會變。
- herdr 管的 agent（claude、grok 等）走 `herdr agent prompt <pane> /exit` 請它自行退出：process 結束、pane 保留、herdr 狀態同步。已實測 claude 與 grok 都吃 `/exit`。
- 休眠後 pane 裡會留一個待命 stub，顯示釋放了多少記憶體與 session id，**按 Enter 就地復原**、Ctrl-C 回到一般 shell。stub 待命時把終端標題設成 `[nap] 原標題`；用的是 OSC 標題跳脫序列而不是 `herdr tab rename`，agent 復原或回到 shell 時標題自然被蓋掉，不需要清理。整批復原走 `--restore`，對 stub 待命中的 pane 送 Enter，對已回到 shell prompt 的 pane 走 `herdr agent start <name> --kind <kind> --pane <pane> -- <原啟動旗標> --resume <session-id>`。兩條路都不遺失對話。
- **復原時帶回原本的啟動旗標**（例如 `--dangerously-skip-permissions`、`--model`）。休眠時從 ps 取 agent 的 argv，去掉 `--resume`/`-r`/`-c`/`--session-id`/`--fork-session` 這類接續 session 的旗標與裸位置參數（多半是啟動 prompt，重播會被當成新訊息），其餘存進紀錄第 6 欄。舊的 5 欄紀錄照常可讀，argv 視為空。
- pane 已經被關掉（或整個 workspace 沒了）的紀錄，`--restore` 會明講「已不存在」並給開新 pane 復原的指令，紀錄保留。
- 復原不一定全自動：實測 `claude --dangerously-skip-permissions --resume` 起來後會先跳「工作區信任」確認畫面，herdr 回報 blocked。兩條復原路徑都會偵測這個狀態並提示到該 pane 回答，紀錄保留到 session 真的回來為止。工具不會替你回答任何確認畫面。
- 自己在 pane 裡按 Enter 復原之後不必收拾，下次執行時過期紀錄與 stub 檔會自動清掉。判斷依據是 herdr 回報的 session id 與紀錄相符，**不是**「這個 pane 有同類 agent 在跑」。
- pane 已經被別的 session 佔用時不會當成復原成功：報告衝突、紀錄留著，並附上換 pane 復原的指令。休眠中的 session id 只存在紀錄裡，刪掉就再也找不回來。
- herdr 沒有回報 session id 的 agent，退出後不寫紀錄也不留 stub，並明講這個對話無法自動復原。
- herdr 之外直開的 claude / grok 維持 SIGTERM fallback，`claude --resume` 可復原。
- 防呆：排除自身 pane、清理前 y/N 確認、逐一驗證退出並回報、復原紀錄存 `~/.local/state/herdr-nap/napped.tsv`、stub 存 `~/.local/state/herdr-nap/panes/`。
- `--list` 是唯讀模式，不動狀態檔；依賴檢查按 mode 做，沒裝 fzf 仍能 `--list` 與 `--restore`。
- **語言**：`LC_ALL`、`LC_MESSAGES` 或 `LANG` 以 `zh` 開頭就顯示繁體中文，其餘一律英文；`HERDR_NAP_LANG=en|zh` 可強制。stub 的訊息在產生當下就固定語言。訊息集中在腳本的 `msg_zh` 與 `msg_en` 兩張表，測試會比對兩邊 key 一致。

### 安裝

需要 `jq` 與 `fzf`（`brew install jq fzf`）。herdr 的 plugin manifest 沒有相依欄位，請自行安裝。

兩種裝法，狀態檔共用 `~/.local/state/herdr-nap/`，可以並存：

- **herdr plugin**（給其他 herdr 使用者）：`herdr plugin install Clementtang/herdr-nap --yes`。裝完在 plugin action 選單有三個動作：「Nap: 挑選 agent 休眠」「Nap: 整批復原」「Nap: 只列出」，各自在 overlay pane 裡開啟。更新就再跑一次 install（herdr 0.9 沒有 plugin update 指令）。
- **直接執行**：`~/bin/herdr-nap` symlink 到本專案的 `herdr-nap`，改這裡即生效。

本機開發 plugin 用 `herdr plugin link ~/herdr-nap`（不會跑 build，manifest 直接指向工作目錄，改完即生效），`herdr plugin unlink clementtang.herdr-nap` 移除。互動挑選要 fzf 佔 TTY，所以 manifest 裡三個入口都宣告成 `[[panes]]`，action 只負責 `herdr plugin pane open` 把 pane 叫出來；pane 的 cwd 是使用者的工作目錄，腳本路徑一律走 `$HERDR_PLUGIN_ROOT`，呼叫 herdr 走 `$HERDR_BIN_PATH`。

開發環境（新 clone 或換機器時要跑一次，`core.hooksPath` 是本機 config，不跟著 repo 走）：

```
git config core.hooksPath githooks
```

`githooks/pre-commit` 會擋下 bash 腳本裡變數緊貼非 ASCII 字元的寫法（見下方實作要點）。

測試（純函式，不依賴 bats，內建 bash 3.2 直接跑）：

```
tests/run-tests.sh
```

腳本用 `HERDR_NAP_LIB_ONLY=1 source herdr-nap` 只載入函式，主流程不會執行。測試涵蓋旗標重播、紀錄格式與合併、單引號包裝、閒置時間解析、子孫 RSS 加總與風險標記。

### herdr server 重啟後會怎樣（實測，2026-09-18）

- herdr 的持久化檔 `~/.config/herdr/session.json` 對每個 pane 只存 cwd，pane 上有 agent 時才多存 `agent_session`。已休眠的 pane（不論 stub 待命中或已回 shell）沒有 `agent_session`。
- 8/26 與 9/4 休眠的 pane 經過 9/1、9/9 兩次重啟後：pane id 不變（session.json 有 `public_pane_numbers` 對照表）、cwd 不變、變成空 shell、stub 消失、agent 沒有被拉起。
- 所以重啟不會讓休眠的 agent 回來吃記憶體，只會失去 pane 裡按 Enter 的捷徑；`--restore` 對停在 shell prompt 的 pane 本來就走 `herdr agent start`，不需要 shell hook，也不動 `.zshrc`。
- herdr 自己重啟時拉起活著的 agent 用的是 `claude --resume <uuid>`，原本的啟動旗標一樣會掉。這是 herdr 的行為，本工具管不到。
- 需要隔離的 herdr server 做實驗時，用具名 session（`herdr --session <name>`，獨立目錄與 socket，CLI 靠 `HERDR_SOCKET_PATH` 指向），不要重啟主 server。

### 實作要點（踩過的坑）

- **資料源是 `herdr agent list`** 的 `.result.agents[]`：agent 種類、`agent_status`（idle / working / done / blocked / unknown）、`pane_id`、`cwd`、`agent_session.value`（resume 用的 session id）、optional `name`（rename 過的 agent 名，restore 時要帶回）、terminal title；沒有 PID。
- **agent PID 要從 pane shell 的直屬子 process 找**，指令是 `herdr pane process-info --pane <id>` 拿 `shell_pid` 再對 `ps` 的 ppid。它回傳的 `foreground_processes` 在 agent 跑工具時會是孫層子 process，PID 與 RSS 都會拿錯，還會讓本體被誤判成 herdr 之外的 process。
- **資料列全程 TSV，欄位不做 pad**：之後要拿去打 herdr 的值保持原樣，對齊交給顯示層（`--list` 與確認清單用 `column -t`，fzf 用 `--header-lines=1` 帶表頭、tab 對齊靠 tabstop）。fzf 用 `--delimiter=$'\t' --with-nth` 隱藏 name / session 欄，選中列仍帶完整資料，不需要事後反查。
- **「pane 停在互動 shell 上」的判斷是 `shell_pid == foreground_processes[0].pid`**，不要用 argv0 白名單猜 shell 名稱。「agent 已退出」的判斷是 agent 本體 PID 找不到。
- **`herdr agent prompt <pane> /exit --wait` 會回 `agent_not_running` 錯誤**：prompt 送達後 agent 退出，wait 撲空。這是成功訊號，再驗證 agent PID 消失即可。
- **散裝 process 掃描只比對 argv0**：對 ps 的 args 全文做萬用字元比對，會被指令參數裡的文字誤觸（實測：`herdr agent prompt <pane> <訊息>` 的訊息內容含「claude/grok」就中招）。
- **macOS bash 3.2 + UTF-8**：`$var` 後緊貼全形標點（`）`、`、`）時，變數名稱解析會把多位元組字元吃進去，`set -u` 下炸 unbound variable。緊貼非 ASCII 的變數一律寫 `${var}`。
- `herdr pane release-agent` 只解除 agent 註冊、不停 process，不能用來釋放記憶體（#631 社群已證實）。
- 自身排除：herdr 列比對 `herdr pane current` 的 pane id；散裝列走祖先 PID 鏈（工具在 herdr 之外執行時 pane current 拿不到，祖先鏈也是後備）。
- 復原紀錄 `napped.tsv` 是累積式：連清多批會合併（同 pane 以最新為準），`--restore` 只把復原失敗的留在紀錄裡。
- **stub 必須是 pane shell 的子 process，不能 exec 取代 pane shell**：stub 內部再 `exec` 成 agent，agent 才會落在「pane shell 的直屬子 process」這個位置，下次清理它才不會連 pane 一起收掉。這個設計參考 [bengemine/herdr-hibernate](https://github.com/bengemine/herdr-hibernate)。
- **stub 待命時 pane 不在 shell prompt 上**，`herdr agent start` 會被拒絕，所以 `--restore` 對這種 pane 改送 `herdr pane send-keys <pane> enter`，讓 stub 自己 exec。
- **bash 3.2 的 `printf %q` 會把中文逐位元組轉成八進位跳脫**：產出的 stub 還能執行，但檔案完全不可讀。自己包單引號（`sq()`）即可。
- **「這個 session 回來了」只能靠 `herdr agent list` 的 `agent_session.value` 比對**：process 存在只證明同類 agent 在跑，可能是完全不同的 session。用 process 存在當復原成功，會把紀錄裡唯一的 session id 洗掉。
- **整份 `ps` 只拍一次快照**，找直屬子 process、RSS、etime、散裝行程都從同一份用 awk 取；需要當下狀態時（送出 `/exit` 或 resume 之後）再明確 refresh。先前每個 pane 掃一次全表，20 個 agent 就是 20 次。
- **bash 3.2 的 pipeline 裡 `while` 跑在 subshell**，裡面的 `return` 不會從函式返回，只會結束 subshell。helper 不要寫成 `ps | while ... return`。
- **ps 的 argv 看不到原本的引號**，含空白的旗標值拆成多個 token 後只會留第一個；裸位置參數一律丟掉，布林旗標後面跟著的位置參數也丟（靠已知布林旗標清單判斷，清單以空白或換行分隔，比對時兩種都要吃）。重播 argv 時要關 globbing，`--add-dir *` 這種值才不會被展開成檔名。
- **對話紀錄 jsonl 的 mtime 不能當閒置依據**：Claude Code 會回頭改寫閒置 session 的檔案（實測最後訊息 9/15 的檔案 mtime 是 9/18），全部 agent 都會顯示成幾十分鐘內活動過。要讀最後幾行裡最大的 `timestamp`（claude 是 ISO 8601 UTC，grok 是 epoch 秒），尾端可能有幾行沒 timestamp 的帳目列。
- **session 檔用 session id 直接 glob**，不要自己推 cwd 的編碼：claude 把 `/` 換成 `-`，grok 走 percent-encoding，而且 grok 的 code-review session 存在 `~/.grok/worktrees/...` 的編碼底下，跟 herdr 回報的 cwd 對不上。uuid 唯一，glob 一次就到。
- **`cut -f` 只會照升冪輸出欄位**，顯示順序就是資料欄順序，所以要顯示的欄位排前面、隱藏欄排後面；fzf 預覽窗用 `{3}` 取 pane，動欄位順序時要一起改。同一個欄位清單同時餵 `cut -f` 與 fzf `--with-nth`，只能用逗號列舉，cut 的 `1-10` fzf 不認（互動模式會直接失敗，`--list` 看不出來）。測試用 `fzf --filter` 非互動驗證這個表達式。
- **herdr 吃 pane 送出的 OSC 0 標題**（實測 `printf '\033]0;...\007'` 後 `herdr pane list` 的 `terminal_title` 跟著變）。但 zsh 每次回到 prompt 都會重設標題，所以只有停留在前景的 process 設的標題留得住；stub 一直卡在 `read` 上，剛好符合。側欄的 agents 區只列 herdr 認得的 agent，睡著的 pane 不會出現在那裡，這個標題目前只在 `herdr pane list` 看得到。
- **`herdr agent start` 的退出碼不能當復原成敗**：agent 啟動時卡在確認畫面（例如工作區信任），herdr 立刻回 `agent_not_ready` 非零，但 process 已經起來。成敗一律以 `herdr agent list` 回報的 session id 為準，blocked 另外提示。
- **非互動測試互動模式**：`FZF_DEFAULT_OPTS="--exact --filter=<pane>" herdr-nap <<< y` 會走完整的休眠流程（fzf 在 filter 模式不佔 TTY），適合對指定 pane 做端到端實測。
- 閒置的 claude agent 底下沒有常駐子行程（14 個實測子孫數 0），`/exit` 後也沒有留下孤兒 MCP process，所以不做 kill 整棵樹。子行程加總只影響 RSS 顯示與「子行程N」標記。

### 已知限制

- 按 Enter 就地復原時，agent 是由 stub 直接 `exec` 起來的，herdr 會用 agent 種類重新命名，原本 rename 過的 agent 名稱會遺失。走 `--restore` 則會帶回原名。
- working 狀態的 agent 也會列出（fzf header 有提醒），要不要清由使用者判斷。
- 閒置時間只支援 claude 與 grok，其他種類顯示 process 年齡並標「無對話紀錄」。
- revelio 的 llama-server（surya OCR，約 1.4 GB）是合法工作負載，不在本工具清單內，不要因為記憶體大就去殺它的宿主。

### 更名記錄

2026-08-24：`herdr-prune` 更名為 `herdr-nap`，專案資料夾 `herdr-mod` 一併改為 `herdr-nap`。

原名沿用自前身 `~/bin/claude-prune` 的後綴。prune 在 git 與 docker 的慣例裡指「清掉不需要的東西」，語意是刪除；本工具走 `/exit` 讓 agent 自行退出，對話留在 session 裡，`--restore` 隨時原地拉回，行為比較接近讓 agent 先睡一下。nap 貼近實際行為，也呼應 herdr 自己的 parked pane 說法。

同時更名：`~/bin/herdr-nap`（symlink）、狀態目錄 `~/.local/state/herdr-nap/`、復原紀錄 `napped.tsv`（原 `last-prune.tsv`）、GitHub repo。舊的 `~/bin/claude-prune` 不受影響，仍然並存。
