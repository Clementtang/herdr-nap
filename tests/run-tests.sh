#!/bin/bash
# herdr-nap 純函式測試。不依賴 bats，macOS 內建 bash 3.2 直接跑：
#   tests/run-tests.sh
# 每個測試是一個 test_* 函式，名稱用 should_<行為>_when_<條件>。
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
export HERDR_NAP_LIB_ONLY=1
export HERDR_NAP_LANG=zh   # 既有測試以中文訊息為準；英文另有專門測試
# shellcheck source=../herdr-nap
. "$HERE/../herdr-nap"
set +e

pass=0; fail=0
assert_eq() {
  local expected=$1 actual=$2 label=${3:-}
  if [ "$expected" = "$actual" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s %s\n  預期: [%s]\n  實際: [%s]\n' "${FUNCNAME[1]}" "$label" "$expected" "$actual"
  fi
}

# ---------- replay_flags ----------
test_should_keep_boolean_flag_when_resume_has_no_value() {
  assert_eq "--dangerously-skip-permissions" \
    "$(replay_flags "claude --dangerously-skip-permissions --resume")"
}
test_should_drop_resume_value_when_it_is_a_session_name() {
  assert_eq "--dangerously-skip-permissions" \
    "$(replay_flags "claude --dangerously-skip-permissions --resume 91app-map-dashboard-dev-0909")"
}
test_should_return_empty_when_only_resume_uuid_given() {
  assert_eq "" "$(replay_flags "claude --resume 50b047c7-9a04-46b6-b0b5-ca4a0a6bffda")"
}
test_should_return_empty_when_argv_is_bare_command() {
  assert_eq "" "$(replay_flags "claude")"
  assert_eq "" "$(replay_flags "")" "空字串"
}
test_should_keep_value_flags_and_drop_positional_prompt() {
  assert_eq "--model opus --dangerously-skip-permissions" \
    "$(replay_flags "/opt/homebrew/bin/claude -r abc --model opus --dangerously-skip-permissions fix the bug")"
}
test_should_drop_all_session_flags_when_mixed_forms_used() {
  assert_eq "--permission-mode plan" \
    "$(replay_flags "claude --resume=abc -c --fork-session --permission-mode plan")"
  assert_eq "--model x" "$(replay_flags "claude --session-id=abc --teleport --from-pr 12 --model x")" "teleport/from-pr"
}
test_should_handle_grok_short_session_flag() {
  assert_eq "--always-approve --model grok-4 --reasoning-effort high" \
    "$(replay_flags "grok -s 01a0 --always-approve --model grok-4 --reasoning-effort high")"
}
test_should_drop_positional_after_boolean_flag() {
  assert_eq "--dangerously-skip-permissions" \
    "$(replay_flags "claude --dangerously-skip-permissions do something")"
}
test_should_not_glob_expand_tokens() {
  local out
  out=$(cd "$HERE" && replay_flags "claude --add-dir * --bg")
  assert_eq "--add-dir * --bg" "$out"
}
test_should_keep_equals_form_value_flags() {
  assert_eq "--model=opus --bg" "$(replay_flags "claude --model=opus --bg")"
}
test_should_treat_every_listed_boolean_flag_as_boolean() {
  # 清單裡每一個旗標（含各行行尾那個）後面接的位置參數都要被丟掉
  local flag
  for flag in $BOOLEAN_FLAGS; do
    assert_eq "$flag" "$(replay_flags "claude $flag 幫我修 bug")" "$flag"
  done
}
test_should_not_leak_glob_setting_to_caller() {
  local before after
  before=$-; replay_flags "claude --add-dir * --bg" >/dev/null; after=$-
  assert_eq "$before" "$after" default-state
  set -f; replay_flags "claude --bg" >/dev/null
  case $- in *f*) assert_eq 1 1 ;; *) assert_eq "f kept" "f dropped" ;; esac
  set +f
}

# ---------- restore_hint ----------
test_should_place_argv_before_resume_when_argv_present() {
  assert_eq "herdr agent start rev --kind claude --pane w1:p1 -- --dangerously-skip-permissions --resume SID" \
    "$(restore_hint w1:p1 claude rev SID "--dangerously-skip-permissions")"
}
test_should_omit_argv_when_empty() {
  assert_eq "herdr agent start claude --kind claude --pane w1:p1 -- --resume SID" \
    "$(restore_hint w1:p1 claude claude SID "")"
}

