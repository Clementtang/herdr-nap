# Changelog

格式依 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)，未發版的變更放在 Unreleased。

## [Unreleased]

### Docs

- 記錄 herdr server 重啟後休眠 pane 的實際行為（agent 不會被拉起、pane id 不變、stub 消失），以及用具名 session 做隔離實驗的方法。

## 2026-08-24

- `herdr-prune` 更名為 `herdr-nap`（見 README 更名記錄）。

## 2026-08-21

- 首版：fzf 挑選、`/exit` 休眠、pane 內 stub 按 Enter 復原、`--restore` 整批復原、以 session id 驗證復原成功。
