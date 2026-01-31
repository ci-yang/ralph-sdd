#!/bin/bash
# Ralph SDD - 無人值守執行 SDD tasks.md 的外部迴圈
#
# 用法:
#   ./scripts/ralph-sdd.sh [options]
#
# 選項:
#   --phase <N>           指定執行的 Phase (預設: 自動偵測)
#   --max-iterations <N>  最大迭代次數 (預設: 50)
#   --tasks <file>        tasks.md 路徑 (預設: 自動偵測)
#   --dry-run             只顯示配置，不執行
#   --monitor             使用 tmux 開啟監控面板
#   --help                顯示說明
#
# 基於 Geoffrey Huntley 的 Ralph 技術
# 整合 spec-kit SDD 流程

set -euo pipefail

# ============================================================================
# 配置
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ralph 配置
MAX_ITERATIONS=50
PHASE=""
TASKS_FILE=""
DRY_RUN=false
USE_TMUX=false
SLEEP_BETWEEN_ITERATIONS=3
PROMPT_TEMPLATE=""  # 自定義 prompt 模板檔案

# 狀態追蹤
LOG_DIR="$PROJECT_ROOT/.ralph"
LOG_FILE="$LOG_DIR/ralph-sdd.log"
STATUS_FILE="$LOG_DIR/status.json"
SESSION_FILE="$LOG_DIR/.session"

# Promise 關鍵字（用於偵測完成）
PROMISE_COMPLETE="<promise>PHASE COMPLETE</promise>"
PROMISE_CONTINUE="<promise>CONTINUE</promise>"
PROMISE_BLOCKED="<promise>BLOCKED"
PROMISE_E2E_PASSED="<promise>E2E PASSED</promise>"

# 顏色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# 工具函數
# ============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""

    case $level in
        "INFO")    color=$BLUE ;;
        "WARN")    color=$YELLOW ;;
        "ERROR")   color=$RED ;;
        "SUCCESS") color=$GREEN ;;
        "LOOP")    color=$PURPLE ;;
        "DEBUG")   color=$CYAN ;;
    esac

    echo -e "${color}[$timestamp] [$level] $message${NC}"
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

show_help() {
    cat << 'EOF'
Ralph SDD - 無人值守執行 SDD tasks.md

用法:
  ./scripts/ralph-sdd.sh [options]

選項:
  --phase <N>           指定執行的 Phase (預設: 自動偵測未完成的 Phase)
  --max-iterations <N>  最大迭代次數 (預設: 50)
  --tasks <file>        tasks.md 路徑 (預設: 自動偵測 specs/*/tasks.md)
  --prompt-template <f> 自定義 prompt 模板檔案 (預設: .ralph/templates/prompt-template.md)
  --dry-run             只顯示配置，不執行
  --monitor             使用 tmux 開啟監控面板
  --help                顯示說明

範例:
  # 自動執行所有未完成任務
  ./scripts/ralph-sdd.sh

  # 指定執行 Phase 11
  ./scripts/ralph-sdd.sh --phase 11

  # 限制最多 20 次迭代
  ./scripts/ralph-sdd.sh --max-iterations 20

  # 開啟監控面板
  ./scripts/ralph-sdd.sh --monitor

說明:
  此腳本會持續呼叫 Claude Code 執行 prompt 模板中定義的指令，
  直到所有任務完成或達到最大迭代次數。

  使用 --prompt-template 指定自定義模板，或將模板放在 .ralph/templates/prompt-template.md

  模板支援的變數：
  - {{PHASE}}           : 當前 Phase
  - {{ITERATION}}       : 當前迭代次數
  - {{MAX_ITERATIONS}}  : 最大迭代次數
  - {{TASKS_FILE}}      : tasks.md 檔案路徑

  Claude 需要輸出以下 promise 標籤來控制流程：
  - <promise>CONTINUE</promise>     : 還有任務未完成，繼續
  - <promise>PHASE COMPLETE</promise>: Phase 完成
  - <promise>BLOCKED: [原因]</promise>: 遇到無法解決的問題

安全性:
  此腳本使用 --dangerously-skip-permissions，但你的 hooks
  (safety-guard.sh) 會提供安全護欄，阻擋危險操作。
EOF
}

# ============================================================================
# 初始化
# ============================================================================

init() {
    mkdir -p "$LOG_DIR"

    # 初始化日誌
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "# Ralph SDD Log" > "$LOG_FILE"
        echo "Started: $(date)" >> "$LOG_FILE"
        echo "---" >> "$LOG_FILE"
    fi

    log "INFO" "初始化 Ralph SDD..."
}

# ============================================================================
# 自動偵測 tasks.md
# ============================================================================

detect_tasks_file() {
    if [[ -n "$TASKS_FILE" && -f "$TASKS_FILE" ]]; then
        return 0
    fi

    # 嘗試常見位置（按優先順序）
    local candidates=(
        "$PROJECT_ROOT/specs/*/tasks.md"
        "$PROJECT_ROOT/.specify/*/tasks.md"
        "$PROJECT_ROOT/tasks.md"
    )

    for pattern in "${candidates[@]}"; do
        # shellcheck disable=SC2086
        for file in $pattern; do
            if [[ -f "$file" ]]; then
                TASKS_FILE="$file"
                log "INFO" "偵測到 tasks.md: $TASKS_FILE"
                return 0
            fi
        done
    done

    log "ERROR" "找不到 tasks.md 檔案"
    exit 1
}

