# herdr-nap

herdr 原生的 agent 清理工具。herdr 的 session persistence 會在 server 啟動時把所有 parked pane 的 agent 批次拉活且永不釋放（實測 14 個 `claude --resume` 同秒 spawn、閒置一天約 2 GB），官方沒有 hibernate 功能（Discussion #631 未實作）。`herdr-nap` 提供手動、互動挑選式的清理，是 `~/bin/claude-prune` 的 herdr 升級版。

## 用法

```
herdr-nap            互動挑選（TAB 多選、Enter 清理、Esc 取消）
herdr-nap --list     只列出，不清理
herdr-nap --restore  復原先前清理掉的 herdr agent
```

- herdr 管的 agent（claude、grok 等）走 `herdr agent prompt <pane> /exit` 請它自行退出：process 結束、pane 保留、herdr 狀態同步。已實測 claude 與 grok 都吃 `/exit`。
- 休眠後 pane 裡會留一個待命 stub，顯示釋放了多少記憶體與 session id，**按 Enter 就地復原**、Ctrl-C 回到一般 shell。整批復原走 `--restore`，對 stub 待命中的 pane 送 Enter，對已回到 shell prompt 的 pane 走 `herdr agent start <name> --kind <kind> --pane <pane> -- --resume <session-id>`。兩條路都不遺失對話。
- 自己在 pane 裡按 Enter 復原之後不必收拾，下次執行時過期紀錄與 stub 檔會自動清掉。
- herdr 之外直開的 claude / grok 維持 SIGTERM fallback，`claude --resume` 可復原。
- 防呆：排除自身 pane、清理前 y/N 確認、逐一驗證退出並回報、復原紀錄存 `~/.local/state/herdr-nap/napped.tsv`、stub 存 `~/.local/state/herdr-nap/panes/`。

安裝方式：`~/bin/herdr-nap` symlink 到本專案的 `herdr-nap`，改這裡即生效。

開發環境（新 clone 或換機器時要跑一次，`core.hooksPath` 是本機 config，不跟著 repo 走）：

```
git config core.hooksPath githooks
```

`githooks/pre-commit` 會擋下 bash 腳本裡變數緊貼非 ASCII 字元的寫法（見下方實作要點最後一項）。

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

## 已知限制

- 按 Enter 就地復原時，agent 是由 stub 直接 `exec` 起來的，herdr 會用 agent 種類重新命名，原本 rename 過的 agent 名稱會遺失。走 `--restore` 則會帶回原名。
- working 狀態的 agent 也會列出（fzf header 有提醒），要不要清由使用者判斷。
- revelio 的 llama-server（surya OCR，約 1.4 GB）是合法工作負載，不在本工具清單內，不要因為記憶體大就去殺它的宿主。

## 更名記錄

2026-08-24：`herdr-prune` 更名為 `herdr-nap`，專案資料夾 `herdr-mod` 一併改為 `herdr-nap`。

原名沿用自前身 `~/bin/claude-prune` 的後綴。prune 在 git 與 docker 的慣例裡指「清掉不需要的東西」，語意是刪除；本工具走 `/exit` 讓 agent 自行退出，對話留在 session 裡，`--restore` 隨時原地拉回，行為比較接近讓 agent 先睡一下。nap 貼近實際行為，也呼應 herdr 自己的 parked pane 說法。

同時更名：`~/bin/herdr-nap`（symlink）、狀態目錄 `~/.local/state/herdr-nap/`、復原紀錄 `napped.tsv`（原 `last-prune.tsv`）、GitHub repo。舊的 `~/bin/claude-prune` 不受影響，仍然並存。
