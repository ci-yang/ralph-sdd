#!/bin/bash
# Safety Guard Hook for Claude Code
# 在 --dangerously-skip-permissions 模式下提供額外保護
# 專為 Ralph SDD 無人值守模式設計
#
# Exit codes:
# 0 = Allow (approve)
# 1 = Error
# 2 = Block (deny)

set -euo pipefail

# ==========================================
# 配置
# ==========================================

# 專案根目錄（使用 Claude Code 提供的環境變數）
PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# Ralph 狀態目錄
RALPH_DIR="$PROJECT_ROOT/.ralph"

# 日誌目錄
LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="$LOG_DIR/safety-guard.log"

# 統計追蹤
STATS_FILE="$RALPH_DIR/.safety_stats"

# ==========================================
# 初始化
# ==========================================

# 讀取 stdin 的 JSON 輸入
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // {}')

# 確保目錄存在
mkdir -p "$LOG_DIR" "$RALPH_DIR" 2>/dev/null || true

# ==========================================
# 日誌和統計
# ==========================================

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
}

update_stats() {
    local action="$1"  # ALLOWED, BLOCKED
    local tool="$2"

    # 初始化統計檔案
    if [[ ! -f "$STATS_FILE" ]]; then
        echo '{"allowed":0,"blocked":0,"tools":{}}' > "$STATS_FILE"
    fi

    # 更新統計（簡單計數）
    if [[ "$action" == "BLOCKED" ]]; then
        local blocked=$(jq '.blocked' "$STATS_FILE")
        jq ".blocked = $((blocked + 1))" "$STATS_FILE" > "$STATS_FILE.tmp" && mv "$STATS_FILE.tmp" "$STATS_FILE"
    else
        local allowed=$(jq '.allowed' "$STATS_FILE")
        jq ".allowed = $((allowed + 1))" "$STATS_FILE" > "$STATS_FILE.tmp" && mv "$STATS_FILE.tmp" "$STATS_FILE"
    fi
}

# ==========================================
# Bash 命令安全檢查
# ==========================================
check_bash_safety() {
    local command="$1"

    # 危險命令模式（絕對禁止）
    local DANGEROUS_PATTERNS=(
        # 破壞性刪除
        "rm -rf /"
        "rm -rf ~"
        "rm -rf \$HOME"
        "rm -rf \.\."
        "sudo rm"
        # 權限提升
        "sudo su"
        "sudo -i"
        "sudo bash"
        "chmod 777"
        "chown root"
        # 磁碟操作
        "mkfs"
        "dd if="
        "fdisk"
        "parted"
        # 設備操作
        "> /dev/"
        "< /dev/sd"
        # 遠端程式碼執行
        "eval \$(curl"
        "curl.*|.*sh"
        "curl.*|.*bash"
        "wget.*|.*sh"
        "wget.*|.*bash"
        "\| sh$"
        "\| bash$"
        # Git 危險操作
        "git push.*--force"
        "git push.*-f"
        "git push -f"
        "git reset --hard origin"
        "git clean -fdx"
        "git rebase.*-i"
        # 發布操作（防止意外發布）
        "npm publish"
        "pnpm publish"
        "yarn publish"
        # Fork bomb
        ":(){:|:&};:"
        # 環境變數洩漏
        "printenv"
        "export.*SECRET"
        "export.*KEY"
        "export.*PASSWORD"
        # 歷史和設定
        "history -c"
        "history -w"
        # 網路監聽
        "nc -l"
        "netcat -l"
        # 加密貨幣挖礦
        "xmrig"
        "cryptominer"
    )

    # 禁止訪問的路徑
    local FORBIDDEN_PATHS=(
        # 系統設定
        "/etc/"
        "/System/"
        "/Library/Preferences/"
        # 系統執行檔
        "/usr/bin/"
        "/usr/local/bin/"
        "/bin/"
        "/sbin/"
        # 憑證和金鑰
        "~/.ssh/"
        "/.ssh/"
        "~/.gnupg/"
        "/.gnupg/"
        # 雲端憑證
        "~/.aws/"
        "/.aws/"
        "~/.config/gcloud"
        "/.config/gcloud"
        "~/.kube/"
        "/.kube/"
        "~/.azure/"
        "/.azure/"
        # 系統日誌
        "/var/log/"
        # 敏感應用程式設定
        "~/.config/gh/"
        "~/.netrc"
        "~/.npmrc"
        # 瀏覽器憑證
        "~/Library/Application Support/Google/Chrome"
        "~/Library/Application Support/Firefox"
    )

    # 檢查危險命令
    for pattern in "${DANGEROUS_PATTERNS[@]}"; do
        if echo "$command" | grep -qiE "$pattern"; then
            log_message "BLOCKED" "Dangerous command pattern: $pattern"
            echo "BLOCKED: 危險命令被攔截 - $pattern" >&2
            return 2
        fi
    done

    # 檢查禁止路徑
    for path in "${FORBIDDEN_PATHS[@]}"; do
        if echo "$command" | grep -qE "$path"; then
            log_message "BLOCKED" "Forbidden path access: $path"
            echo "BLOCKED: 禁止訪問系統路徑 - $path" >&2
            return 2
        fi
    done

    # 允許的安全命令模式
    local ALLOWED_PATTERNS=(
        "^pnpm "
        "^npm "
        "^npx "
        "^git (status|add|commit|log|diff|branch|checkout|stash|pull)"
        "^mkdir "
        "^touch "
        "^cp "
        "^mv "
        "^cat "
        "^ls "
        "^pwd"
        "^echo "
        "^node "
        "^tsx "
        "^vitest"
        "^playwright"
        "^prisma "
        "^next "
    )

    log_message "ALLOWED" "Command passed safety check: ${command:0:50}..."
    return 0
}