# ---------- sq ----------
test_should_single_quote_plain_string() {
  assert_eq "'abc'" "$(sq abc)"
}
test_should_escape_embedded_single_quote() {
  assert_eq "'it'\\''s'" "$(sq "it's")"
}
test_should_keep_cjk_readable_when_quoting() {
  assert_eq "'已休眠，釋放 100MB'" "$(sq "已休眠，釋放 100MB")"
}
test_should_round_trip_through_eval() {
  local s="a b'c\$d\`e*?"
  eval "local back=$(sq "$s")"
  assert_eq "$s" "$back"
}

# ---------- record_line / 舊紀錄相容 ----------
test_should_write_six_tab_fields() {
  assert_eq $'w1:p1\tclaude\tname\tSID\t/tmp\t--bg' "$(record_line w1:p1 claude name SID /tmp --bg)"
}
test_should_write_dash_for_empty_fields_so_read_does_not_shift() {
  # bash 的 IFS=tab read 會合併連續 tab，空欄不補 - 整列就位移
  local pane kind name session cwd argv
  IFS=$'\t' read -r pane kind name session cwd argv <<< "$(record_line w1:p1 claude claude SID "" --bg)"
  assert_eq "SID" "$session" session
  assert_eq "" "$(undash "$cwd")" cwd-empty
  assert_eq "--bg" "$(undash "$argv")" argv
  assert_eq "" "$(undash -)" undash-dash
  assert_eq "/x" "$(undash /x)" undash-plain
}
test_should_read_old_five_field_record_with_empty_argv() {
  local pane kind name session cwd argv
  IFS=$'\t' read -r pane kind name session cwd argv <<< $'w1:p1\tclaude\tclaude\tSID\t/tmp'
  assert_eq "/tmp" "$cwd" cwd
  assert_eq "" "$argv" argv
}
with_temp_state() {   # 讓紀錄相關函式寫到暫存目錄
  STATE_DIR=$(mktemp -d); RESTORE_LOG="$STATE_DIR/napped.tsv"; LOCK_DIR="$STATE_DIR/.lock"; HOLDING_LOCK=0
}
test_should_upsert_record_replacing_same_pane_and_keeping_others() {
  with_temp_state
  upsert_record w1:p1 "$(record_line w1:p1 claude claude OLD /a "")"
  upsert_record w2:p1 "$(record_line w2:p1 grok grok KEEP /b "")"
  upsert_record w1:p1 "$(record_line w1:p1 claude claude NEW /a --bg)"
  assert_eq $'w2:p1\tgrok\tgrok\tKEEP\t/b\t-\nw1:p1\tclaude\tclaude\tNEW\t/a\t--bg' "$(cat "$RESTORE_LOG")"
  [ -d "$LOCK_DIR" ] && assert_eq "lock released" "lock left behind" || assert_eq 1 1
  rm -rf "$STATE_DIR"
}
test_should_remove_only_listed_panes() {
  with_temp_state
  upsert_record w1:p1 "$(record_line w1:p1 claude claude A /a "")"
  upsert_record w2:p1 "$(record_line w2:p1 claude claude B /b "")"
  upsert_record w3:p1 "$(record_line w3:p1 claude claude C /c "")"
  remove_records "w1:p1 w3:p1"
  assert_eq $'w2:p1\tclaude\tclaude\tB\t/b\t-' "$(cat "$RESTORE_LOG")"
  remove_records ""; assert_eq $'w2:p1\tclaude\tclaude\tB\t/b\t-' "$(cat "$RESTORE_LOG")" empty-list-noop
  rm -rf "$STATE_DIR"
}
test_should_give_up_on_lock_held_by_someone_else_and_break_stale_lock() {
  with_temp_state; LOCK_WAIT_SECS=1
  mkdir -p "$LOCK_DIR"
  upsert_record w1:p1 "$(record_line w1:p1 claude claude A /a "")" 2>/dev/null; assert_eq 1 $? busy
  [ -f "$RESTORE_LOG" ] && assert_eq "no write" "wrote anyway" || assert_eq 1 1
  # 60 秒沒動的鎖視為殘留，可以打破
  touch -t 202601010000 "$LOCK_DIR"
  upsert_record w1:p1 "$(record_line w1:p1 claude claude A /a "")"; assert_eq 0 $? stale-broken
  LOCK_WAIT_SECS=30; rm -rf "$STATE_DIR"
}

