# herdr-mod

herdr 原生的 agent 清理工具。herdr 的 session persistence 會在 server 啟動時把所有 parked pane 的 agent 批次拉活且永不釋放（實測 14 個 `claude --resume` 同秒 spawn、閒置一天約 2 GB），官方沒有 hibernate 功能（Discussion #631 未實作）。`herdr-prune` 提供手動、互動挑選式的清理，是 `~/bin/claude-prune` 的 herdr 升級版。

## 用法

```
herdr-prune            互動挑選（TAB 多選、Enter 清理、Esc 取消）
herdr-prune --list     只列出，不清理
herdr-prune --restore  復原上一次清理掉的 herdr agent
```

- herdr 管的 agent（claude、grok 等）走 `herdr agent prompt <pane> /exit` 請它自行退出：process 結束、pane 保留、herdr 狀態同步，之後 `--restore` 用 `herdr agent start --kind <kind> --pane <pane> -- --resume <session-id>` 原地復原，對話不遺失。已實測 claude 與 grok 都吃 `/exit`。
- herdr 之外直開的 claude / grok 維持 SIGTERM fallback，`claude --resume` 可復原。
- 防呆：排除自身 pane、清理前 y/N 確認、逐一驗證退出並回報、復原紀錄存 `~/.local/state/herdr-prune/last-prune.tsv`。

安裝方式：`~/bin/herdr-prune` symlink 到本專案的 `herdr-prune`，改這裡即生效。

## 實作要點（踩過的坑）

- **agent PID 要從 pane shell 的直屬子 process 找**，指令是 `herdr pane process-info --pane <id>` 拿 `shell_pid` 再對 `ps` 的 ppid。它回傳的 `foreground_processes` 在 agent 跑工具時會是孫層子 process，PID 與 RSS 都會拿錯，還會讓本體被誤判成 herdr 之外的 process。
- **`herdr api snapshot`** 的 `agents[]` 給 agent 種類、`agent_status`（idle / working / done / unknown）、`pane_id`、`cwd`、`agent_session.value`（resume 用的 session id）、terminal title；沒有 PID。
- **`herdr agent prompt <pane> /exit --wait` 會回 `agent_not_running` 錯誤**：prompt 送達後 agent 退出，wait 撲空。這是成功訊號，要再用 process-info 驗證 pane 前景回到 shell。
- **macOS bash 3.2 + UTF-8**：`$var` 後緊貼全形標點（`）`、`、`）時，變數名稱解析會把多位元組字元吃進去，`set -u` 下炸 unbound variable。緊貼非 ASCII 的變數一律寫 `${var}`。
- `herdr pane release-agent` 只解除 agent 註冊、不停 process，不能用來釋放記憶體（#631 社群已證實）。

## 已知限制

- working 狀態的 agent 也會列出（fzf header 有提醒），要不要清由使用者判斷。
- revelio 的 llama-server（surya OCR，約 1.4 GB）是合法工作負載，不在本工具清單內，不要因為記憶體大就去殺它的宿主。