# ==========================================
# 檔案操作安全檢查
# ==========================================
check_file_safety() {
    local file_path="$1"
    local operation="$2"

    # 禁止操作的檔案模式
    local FORBIDDEN_FILES=(
        # 環境變數（含敏感資訊）
        ".env"
        ".env.local"
        ".env.production"
        ".env.staging"
        # SSH 金鑰
        "id_rsa"
        "id_ed25519"
        "id_dsa"
        "id_ecdsa"
        "known_hosts"
        "authorized_keys"
        # 雲端憑證
        "credentials.json"
        "service-account.json"
        "gcp-key.json"
        "aws-credentials"
        # 憑證檔案
        "*.pem"
        "*.key"
        "*.p12"
        "*.pfx"
        "*.crt"
        # Token 和密碼
        "*token*"
        "*secret*"
        "*.password"
        # 設定檔（可能含敏感資訊）
        ".netrc"
        ".npmrc"
        ".pypirc"
        # 資料庫
        "*.sqlite"
        "*.db"
    )

    # 允許的例外（安全的範本檔案）
    local ALLOWED_EXCEPTIONS=(
        ".env.example"
        ".env.sample"
        ".env.template"
        "*.example"
        "*.sample"
        "*.template"
    )

    # 檢查是否為允許的例外
    for exception in "${ALLOWED_EXCEPTIONS[@]}"; do
        if [[ "$file_path" == *"$exception"* ]]; then
            log_message "ALLOWED" "Exception file: $file_path"
            return 0
        fi
    done

    # 檢查禁止的檔案
    for pattern in "${FORBIDDEN_FILES[@]}"; do
        # 移除 * 做簡單匹配
        local clean_pattern="${pattern//\*/}"
        if [[ "$file_path" == *"$clean_pattern"* ]]; then
            log_message "BLOCKED" "Forbidden file access: $file_path ($operation)"
            update_stats "BLOCKED" "$operation"
            echo "BLOCKED: 禁止操作敏感檔案 - $file_path" >&2
            return 2
        fi
    done

    # 檢查絕對路徑是否在專案內
    if [[ "$file_path" == /* ]]; then
        # 是絕對路徑
        if [[ "$file_path" != "$PROJECT_ROOT"* ]]; then
            log_message "BLOCKED" "File outside project: $file_path"
            update_stats "BLOCKED" "$operation"
            echo "BLOCKED: 禁止操作專案外的檔案 - $file_path" >&2
            return 2
        fi
    else
        # 是相對路徑，檢查是否試圖離開專案目錄
        if [[ "$file_path" == ../* ]] || [[ "$file_path" == */../* ]]; then
            log_message "BLOCKED" "Path traversal attempt: $file_path"
            update_stats "BLOCKED" "$operation"
            echo "BLOCKED: 禁止路徑穿越 - $file_path" >&2
            return 2
        fi
    fi

    log_message "ALLOWED" "File operation: $operation $file_path"
    update_stats "ALLOWED" "$operation"
    return 0
}

# ==========================================
# 網路請求安全檢查
# ==========================================
check_network_safety() {
    local url="$1"

    # 禁止的 URL 模式
    local FORBIDDEN_URLS=(
        "localhost"
        "127.0.0.1"
        "0.0.0.0"
        "169.254."        # Link-local
        "10."             # Private class A
        "172.16."         # Private class B
        "192.168."        # Private class C
        "metadata.google"
        "169.254.169.254" # AWS/GCP metadata
    )

    for pattern in "${FORBIDDEN_URLS[@]}"; do
        if [[ "$url" == *"$pattern"* ]]; then
            log_message "BLOCKED" "SSRF attempt: $url"
            update_stats "BLOCKED" "WebFetch"
            echo "BLOCKED: 禁止存取內部網路 - $url" >&2
            return 2
        fi
    done

    return 0
}

# ==========================================
# 主邏輯
# ==========================================

# 記錄所有工具呼叫
log_message "TOOL" "Tool: $TOOL_NAME"

case "$TOOL_NAME" in
    "Bash")
        command=$(echo "$TOOL_INPUT" | jq -r '.command // empty')
        if [ -n "$command" ]; then
            check_bash_safety "$command"
            result=$?
            if [[ $result -eq 0 ]]; then
                update_stats "ALLOWED" "Bash"
            fi
            exit $result
        fi
        ;;

    "Write"|"Edit")
        file_path=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')
        if [ -n "$file_path" ]; then
            check_file_safety "$file_path" "$TOOL_NAME"
            exit $?
        fi
        ;;

    "Read")
        file_path=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')
        if [ -n "$file_path" ]; then
            # Read 操作較寬鬆，但仍檢查敏感檔案
            check_file_safety "$file_path" "$TOOL_NAME"
            exit $?
        fi
        ;;

    "WebFetch")
        url=$(echo "$TOOL_INPUT" | jq -r '.url // empty')
        if [ -n "$url" ]; then
            check_network_safety "$url"
            result=$?
            if [[ $result -eq 0 ]]; then
                update_stats "ALLOWED" "WebFetch"
            fi
            exit $result
        fi
        ;;

    "Task")
        # Task 工具（啟動 subagent）- 記錄但允許
        subagent_type=$(echo "$TOOL_INPUT" | jq -r '.subagent_type // empty')
        log_message "INFO" "Task spawning subagent: $subagent_type"
        update_stats "ALLOWED" "Task"
        ;;

    "TodoWrite"|"Glob"|"Grep")
        # 安全的唯讀工具
        log_message "ALLOWED" "Safe tool: $TOOL_NAME"
        update_stats "ALLOWED" "$TOOL_NAME"
        ;;

    "mcp__"*)
        # MCP 工具 - 記錄並允許（MCP server 有自己的安全檢查）
        log_message "INFO" "MCP tool: $TOOL_NAME"
        update_stats "ALLOWED" "$TOOL_NAME"
        ;;

    *)
        # 其他工具預設允許但記錄
        log_message "PASS" "Tool $TOOL_NAME allowed by default"
        update_stats "ALLOWED" "$TOOL_NAME"
        ;;
esac

exit 0