# ---------- fmt_age / etime_to_secs ----------
test_should_format_age_in_days_hours_minutes() {
  assert_eq "12m" "$(fmt_age 750)" minutes
  assert_eq "4h05m" "$(fmt_age $((4 * 3600 + 300)))" hours
  assert_eq "3d2h" "$(fmt_age $((3 * 86400 + 2 * 3600 + 59)))" days
  assert_eq "0m" "$(fmt_age 0)" zero
}
test_should_parse_every_etime_shape() {
  assert_eq 754 "$(etime_to_secs 12:34)" mm:ss
  assert_eq $((1 * 3600 + 2 * 60 + 3)) "$(etime_to_secs 01:02:03)" hh:mm:ss
  assert_eq $((8 * 86400 + 19 * 3600 + 58 * 60 + 17)) "$(etime_to_secs 08-19:58:17)" dd-hh:mm:ss
  assert_eq 9 "$(etime_to_secs 00:09)" leading-zero
}

# ---------- last_entry_epoch / latest_entry_epoch / tree_rss_of_pid ----------
test_should_read_last_timestamp_not_mtime() {
  local d; d=$(mktemp -d)
  printf '%s\n' '{"type":"user","timestamp":"2026-09-15T05:07:56.546Z"}' \
    '{"type":"ledger"}' '{"type":"ledger"}' > "$d/claude.jsonl"
  touch "$d/claude.jsonl"   # mtime 是現在，timestamp 是 9/15，要以 timestamp 為準
  assert_eq 1789448876 "$(last_entry_epoch "$d/claude.jsonl")" iso
  printf '%s\n' '{"timestamp":1787735609}' > "$d/grok.jsonl"
  assert_eq 1787735609 "$(last_entry_epoch "$d/grok.jsonl")" epoch-seconds
  printf '%s\n' '{"timestamp":1787735609123}' > "$d/ms.jsonl"
  assert_eq 1787735609 "$(last_entry_epoch "$d/ms.jsonl")" epoch-millis
  printf '%s\n' '{"type":"ledger"}' > "$d/none.jsonl"
  assert_eq "" "$(last_entry_epoch "$d/none.jsonl")" no-timestamp
  assert_eq "" "$(last_entry_epoch "$d/missing")" missing
  rm -rf "$d"
}
test_should_handle_spaces_in_transcript_paths() {
  local real_home=$HOME tmp; tmp=$(mktemp -d); HOME=$tmp
  mkdir -p "$HOME/.claude/projects/-Users-foo-My Project"
  printf '{"timestamp":"2026-06-01T00:00:00Z"}\n' > "$HOME/.claude/projects/-Users-foo-My Project/sid.jsonl"
  local main sub; read -r main sub <<< "$(session_epochs claude sid)"
  assert_eq "$(TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%S' 2026-06-01T00:00:00 +%s)" "$main"
  HOME=$real_home; rm -rf "$tmp"
}
test_should_pick_newest_entry_across_files() {
  local d; d=$(mktemp -d)
  printf '%s\n' '{"timestamp":"2026-01-01T00:00:00Z"}' > "$d/old"
  printf '%s\n' '{"timestamp":"2026-06-01T00:00:00Z"}' > "$d/new"
  assert_eq "$(last_entry_epoch "$d/new")" "$(latest_entry_epoch "$d/old" "$d/missing" "$d/new")"
  assert_eq "" "$(latest_entry_epoch "$d/missing")" all-missing
  rm -rf "$d"
}
test_should_sum_descendant_rss_across_generations() {
  PS_DUMP=$(mktemp)
  printf '%s\n' \
    '100 1 1000 01:00 claude' \
    '200 100 300 00:30 node mcp' \
    '300 200 50 00:10 sh -c x' \
    '400 1 999 01:00 other' \
    '500 400 20 00:10 unrelated' > "$PS_DUMP"
  assert_eq "1350 2" "$(tree_rss_of_pid 100)" with-grandchild
  assert_eq "1019 1" "$(tree_rss_of_pid 400)" sibling-tree
  assert_eq "0 0" "$(tree_rss_of_pid 777)" unknown-root
  rm -f "$PS_DUMP"
}