# ============================================================================
# 分析 tasks.md 狀態
# ============================================================================

analyze_tasks() {
    local tasks_file="$1"

    # 計算總任務數、已完成、未完成
    local total=$(grep -c '^\- \[' "$tasks_file" 2>/dev/null || echo "0")
    local completed=$(grep -c '^\- \[x\]' "$tasks_file" 2>/dev/null || echo "0")
    local pending=$((total - completed))

    echo "$total:$completed:$pending"
}

get_current_phase() {
    local tasks_file="$1"

    # 找到第一個有未完成任務的 Phase
    local current_phase=""
    local in_phase=""

    while IFS= read -r line; do
        # 偵測 Phase 標題
        if [[ "$line" =~ ^##[[:space:]]+Phase[[:space:]]+([0-9]+) ]]; then
            in_phase="${BASH_REMATCH[1]}"
        fi

        # 如果在 Phase 中且有未完成任務
        if [[ -n "$in_phase" && "$line" =~ ^\-[[:space:]]\[[[:space:]]\] ]]; then
            current_phase="$in_phase"
            break
        fi
    done < "$tasks_file"

    echo "$current_phase"
}

get_phase_tasks() {
    local tasks_file="$1"
    local phase="$2"

    # 計算指定 Phase 的任務狀態
    local in_target_phase=false
    local total=0
    local completed=0

    while IFS= read -r line; do
        # 偵測 Phase 標題
        if [[ "$line" =~ ^##[[:space:]]+Phase[[:space:]]+([0-9]+) ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$phase" ]]; then
                in_target_phase=true
            else
                in_target_phase=false
            fi
        fi

        # 計算任務
        if [[ "$in_target_phase" == true ]]; then
            if [[ "$line" =~ ^\-[[:space:]]\[[xX]\] ]]; then
                ((total++))
                ((completed++))
            elif [[ "$line" =~ ^\-[[:space:]]\[[[:space:]]\] ]]; then
                ((total++))
            fi
        fi
    done < "$tasks_file"

    local pending=$((total - completed))
    echo "$total:$completed:$pending"
}

# ============================================================================
# 更新狀態
# ============================================================================

update_status() {
    local iteration="$1"
    local phase="$2"
    local status="$3"
    local last_promise="$4"

    local stats=$(analyze_tasks "$TASKS_FILE")
    local total=$(echo "$stats" | cut -d: -f1)
    local completed=$(echo "$stats" | cut -d: -f2)
    local pending=$(echo "$stats" | cut -d: -f3)

    cat > "$STATUS_FILE" << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "iteration": $iteration,
    "max_iterations": $MAX_ITERATIONS,
    "phase": "$phase",
    "status": "$status",
    "last_promise": "$last_promise",
    "tasks": {
        "total": $total,
        "completed": $completed,
        "pending": $pending,
        "progress_percent": $(( completed * 100 / (total > 0 ? total : 1) ))
    },
    "tasks_file": "$TASKS_FILE"
}
EOF
}

# ============================================================================
# 執行 Claude Code
# ============================================================================

# ============================================================================
# Prompt 模板處理
# ============================================================================

# 預設 prompt 模板（當沒有指定模板檔案時使用）
get_default_prompt() {
    local phase="$1"
    local iteration="$2"

    if [[ -n "$phase" ]]; then
        cat << EOF
執行任務，專注於 Phase $phase 的未完成任務。

任務檔案: $TASKS_FILE

規則：
1. 只執行 Phase $phase 中標記為 [ ] 的任務
2. 每完成一個任務，立即在任務檔案中標記為 [x]
3. 如果 Phase $phase 所有任務完成，輸出 <promise>PHASE COMPLETE</promise>
4. 如果還有任務未完成，輸出 <promise>CONTINUE</promise>
5. 如果遇到無法解決的問題，輸出 <promise>BLOCKED: [原因]</promise>

當前迭代: $iteration / $MAX_ITERATIONS
EOF
    else
        cat << EOF
執行任務，從第一個未完成的任務開始。

任務檔案: $TASKS_FILE

規則：
1. 找到任務檔案中第一個標記為 [ ] 的任務
2. 完成後在任務檔案中標記為 [x]
3. 輸出適當的 promise 標籤

當前迭代: $iteration / $MAX_ITERATIONS
EOF
    fi
}

# 從模板檔案建立 prompt（支援變數替換）
build_prompt_from_template() {
    local phase="$1"
    local iteration="$2"
    local template_file="$3"

    if [[ ! -f "$template_file" ]]; then
        log "WARN" "找不到模板檔案 $template_file，使用預設 prompt"
        get_default_prompt "$phase" "$iteration"
        return
    fi

    # 讀取模板並替換變數
    local template
    template=$(cat "$template_file")

    # 變數替換
    template="${template//\{\{PHASE\}\}/$phase}"
    template="${template//\{\{ITERATION\}\}/$iteration}"
    template="${template//\{\{MAX_ITERATIONS\}\}/$MAX_ITERATIONS}"
    template="${template//\{\{TASKS_FILE\}\}/$TASKS_FILE}"

    echo "$template"
}

# 偵測或使用指定的 prompt 模板
detect_prompt_template() {
    if [[ -n "$PROMPT_TEMPLATE" && -f "$PROMPT_TEMPLATE" ]]; then
        log "INFO" "使用指定模板: $PROMPT_TEMPLATE"
        return 0
    fi

    # 嘗試預設位置
    local default_template="$PROJECT_ROOT/.ralph/templates/prompt-template.md"
    if [[ -f "$default_template" ]]; then
        PROMPT_TEMPLATE="$default_template"
        log "INFO" "偵測到模板: $PROMPT_TEMPLATE"
        return 0
    fi

    # 沒有模板，使用內建預設
    PROMPT_TEMPLATE=""
    log "INFO" "使用內建預設 prompt"
}

run_claude() {
    local phase="$1"
    local iteration="$2"

    local prompt=""

    if [[ -n "$PROMPT_TEMPLATE" && -f "$PROMPT_TEMPLATE" ]]; then
        prompt=$(build_prompt_from_template "$phase" "$iteration" "$PROMPT_TEMPLATE")
    else
        prompt=$(get_default_prompt "$phase" "$iteration")
    fi

    # 執行 Claude Code
    local output
    output=$(claude --dangerously-skip-permissions -p "$prompt" 2>&1 | tee /dev/stderr) || true

    echo "$output"
}

# ============================================================================
# 分析輸出
# ============================================================================

analyze_output() {
    local output="$1"

    if echo "$output" | grep -q "$PROMISE_COMPLETE"; then
        echo "PHASE_COMPLETE"
    elif echo "$output" | grep -q "$PROMISE_E2E_PASSED"; then
        echo "E2E_PASSED"
    elif echo "$output" | grep -q "$PROMISE_BLOCKED"; then
        echo "BLOCKED"
    elif echo "$output" | grep -q "$PROMISE_CONTINUE"; then
        echo "CONTINUE"
    else
        # 沒有明確的 promise，檢查是否有進度
        echo "NO_PROMISE"
    fi
}

# ============================================================================
# 主迴圈
# ============================================================================

main_loop() {
    local iteration=0
    local consecutive_no_progress=0
    local last_completed=0

    log "LOOP" "=========================================="
    log "LOOP" "  Ralph SDD 開始執行"
    log "LOOP" "=========================================="
    log "INFO" "Tasks 檔案: $TASKS_FILE"
    log "INFO" "最大迭代: $MAX_ITERATIONS"
    if [[ -n "$PHASE" ]]; then
        log "INFO" "指定 Phase: $PHASE"
    fi

    # 初始狀態
    local stats=$(analyze_tasks "$TASKS_FILE")
    local total=$(echo "$stats" | cut -d: -f1)
    local completed=$(echo "$stats" | cut -d: -f2)
    local pending=$(echo "$stats" | cut -d: -f3)

    log "INFO" "任務狀態: $completed/$total 完成, $pending 待處理"

    if [[ "$pending" -eq 0 ]]; then
        log "SUCCESS" "所有任務已完成！"
        return 0
    fi

    # 決定要執行的 Phase
    local target_phase="$PHASE"
    if [[ -z "$target_phase" ]]; then
        target_phase=$(get_current_phase "$TASKS_FILE")
    fi

    if [[ -n "$target_phase" ]]; then
        local phase_stats=$(get_phase_tasks "$TASKS_FILE" "$target_phase")
        local phase_pending=$(echo "$phase_stats" | cut -d: -f3)
        log "INFO" "Phase $target_phase: $phase_pending 個任務待處理"
    fi

    last_completed=$completed

    while [[ $iteration -lt $MAX_ITERATIONS ]]; do
        ((iteration++))

        log "LOOP" ""
        log "LOOP" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log "LOOP" "  迭代 $iteration / $MAX_ITERATIONS"
        log "LOOP" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        update_status "$iteration" "$target_phase" "running" ""

        # 執行 Claude
        local output
        output=$(run_claude "$target_phase" "$iteration")

        # 分析輸出
        local result=$(analyze_output "$output")

        log "INFO" "輸出分析: $result"

        # 更新任務統計
        stats=$(analyze_tasks "$TASKS_FILE")
        completed=$(echo "$stats" | cut -d: -f2)
        pending=$(echo "$stats" | cut -d: -f3)

        # 檢查進度
        if [[ "$completed" -gt "$last_completed" ]]; then
            local progress=$((completed - last_completed))
            log "SUCCESS" "完成 $progress 個任務！目前進度: $completed/$total"
            consecutive_no_progress=0
            last_completed=$completed
        else
            ((consecutive_no_progress++))
            log "WARN" "本次迭代無新進度 ($consecutive_no_progress 次)"
        fi

        update_status "$iteration" "$target_phase" "$result" "$result"

        # 根據結果決定下一步
        case "$result" in
            "PHASE_COMPLETE"|"E2E_PASSED")
                log "SUCCESS" "Phase $target_phase 完成！"

                # 檢查是否還有其他 Phase
                local next_phase=$(get_current_phase "$TASKS_FILE")
                if [[ -z "$next_phase" ]]; then
                    log "SUCCESS" "=========================================="
                    log "SUCCESS" "  所有任務完成！"
                    log "SUCCESS" "=========================================="
                    update_status "$iteration" "" "complete" "$result"
                    return 0
                else
                    log "INFO" "繼續執行 Phase $next_phase"
                    target_phase="$next_phase"
                    consecutive_no_progress=0
                fi
                ;;

            "BLOCKED")
                log "ERROR" "=========================================="
                log "ERROR" "  執行被阻塞"
                log "ERROR" "=========================================="
                log "ERROR" "請檢查 Claude 輸出了解阻塞原因"
                update_status "$iteration" "$target_phase" "blocked" "$result"
                return 1
                ;;

            "CONTINUE"|"NO_PROMISE")
                if [[ "$pending" -eq 0 ]]; then
                    log "SUCCESS" "所有任務完成！"
                    update_status "$iteration" "" "complete" "$result"
                    return 0
                fi

                # Circuit breaker: 連續 5 次無進度
                if [[ "$consecutive_no_progress" -ge 5 ]]; then
                    log "ERROR" "=========================================="
                    log "ERROR" "  Circuit Breaker 觸發"
                    log "ERROR" "  連續 5 次迭代無進度"
                    log "ERROR" "=========================================="
                    update_status "$iteration" "$target_phase" "circuit_break" "NO_PROGRESS"
                    return 1
                fi

                log "INFO" "繼續下一次迭代..."
                ;;
        esac

        sleep $SLEEP_BETWEEN_ITERATIONS
    done

    log "WARN" "=========================================="
    log "WARN" "  達到最大迭代次數 ($MAX_ITERATIONS)"
    log "WARN" "=========================================="
    update_status "$iteration" "$target_phase" "max_iterations" ""
    return 1
}

