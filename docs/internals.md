# herdr-nap internals

Maintainer notes: what was measured, and every trap hit along the way. The README only covers install and usage.

[English](#english) | [繁體中文](#繁體中文)

# English

## Development

Plugin work: `herdr plugin link ~/herdr-nap` registers the working tree (no build step); `herdr plugin unlink clementtang.herdr-nap` removes it. The picker needs a TTY for fzf, so all three entry points are `[[panes]]` and each action only calls `herdr plugin pane open`. Pane commands run with the user's cwd, so scripts go through `$HERDR_PLUGIN_ROOT` and herdr through `$HERDR_BIN_PATH`.

Once per clone (`core.hooksPath` is local config):

```
git config core.hooksPath githooks
```

`githooks/pre-commit` rejects a bash variable directly followed by a non-ASCII character (see the bash 3.2 note below).

Tests are pure-function tests on the stock bash 3.2, no bats:

```
tests/run-tests.sh
```

`HERDR_NAP_LIB_ONLY=1 source herdr-nap` loads only the functions. End-to-end on one pane without a TTY: `FZF_DEFAULT_OPTS="--exact --filter=<pane>" herdr-nap <<< y`.

## What happens after a herdr server restart (measured, 2026-09-18)

- herdr's persisted `~/.config/herdr/session.json` stores only cwd per pane, plus `agent_session` when an agent is present. Napped panes (stub waiting or back at a shell) have no `agent_session`.
- Panes napped on 8/26 and 9/4 went through restarts on 9/1 and 9/9: same pane id (session.json keeps a `public_pane_numbers` map), same cwd, empty shell, stub gone, no agent relaunched.
- So a restart does not bring napped agents back to eat memory; you only lose the in-pane Enter shortcut. `--restore` already handles panes at a shell prompt through `herdr agent start`, so no shell hook is needed.
- herdr relaunches live agents with plain `claude --resume <uuid>`, dropping their original flags. That is herdr's behaviour, outside this tool's reach.
- For experiments that need an isolated server, use a named session (`herdr --session <name>`: separate directory and socket, the CLI follows `HERDR_SOCKET_PATH`) instead of restarting the main one.

## Implementation notes (lessons learned)

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
- **`IFS=$'\t' read` collapses consecutive tabs** (tab is IFS whitespace), so an empty middle field shifts every later field. `record_line` writes `-` for empty fields and readers map `-` back to empty. `awk -F'\t'` does not have this problem, which is why the merge and removal helpers use awk.
- **Write the record before arming the stub, one record at a time**. Batching records until the end meant any failure after `/exit` (a failed `herdr pane run`, Ctrl-C, a jq error) lost every session id already put to sleep. `upsert_record` runs right after the PID is confirmed gone; the stub is only the Enter shortcut. `herdr pane run` failures are reported, not fatal.
- **`napped.tsv` is guarded by a mkdir lock** (`.lock` in the state dir, macOS has no flock). nap and `--restore` can run at the same time from two plugin overlays; `--restore` never rewrites the whole file, it only removes the panes it restored, so lines added meanwhile survive. A lock older than a minute is treated as left behind.
- **Re-check before acting**: the list is a snapshot and the user may sit in fzf for a long time. Before `/exit`, the pane's current session id must still match the row; before SIGTERM, the PID must still be a claude/grok outside the herdr tree. Anything that changed is skipped with a message.
- **The fzf preview runs in another shell**, so the `herdr` wrapper function is not there; the preview command embeds `$HERDR_BIN` explicitly or the plugin build shows an empty preview.
- **`date -j` is macOS only**; Linux falls back to `date -d`. Transcript paths may contain spaces (claude only replaces `/`), so file lists are passed one per line, never through an unquoted `$( )`.
- **Testing the interactive mode without a TTY**: `FZF_DEFAULT_OPTS="--exact --filter=<pane>" herdr-nap <<< y` runs the full nap flow (fzf in filter mode does not need a terminal), handy for end-to-end tests on one pane.
- Idle claude agents have no long-lived children (14 measured, zero descendants) and `/exit` leaves no orphaned MCP process, so the tool never kills a process tree. Descendant sums only affect the RSS column and the child-process marker.
- **"Outside herdr" cannot be decided by `herdr agent list` alone**: a claude/grok can run inside a herdr pane while herdr has not registered it as an agent (a stub resumed into a trust prompt, a failed resume, or a detection lag). Every pane shell is a direct child of the `herdr server` process, so an in-pane agent has herdr server as an ancestor; a genuinely external one does not. The stray-process loop walks the ancestor chain: anything under herdr server is listed as source `herdr?` with the note `unregistered`, stays visible, and is left alone when picked (no /exit is possible, SIGTERM would destroy the pane's resume path).

# 繁體中文

## 開發

plugin：`herdr plugin link ~/herdr-nap` 掛上工作目錄（不跑 build），`herdr plugin unlink clementtang.herdr-nap` 移除。互動挑選要 fzf 佔 TTY，所以三個入口都是 `[[panes]]`，action 只負責 `herdr plugin pane open`。pane 的 cwd 是使用者的工作目錄，腳本路徑走 `$HERDR_PLUGIN_ROOT`，呼叫 herdr 走 `$HERDR_BIN_PATH`。

新 clone 跑一次（`core.hooksPath` 是本機 config）：

```
git config core.hooksPath githooks
```

`githooks/pre-commit` 會擋下變數緊貼非 ASCII 字元的寫法（見下方 bash 3.2 那條）。

測試是純函式測試，內建 bash 3.2 直接跑，不用 bats：

```
tests/run-tests.sh
```

`HERDR_NAP_LIB_ONLY=1 source herdr-nap` 只載入函式。對單一 pane 做無 TTY 的端到端測試：`FZF_DEFAULT_OPTS="--exact --filter=<pane>" herdr-nap <<< y`。

## herdr server 重啟後會怎樣（實測，2026-09-18）

- herdr 的持久化檔 `~/.config/herdr/session.json` 對每個 pane 只存 cwd，pane 上有 agent 時才多存 `agent_session`。已休眠的 pane（不論 stub 待命中或已回 shell）沒有 `agent_session`。
- 8/26 與 9/4 休眠的 pane 經過 9/1、9/9 兩次重啟後：pane id 不變（session.json 有 `public_pane_numbers` 對照表）、cwd 不變、變成空 shell、stub 消失、agent 沒有被拉起。
- 所以重啟不會讓休眠的 agent 回來吃記憶體，只會失去 pane 裡按 Enter 的捷徑；`--restore` 對停在 shell prompt 的 pane 本來就走 `herdr agent start`，不需要 shell hook，也不動 `.zshrc`。
- herdr 自己重啟時拉起活著的 agent 用的是 `claude --resume <uuid>`，原本的啟動旗標一樣會掉。這是 herdr 的行為，本工具管不到。
- 需要隔離的 herdr server 做實驗時，用具名 session（`herdr --session <name>`，獨立目錄與 socket，CLI 靠 `HERDR_SOCKET_PATH` 指向），不要重啟主 server。

## 實作要點（踩過的坑）

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
- **`IFS=$'\t' read` 會把連續 tab 合併**（tab 是 IFS 空白），中間有空欄後面全部位移。`record_line` 對空欄寫 `-`，讀回時轉回空字串；`awk -F'\t'` 沒這個問題，合併與刪除 helper 因此用 awk。
- **先寫紀錄再種 stub，逐筆落地**。原本整批處理完才寫檔，`/exit` 之後任何一步失敗（`herdr pane run` 非零、Ctrl-C、jq 出錯）都會弄丟已經睡掉的 session id。現在確認 PID 消失就 `upsert_record`，stub 只是按 Enter 的捷徑；`herdr pane run` 失敗只回報不中止。
- **`napped.tsv` 有 mkdir 鎖**（狀態目錄的 `.lock`，macOS 沒有 flock）。nap 與 `--restore` 可能從兩個 plugin overlay 同時跑；`--restore` 不再重寫整檔，只刪它復原成功的 pane，期間別人新寫的列保得住。超過一分鐘沒動的鎖視為殘留。
- **動手前重核對**：清單是快照，使用者可能在 fzf 裡停很久。送 `/exit` 前 pane 上的 session id 必須仍等於該列；送 SIGTERM 前 PID 仍必須是 herdr 樹外的 claude/grok。變了就略過並明講。
- **fzf 預覽窗跑在另一個 shell**，看不到 `herdr` 包裝函式；預覽指令要把 `$HERDR_BIN` 直接嵌進去，否則 plugin 環境預覽一片空白。
- **`date -j` 只有 macOS 有**，Linux 退回 `date -d`。對話紀錄路徑可能含空白（claude 只把 `/` 換掉），檔名清單一行一個傳遞，不走未加引號的 `$( )`。
- **非互動測試互動模式**：`FZF_DEFAULT_OPTS="--exact --filter=<pane>" herdr-nap <<< y` 會走完整的休眠流程（fzf 在 filter 模式不佔 TTY），適合對指定 pane 做端到端實測。
- 閒置的 claude agent 底下沒有常駐子行程（14 個實測子孫數 0），`/exit` 後也沒有留下孤兒 MCP process，所以不做 kill 整棵樹。子行程加總只影響 RSS 顯示與「子行程N」標記。
- **「herdr 之外」不能只看 `herdr agent list`**：claude/grok 可能人在 herdr pane 裡，herdr 卻沒把它辨識成 agent（stub resume 後卡在信任確認、resume 失敗、或偵測延遲）。每個 pane shell 都是 `herdr server` 的直屬子行程，所以 pane 內的 agent 祖先鏈一定含 herdr server，真正外部直開的則沒有。散裝 process 迴圈追祖先鏈，凡在 herdr server 底下的列成來源 `herdr?`、備註「herdr未辨識」，照樣看得到，勾了也不動它（無法 /exit，SIGTERM 會毀掉 pane 的復原路徑）。

## 更名記錄

2026-08-24：`herdr-prune` 更名為 `herdr-nap`，專案資料夾 `herdr-mod` 一併改為 `herdr-nap`。

原名沿用自前身 `~/bin/claude-prune` 的後綴。prune 在 git 與 docker 的慣例裡指「清掉不需要的東西」，語意是刪除；本工具走 `/exit` 讓 agent 自行退出，對話留在 session 裡，`--restore` 隨時原地拉回，行為比較接近讓 agent 先睡一下。nap 貼近實際行為，也呼應 herdr 自己的 parked pane 說法。

同時更名：`~/bin/herdr-nap`（symlink）、狀態目錄 `~/.local/state/herdr-nap/`、復原紀錄 `napped.tsv`（原 `last-prune.tsv`）、GitHub repo。舊的 `~/bin/claude-prune` 不受影響，仍然並存。