# ---------- risk_markers ----------
test_should_mark_descendants_and_fresh_start() {
  local now; now=$(date +%s)
  assert_eq "子行程2,剛啟動,無對話紀錄" "$(risk_markers sid 02:00 2 "$now" - -)"
  assert_eq "-" "$(risk_markers "" 01-00:00:00 0 "$now" - -)" nothing
  assert_eq "-" "$(risk_markers sid 01-00:00:00 0 "$now" "$((now - 99999))" "$((now - 99999))")" old-subagent
}
test_should_mark_subagent_activity_when_recent() {
  local now; now=$(date +%s)
  assert_eq "subagent活動中" "$(risk_markers sid 01:00:00 0 "$now" "$((now - 60))" "$((now - 60))")"
}
test_should_scan_main_and_subagent_files_once_each() {
  local real_home=$HOME tmp now; tmp=$(mktemp -d); now=$(date +%s)
  HOME=$tmp
  mkdir -p "$HOME/.claude/projects/-x/sid/subagents"
  local recent; recent=$(TZ=UTC date -r "$((now - 60))" +%Y-%m-%dT%H:%M:%SZ)
  printf '{"timestamp":"2026-09-01T00:00:00Z"}\n' > "$HOME/.claude/projects/-x/sid.jsonl"
  printf '{"timestamp":"%s"}\n' "$recent" > "$HOME/.claude/projects/-x/sid/subagents/a.jsonl"
  local main sub
  read -r main sub <<< "$(session_epochs claude sid)"
  assert_eq "$(last_entry_epoch "$HOME/.claude/projects/-x/sid.jsonl")" "$main" main
  assert_eq $((now - 60)) "$sub" sub
  assert_eq $((now - 60)) "$(max_epoch "$main" "$sub")" max
  assert_eq "- -" "$(session_epochs claude nope)" missing-session
  assert_eq "- -" "$(session_epochs claude "")" empty-session
  assert_eq "" "$(max_epoch - -)" max-of-none
  HOME=$real_home; rm -rf "$tmp"
}
test_should_not_abort_under_errexit_when_timestamp_unparseable() {
  local d out; d=$(mktemp -d)
  printf '%s\n' '{"timestamp":"2026-13-99T99:99:99Z"}' > "$d/bad.jsonl"
  printf '%s\n' '{"timestamp":1787735609.5}' > "$d/float.jsonl"
  printf '%s\n' '{"timestamp":1787735609123456}' > "$d/micro.jsonl"
  out=$(set -e; v=$(last_entry_epoch "$d/bad.jsonl"); echo "ok[$v]")
  assert_eq "ok[]" "$out" bad-iso
  assert_eq 1787735609 "$(last_entry_epoch "$d/float.jsonl")" float-epoch
  assert_eq 1787735609 "$(last_entry_epoch "$d/micro.jsonl")" micro-epoch
  rm -rf "$d"
}

# ---------- FIELDS_SHOWN 同時要被 cut 與 fzf 接受 ----------
test_should_use_field_list_that_both_cut_and_fzf_accept() {
  local row; row=$(printf '1\t2\t3\t4\t5\t6\t7\t8\t9\t10\t11\t12\t13\t14\t15')
  assert_eq $'1\t2\t3\t4\t5\t6\t7\t8\t9\t10' "$(printf '%s\n' "$row" | cut -f"$FIELDS_SHOWN")" cut
  if command -v fzf >/dev/null; then
    assert_eq "$row" "$(printf '%s\n' "$row" | fzf --filter=3 --delimiter=$'\t' --with-nth="$FIELDS_SHOWN")" fzf
  fi
}

# ---------- inside_herdr_tree ----------
test_should_detect_process_inside_herdr_tree() {
  PS_DUMP=$(mktemp)
  # herdr server(500) -> pane shell(600, zsh) -> claude(700)；外部 claude(800) -> Terminal(801)
  printf '%s\n' \
    '500 1 1000 01:00 /opt/homebrew/bin/herdr server' \
    '600 500 2000 01:00 -zsh' \
    '700 600 3000 01:00 claude --resume abc' \
    '801 1 900 01:00 /Applications/iTerm.app/Contents/MacOS/iTerm2' \
    '800 801 3000 01:00 claude --resume xyz' > "$PS_DUMP"
  inside_herdr_tree 700; assert_eq 0 $? in-herdr
  inside_herdr_tree 800; assert_eq 1 $? external
  inside_herdr_tree 600; assert_eq 0 $? pane-shell-itself
  inside_herdr_tree 999; assert_eq 1 $? unknown-pid
  rm -f "$PS_DUMP"
}
test_should_not_loop_on_ppid_cycle() {
  PS_DUMP=$(mktemp)
  # 病態：兩個 pid 互為 parent，不能無限迴圈
  printf '%s\n' '10 11 0 01:00 a' '11 10 0 01:00 b' > "$PS_DUMP"
  inside_herdr_tree 10; assert_eq 1 $? cycle-terminates
  rm -f "$PS_DUMP"
}