# ============================================================================
# 參數解析
# ============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --phase)
                PHASE="$2"
                shift 2
                ;;
            --max-iterations)
                MAX_ITERATIONS="$2"
                shift 2
                ;;
            --tasks)
                TASKS_FILE="$2"
                shift 2
                ;;
            --prompt-template)
                PROMPT_TEMPLATE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --monitor)
                USE_TMUX=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "未知參數: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# Dry Run
# ============================================================================

dry_run() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Ralph SDD - Dry Run"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "配置:"
    echo "  Tasks 檔案:    $TASKS_FILE"
    echo "  最大迭代:      $MAX_ITERATIONS"
    echo "  指定 Phase:    ${PHASE:-自動偵測}"
    echo "  Prompt 模板:   ${PROMPT_TEMPLATE:-內建預設}"
    echo ""

    local stats=$(analyze_tasks "$TASKS_FILE")
    local total=$(echo "$stats" | cut -d: -f1)
    local completed=$(echo "$stats" | cut -d: -f2)
    local pending=$(echo "$stats" | cut -d: -f3)

    echo "任務狀態:"
    echo "  總計:     $total"
    echo "  已完成:   $completed"
    echo "  待處理:   $pending"
    echo ""

    if [[ -z "$PHASE" ]]; then
        local current_phase=$(get_current_phase "$TASKS_FILE")
        echo "自動偵測 Phase: $current_phase"

        if [[ -n "$current_phase" ]]; then
            local phase_stats=$(get_phase_tasks "$TASKS_FILE" "$current_phase")
            echo "Phase $current_phase 任務: $(echo "$phase_stats" | cut -d: -f3) 個待處理"
        fi
    fi

    echo ""
    echo "將執行的命令:"
    echo "  claude --dangerously-skip-permissions -p \"<prompt from template>\""
    echo ""
    echo "Hooks (安全護欄):"
    if [[ -f "$PROJECT_ROOT/.claude/hooks/hooks.json" ]]; then
        echo "  ✓ hooks.json 已配置"
        echo "  ✓ safety-guard.sh 將阻擋危險操作"
    else
        echo "  ⚠ 未偵測到 hooks 配置"
    fi
    echo ""
}

