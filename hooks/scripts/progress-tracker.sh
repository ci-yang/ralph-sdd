#!/bin/bash
# Progress Tracker Hook for Claude Code
# 追蹤檔案變更並提醒 Atomic Commit
#
# 在 PostToolUse 時執行，追蹤 Write/Edit 操作

set -euo pipefail

# 讀取 stdin 的 JSON 輸入
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // {}')

# 專案根目錄（使用 Claude Code 提供的環境變數）
PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PROGRESS_FILE="$PROJECT_ROOT/.claude/progress.local.md"
COMMIT_THRESHOLD=5

# 確保進度檔案存在
if [ ! -f "$PROGRESS_FILE" ]; then
    cat > "$PROGRESS_FILE" << 'EOF'
# Ralph Loop Progress Tracker

## Session Info
- Started: $(date '+%Y-%m-%d %H:%M:%S')
- Status: running

## Modified Files
EOF
fi

# 記錄檔案修改
if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
    file_path=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')
    if [ -n "$file_path" ]; then
        timestamp=$(date '+%H:%M:%S')
        echo "- [$timestamp] $TOOL_NAME: $file_path" >> "$PROGRESS_FILE"
    fi
fi

# 檢查未提交的變更數量
cd "$PROJECT_ROOT" 2>/dev/null || exit 0

CHANGED_FILES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

if [ "$CHANGED_FILES" -gt "$COMMIT_THRESHOLD" ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 ATOMIC COMMIT REMINDER"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "有 $CHANGED_FILES 個檔案已變更。"
    echo "建議執行 atomic commit 保存進度。"
    echo ""
    echo "使用 /ggcm 或手動執行 git commit"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
fi

exit 0
