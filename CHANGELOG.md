# Changelog

格式依 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)，未發版的變更放在 Unreleased。

## [Unreleased]

### Docs

- README 精簡成安裝、用法、限制；實測數據、實作要點、開發設定原文搬到 `docs/internals.md`。

## [0.2.1] - 2026-09-19

### Fixed

- Grok 第二輪審查（反對者立場）抓到的問題：
  - `/exit` 後紀錄要到整批結束才寫檔，中途失敗會弄丟已睡掉的 session id。改成確認退出後立刻逐筆寫入，stub 種不起來只回報。
  - 送 `/exit` 前沒重讀 pane 當下的 session；fzf 停留期間換人會請走別的 session。改成動手前重核對，變了就略過。
  - `IFS=tab read` 會合併連續 tab，紀錄中間空欄會讓後面欄位位移。空欄改寫 `-`。
  - `napped.tsv` 沒有鎖，nap 與 `--restore` 同時跑會互相蓋檔。加 mkdir 鎖，`--restore` 改成只刪復原成功的 pane。
  - SIGTERM 前沒確認 PID 仍是當初那個 claude/grok。改成 kill 前重認 argv0 與 herdr 樹。
  - fzf 預覽窗用字面 `herdr`，plugin 環境找不到。改嵌 `$HERDR_BIN`。
  - Linux 沒有 `date -j`，閒置時間會退回 process 年齡。加 `date -d` 後備。
  - 對話紀錄路徑含空白時 glob 結果被切開。改逐行傳遞。
- 在 herdr pane 裡但 herdr 尚未辨識成 agent 的 claude/grok（例如 stub resume 後卡在信任確認、或偵測延遲）不再被誤判成「herdr 之外」而列進 SIGTERM 清單。改以「祖先鏈是否含 herdr server」判斷，這種 process 列成來源 `herdr?`、備註「herdr未辨識」，勾了也不動它。
- `--list` 與確認清單裡空欄位會被 `column -t` 吞掉、後面欄位往前擠；顯示前補成 `-`。

### Added

- 前景是 `ssh`/`mosh` 的 pane 列成來源 `remote`（唯讀），提示 agent 在另一台機器上。
- 英文訊息。依 `LC_ALL`/`LC_MESSAGES`/`LANG` 判斷，`zh` 開頭顯示繁體中文，其餘英文；`HERDR_NAP_LANG` 可強制。訊息集中成 `msg_zh`、`msg_en` 兩張表，測試比對 key 一致。

## [0.2.0] - 2026-09-18

### Added

- 復原時重播原本的啟動旗標（例如 `--dangerously-skip-permissions`）。休眠紀錄 `napped.tsv` 新增第 6 欄 argv，舊的 5 欄紀錄相容。
- `--restore` 遇到 pane 已不存在的紀錄時明講，並給出開新 pane 復原的指令；紀錄保留。
- 清單新增「閒置」欄並依它排序，取對話紀錄最後一筆的 timestamp（不用檔案 mtime，Claude Code 會回頭改寫閒置 session 的檔案）。
- 新增「備註」欄：子行程數、subagent 活動中、剛啟動、無對話紀錄。只標記不擋。
- fzf 預覽窗顯示游標所在 pane 的目前畫面，Ctrl-/ 切換。
- `tests/run-tests.sh`：純函式測試，不依賴 bats。腳本支援 `HERDR_NAP_LIB_ONLY=1` 只載入函式。
- stub 待命時把終端標題設成 `[nap] 原標題`（OSC 跳脫序列，不動 herdr tab 名，復原後自然蓋掉）。
- `herdr-plugin.toml`：可用 `herdr plugin install Clementtang/herdr-nap` 安裝，三個 overlay pane 入口（挑選、復原、清單）加對應 action。腳本改走 `HERDR_BIN_PATH` 呼叫 herdr，plugin 環境下 PATH 沒有 herdr 也能跑。
- 釘選排除：`~/.config/herdr-nap/exclude` 的字樣比對 pane 標題與 tab 標籤，命中的 agent 不進 fzf 清單，`--list` 灰顯並標「釘選」。
- `--restore` 偵測 agent 起來後卡在確認畫面（herdr 回報 blocked）的狀態並明講，不再誤報失敗或成功。

### Fixed

- fzf `--with-nth` 不吃 `1-10` 範圍寫法，互動模式在欄位重排後會直接失敗（實測 w1:pB 端到端時抓到）。改回逗號列舉並加測試。

### Changed

- RSS 改為整棵 process 樹（agent 本體加所有子孫）的合計，stub 橫幅的「釋放」數字一併修正。

### Docs

- MIT 授權、README 改中英雙語並加 badge。
- 記錄 herdr server 重啟後休眠 pane 的實際行為（agent 不會被拉起、pane id 不變、stub 消失），以及用具名 session 做隔離實驗的方法。

## 2026-08-24

- `herdr-prune` 更名為 `herdr-nap`（見 README 更名記錄）。

## 2026-08-21

- 首版：fzf 挑選、`/exit` 休眠、pane 內 stub 按 Enter 復原、`--restore` 整批復原、以 session id 驗證復原成功。
