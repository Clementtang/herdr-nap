# Changelog

格式依 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)，未發版的變更放在 Unreleased。

## [Unreleased]

### Added

- 復原時重播原本的啟動旗標（例如 `--dangerously-skip-permissions`）。休眠紀錄 `napped.tsv` 新增第 6 欄 argv，舊的 5 欄紀錄相容。
- `--restore` 遇到 pane 已不存在的紀錄時明講，並給出開新 pane 復原的指令；紀錄保留。
- 清單新增「閒置」欄並依它排序，取對話紀錄最後一筆的 timestamp（不用檔案 mtime，Claude Code 會回頭改寫閒置 session 的檔案）。
- 新增「備註」欄：子行程數、subagent 活動中、剛啟動、無對話紀錄。只標記不擋。
- fzf 預覽窗顯示游標所在 pane 的目前畫面，Ctrl-/ 切換。
- `tests/run-tests.sh`：純函式測試，不依賴 bats。腳本支援 `HERDR_NAP_LIB_ONLY=1` 只載入函式。
- `--restore` 偵測 agent 起來後卡在確認畫面（herdr 回報 blocked）的狀態並明講，不再誤報失敗或成功。

### Fixed

- fzf `--with-nth` 不吃 `1-10` 範圍寫法，互動模式在欄位重排後會直接失敗（實測 w1:pB 端到端時抓到）。改回逗號列舉並加測試。

### Changed

- RSS 改為整棵 process 樹（agent 本體加所有子孫）的合計，stub 橫幅的「釋放」數字一併修正。

### Docs

- 記錄 herdr server 重啟後休眠 pane 的實際行為（agent 不會被拉起、pane id 不變、stub 消失），以及用具名 session 做隔離實驗的方法。

## 2026-08-24

- `herdr-prune` 更名為 `herdr-nap`（見 README 更名記錄）。

## 2026-08-21

- 首版：fzf 挑選、`/exit` 休眠、pane 內 stub 按 Enter 復原、`--restore` 整批復原、以 session id 驗證復原成功。