# ============================================================================
# tmux 監控
# ============================================================================

setup_tmux() {
    if ! command -v tmux &> /dev/null; then
        log "ERROR" "tmux 未安裝"
        echo "安裝方式:"
        echo "  macOS: brew install tmux"
        echo "  Ubuntu: sudo apt install tmux"
        exit 1
    fi

    local session_name="ralph-sdd-$(date +%s)"

    log "INFO" "建立 tmux session: $session_name"

    # 建立 session
    tmux new-session -d -s "$session_name" -c "$PROJECT_ROOT"

    # 分割視窗
    tmux split-window -h -t "$session_name" -c "$PROJECT_ROOT"

    # 左側：Ralph 主程式
    tmux send-keys -t "$session_name:0.0" "$0 --tasks '$TASKS_FILE' --max-iterations $MAX_ITERATIONS ${PHASE:+--phase $PHASE}" Enter

    # 右側：監控狀態
    tmux send-keys -t "$session_name:0.1" "watch -n 2 'cat $STATUS_FILE 2>/dev/null | jq . || echo \"等待狀態更新...\"'" Enter

    # 設定標題
    tmux rename-window -t "$session_name:0" "Ralph SDD"

    log "SUCCESS" "tmux session 已建立"
    log "INFO" "使用 Ctrl+B 然後 D 來 detach"
    log "INFO" "使用 'tmux attach -t $session_name' 重新連接"

    # 連接到 session
    tmux attach-session -t "$session_name"

    exit 0
}

# ============================================================================
# 主程式
# ============================================================================

main() {
    parse_args "$@"
    init
    detect_tasks_file
    detect_prompt_template

    if [[ "$USE_TMUX" == true ]]; then
        setup_tmux
    fi

    if [[ "$DRY_RUN" == true ]]; then
        dry_run
        exit 0
    fi

    main_loop
}

main "$@"
