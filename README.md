# herdr-nap

herdr 原生的 agent 清理工具。herdr 的 session persistence 會在 server 啟動時把所有 parked pane 的 agent 批次拉活且永不釋放（實測 14 個 `claude --resume` 同秒 spawn、閒置一天約 2 GB），官方沒有 hibernate 功能（Discussion #631 未實作）。`herdr-nap` 提供手動、互動挑選式的清理，是 `~/bin/claude-prune` 的 herdr 升級版。

## 用法

```
herdr-nap            互動挑選（TAB 多選、Enter 清理、Esc 取消）
herdr-nap --list     只列出，不清理
herdr-nap --restore  復原先前清理掉的 herdr agent
```

- 清單依**閒置時間**排序，閒置最久的在最上面。閒置取對話紀錄最後一筆的 timestamp（claude 讀 `~/.claude/projects/*/<session>.jsonl` 與其 `subagents/*.jsonl`，grok 讀 `~/.grok/sessions/*/<session>/updates.jsonl`），不是 process 年齡，resume 過的舊 session 不會顯示成很新。RSS 是整棵 process 樹（含 MCP 與工具子行程）的合計。備註欄標記「子行程N」「subagent活動中」「剛啟動」「無對話紀錄」，只標記不擋。
- fzf 下方有預覽窗，顯示游標所在 pane 的目前畫面（`herdr pane read --source visible`），Ctrl-/ 切換。
- **釘選排除**：`~/.config/herdr-nap/exclude` 一行一個字樣（`#` 開頭是註解），pane 標題或 tab 標籤含該字樣的 agent 不進 fzf 清單，連誤點的機會都沒有；`--list` 仍列出，備註標「釘選」並灰顯（輸出到終端時才上色）。用字樣不用 pane id 或 tab id，因為 id 在 workspace 關開後會變。
- herdr 管的 agent（claude、grok 等）走 `herdr agent prompt <pane> /exit` 請它自行退出：process 結束、pane 保留、herdr 狀態同步。已實測 claude 與 grok 都吃 `/exit`。
- 休眠後 pane 裡會留一個待命 stub，顯示釋放了多少記憶體與 session id，**按 Enter 就地復原**、Ctrl-C 回到一般 shell。整批復原走 `--restore`，對 stub 待命中的 pane 送 Enter，對已回到 shell prompt 的 pane 走 `herdr agent start <name> --kind <kind> --pane <pane> -- <原啟動旗標> --resume <session-id>`。兩條路都不遺失對話。
- **復原時帶回原本的啟動旗標**（例如 `--dangerously-skip-permissions`、`--model`）。休眠時從 ps 取 agent 的 argv，去掉 `--resume`/`-r`/`-c`/`--session-id`/`--fork-session` 這類接續 session 的旗標與裸位置參數（多半是啟動 prompt，重播會被當成新訊息），其餘存進紀錄第 6 欄。舊的 5 欄紀錄照常可讀，argv 視為空。
- pane 已經被關掉（或整個 workspace 沒了）的紀錄，`--restore` 會明講「已不存在」並給開新 pane 復原的指令，紀錄保留。
- 復原不一定全自動：實測 `claude --dangerously-skip-permissions --resume` 起來後會先跳「工作區信任」確認畫面，herdr 回報 blocked。兩條復原路徑都會偵測這個狀態並提示到該 pane 回答，紀錄保留到 session 真的回來為止。工具不會替你回答任何確認畫面。
- 自己在 pane 裡按 Enter 復原之後不必收拾，下次執行時過期紀錄與 stub 檔會自動清掉。判斷依據是 herdr 回報的 session id 與紀錄相符，**不是**「這個 pane 有同類 agent 在跑」。
- pane 已經被別的 session 佔用時不會當成復原成功：報告衝突、紀錄留著，並附上換 pane 復原的指令。休眠中的 session id 只存在紀錄裡，刪掉就再也找不回來。
- herdr 沒有回報 session id 的 agent，退出後不寫紀錄也不留 stub，並明講這個對話無法自動復原。
- herdr 之外直開的 claude / grok 維持 SIGTERM fallback，`claude --resume` 可復原。
- 防呆：排除自身 pane、清理前 y/N 確認、逐一驗證退出並回報、復原紀錄存 `~/.local/state/herdr-nap/napped.tsv`、stub 存 `~/.local/state/herdr-nap/panes/`。
- `--list` 是唯讀模式，不動狀態檔；依賴檢查按 mode 做，沒裝 fzf 仍能 `--list` 與 `--restore`。

安裝方式：`~/bin/herdr-nap` symlink 到本專案的 `herdr-nap`，改這裡即生效。

開發環境（新 clone 或換機器時要跑一次，`core.hooksPath` 是本機 config，不跟著 repo 走）：

```
git config core.hooksPath githooks
```

`githooks/pre-commit` 會擋下 bash 腳本裡變數緊貼非 ASCII 字元的寫法（見下方實作要點最後一項）。

測試（純函式，不依賴 bats，內建 bash 3.2 直接跑）：

```
tests/run-tests.sh
```

腳本用 `HERDR_NAP_LIB_ONLY=1 source herdr-nap` 只載入函式，主流程不會執行。測試涵蓋旗標重播、紀錄格式與合併、單引號包裝、閒置時間解析、子孫 RSS 加總與風險標記。

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
- **`herdr agent start` 的退出碼不能當復原成敗**：agent 啟動時卡在確認畫面（例如工作區信任），herdr 立刻回 `agent_not_ready` 非零，但 process 已經起來。成敗一律以 `herdr agent list` 回報的 session id 為準，blocked 另外提示。
- **非互動測試互動模式**：`FZF_DEFAULT_OPTS="--exact --filter=<pane>" herdr-nap <<< y` 會走完整的休眠流程（fzf 在 filter 模式不佔 TTY），適合對指定 pane 做端到端實測。
- 閒置的 claude agent 底下沒有常駐子行程（14 個實測子孫數 0），`/exit` 後也沒有留下孤兒 MCP process，所以不做 kill 整棵樹。子行程加總只影響 RSS 顯示與「子行程N」標記。

## 已知限制

- 按 Enter 就地復原時，agent 是由 stub 直接 `exec` 起來的，herdr 會用 agent 種類重新命名，原本 rename 過的 agent 名稱會遺失。走 `--restore` 則會帶回原名。
- working 狀態的 agent 也會列出（fzf header 有提醒），要不要清由使用者判斷。
- revelio 的 llama-server（surya OCR，約 1.4 GB）是合法工作負載，不在本工具清單內，不要因為記憶體大就去殺它的宿主。

## 更名記錄

2026-08-24：`herdr-prune` 更名為 `herdr-nap`，專案資料夾 `herdr-mod` 一併改為 `herdr-nap`。

原名沿用自前身 `~/bin/claude-prune` 的後綴。prune 在 git 與 docker 的慣例裡指「清掉不需要的東西」，語意是刪除；本工具走 `/exit` 讓 agent 自行退出，對話留在 session 裡，`--restore` 隨時原地拉回，行為比較接近讓 agent 先睡一下。nap 貼近實際行為，也呼應 herdr 自己的 parked pane 說法。

同時更名：`~/bin/herdr-nap`（symlink）、狀態目錄 `~/.local/state/herdr-nap/`、復原紀錄 `napped.tsv`（原 `last-prune.tsv`）、GitHub repo。舊的 `~/bin/claude-prune` 不受影響，仍然並存。