# ---------- 訊息與語言 ----------
message_keys() {
  # 從 case 分支抓 key（排除 * 預設分支）
  # declare -f 會把 `key) printf ... ;;` 重排成多行，只認行首的 `key)`
  declare -f "$1" | awk '/^ *[a-z_]+\)/ { sub(/\).*/, ""); sub(/^ */, ""); print }' | sort
}
test_should_have_identical_keys_in_both_message_tables() {
  assert_eq "$(message_keys msg_zh)" "$(message_keys msg_en)"
  [ "$(message_keys msg_zh | wc -l | tr -d ' ')" -gt 40 ] && assert_eq 1 1 || assert_eq "many keys" "few keys"
}
test_should_have_same_placeholder_count_in_both_languages() {
  local key zh en
  for key in $(message_keys msg_zh); do
    zh=$(msg_zh "$key" | grep -o '%s' | wc -l | tr -d ' ')
    en=$(msg_en "$key" | grep -o '%s' | wc -l | tr -d ' ')
    assert_eq "$zh" "$en" "$key"
  done
}
test_should_render_message_in_selected_language() {
  NAP_LANG=zh; assert_eq "w1:p1 claude 已在執行中，紀錄清除。" "$(t already_running w1:p1 claude)" zh
  NAP_LANG=en; assert_eq "w1:p1 claude is already running, record cleared." "$(t already_running w1:p1 claude)" en
  NAP_LANG=en; assert_eq "children:3" "$(t mark_children 3)" en-mark
  NAP_LANG=en; assert_eq $'SRC\tAGENT\tPANE' "$(t header_row | cut -f1-3)" en-header
  NAP_LANG=zh
}
test_should_detect_language_from_env() {
  assert_eq zh "$(HERDR_NAP_LANG=zh LANG=en_US.UTF-8 detect_lang)" override
  assert_eq en "$(HERDR_NAP_LANG= LC_ALL= LC_MESSAGES= LANG=en_US.UTF-8 detect_lang)" lang-en
  assert_eq zh "$(HERDR_NAP_LANG= LC_ALL= LC_MESSAGES= LANG=zh_TW.UTF-8 detect_lang)" lang-zh
  assert_eq zh "$(HERDR_NAP_LANG= LC_ALL=zh_CN.UTF-8 LANG=en_US.UTF-8 detect_lang)" lc-all-wins
  assert_eq en "$(HERDR_NAP_LANG= LC_ALL= LC_MESSAGES= LANG= detect_lang)" unset
}
test_should_mark_risks_in_english_when_selected() {
  NAP_LANG=en
  assert_eq "children:2,just-started,no-transcript" "$(risk_markers sid 02:00 2 "$(date +%s)" - -)"
  NAP_LANG=zh
}

# ---------- fill_empty_fields ----------
test_should_fill_empty_tsv_fields_with_dash() {
  assert_eq $'a\t-\tc\t-' "$(printf 'a\t\tc\t\n' | fill_empty_fields)"
  assert_eq $'x\ty' "$(printf 'x\ty\n' | fill_empty_fields)" untouched
}

# ---------- 釘選排除 ----------
test_should_load_patterns_ignoring_comments_and_blank_lines() {
  local f; f=$(mktemp)
  printf '# 註解\n\nrevelio\n  \nherdr-nap-dev\n' > "$f"
  assert_eq $'revelio\nherdr-nap-dev' "$(exclude_patterns "$f")"
  assert_eq "" "$(exclude_patterns "$f.missing")" missing-file
  rm -f "$f"
}
test_should_pin_when_title_or_label_contains_pattern() {
  local p=$'revelio\ndev-0918'
  is_pinned "$p" "surya OCR revelio host" "";        assert_eq 0 $? title
  is_pinned "$p" "" "herdr-nap-dev-0918";           assert_eq 0 $? label
  is_pinned "$p" "91app-map" "w5:t3";               assert_eq 1 $? neither
  is_pinned ""   "revelio" "revelio";               assert_eq 1 $? no-patterns
}
test_should_dim_only_pinned_lines_when_on_a_tty() {
  # 非 tty 時原樣輸出，管線接下去的人不會吃到跳脫碼
  assert_eq $'a b w1:p1 x\na b w2:p1 y' "$(printf 'a b w1:p1 x\na b w2:p1 y\n' | dim_pinned_lines "w1:p1")"
}

# ---------- stub_path ----------
test_should_sanitize_pane_id_for_stub_filename() {
  STUB_DIR=/s
  assert_eq "/s/w1_pB.sh" "$(stub_path w1:pB)"
}

# ---------- is_boolean_flag ----------
test_should_recognize_known_boolean_flags() {
  is_boolean_flag --dangerously-skip-permissions; assert_eq 0 $? dsp
  is_boolean_flag --model; assert_eq 1 $? model
  is_boolean_flag --bg; assert_eq 0 $? bg
}

for t in $(declare -F | awk '$3 ~ /^test_/ { print $3 }'); do "$t"; done
echo "通過 ${pass}、失敗 ${fail}"
[ "$fail" -eq 0 ]
