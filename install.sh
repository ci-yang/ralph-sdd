#!/usr/bin/env bash
#
# Ralph SDD Installer
# 安裝 Ralph SDD 到目標專案
#

set -euo pipefail

# 顏色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 取得腳本所在目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 預設值
TARGET_DIR=""
FORCE=false
UPDATE=false

usage() {
    cat << EOF
Ralph SDD Installer

Usage: ./install.sh [OPTIONS] [TARGET_DIR]

Options:
    -f, --force     覆蓋現有檔案
    -u, --update    更新模式（保留現有模板）
    -h, --help      顯示說明

Arguments:
    TARGET_DIR      目標專案目錄（預設：當前目錄）

Examples:
    ./install.sh                      # 安裝到當前目錄
    ./install.sh /path/to/project     # 安裝到指定目錄
    ./install.sh --update             # 更新現有安裝
EOF
}

log() {
    local level=$1
    shift
    local msg="$*"
    case $level in
        INFO)  echo -e "${BLUE}[INFO]${NC} $msg" ;;
        OK)    echo -e "${GREEN}[OK]${NC} $msg" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $msg" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $msg" ;;
    esac
}

check_prerequisites() {
    log INFO "檢查前置條件..."

    # 檢查 Claude CLI
    if ! command -v claude &> /dev/null; then
        log WARN "Claude CLI 未安裝，Ralph SDD 需要 Claude CLI 才能執行"
        log INFO "安裝方式: npm install -g @anthropic-ai/claude-code"
    fi

    # 檢查 jq
    if ! command -v jq &> /dev/null; then
        log ERROR "jq 未安裝，請先安裝: brew install jq"
        exit 1
    fi
}

install_ralph() {
    local target="$1"

    log INFO "安裝 Ralph SDD 到: $target"

    # 建立目錄
    mkdir -p "$target/.ralph/templates"
    mkdir -p "$target/.ralph/docs"
    mkdir -p "$target/.claude/hooks/scripts"

    # 複製主程式
    cp "$SCRIPT_DIR/ralph-sdd.sh" "$target/.ralph/"
    chmod +x "$target/.ralph/ralph-sdd.sh"
    log OK "已安裝 ralph-sdd.sh"

    # 複製模板
    if [[ "$UPDATE" == true && -f "$target/.ralph/templates/prompt-template.md" ]]; then
        log WARN "保留現有模板 (--update 模式)"
    else
        cp "$SCRIPT_DIR/templates/"*.md "$target/.ralph/templates/"
        log OK "已安裝模板"
    fi

    # 複製文件
    cp "$SCRIPT_DIR/docs/architecture.md" "$target/.ralph/docs/"
    log OK "已安裝文件"

    # 處理 hooks
    install_hooks "$target"

    # 建立 symlink（可選）
    if [[ ! -d "$target/scripts" ]]; then
        mkdir -p "$target/scripts"
    fi

    if [[ ! -L "$target/scripts/ralph" ]]; then
        ln -sf "../.ralph/ralph-sdd.sh" "$target/scripts/ralph"
        log OK "已建立 symlink: scripts/ralph"
    fi

    # 建立 README
    create_project_readme "$target"
}

install_hooks() {
    local target="$1"
    local hooks_file="$target/.claude/hooks/hooks.json"

    # 複製 hook 腳本
    cp "$SCRIPT_DIR/hooks/scripts/"*.sh "$target/.claude/hooks/scripts/"
    chmod +x "$target/.claude/hooks/scripts/"*.sh
    log OK "已安裝 hook 腳本"

    # 處理 hooks.json
    if [[ -f "$hooks_file" ]]; then
        log WARN "發現現有 hooks.json"

        if [[ "$FORCE" == true ]]; then
            cp "$SCRIPT_DIR/hooks/hooks.json" "$hooks_file"
            log OK "已覆蓋 hooks.json"
        else
            log INFO "請手動合併 hooks 配置，參考:"
            log INFO "  $SCRIPT_DIR/hooks/hooks.json"

            # 嘗試自動合併
            if merge_hooks "$target"; then
                log OK "已自動合併 hooks.json"
            else
                log WARN "無法自動合併，請手動處理"
            fi
        fi
    else
        cp "$SCRIPT_DIR/hooks/hooks.json" "$hooks_file"
        log OK "已安裝 hooks.json"
    fi
}

merge_hooks() {
    local target="$1"
    local existing="$target/.claude/hooks/hooks.json"
    local new_hooks="$SCRIPT_DIR/hooks/hooks.json"
    local backup="$existing.backup"

    # 備份
    cp "$existing" "$backup"

    # 使用 jq 合併（簡化版：只添加不存在的 hooks）
    if jq -s '
        .[0] as $existing |
        .[1] as $new |
        {
            hooks: (
                ($existing.hooks // []) +
                ($new.hooks // [] | map(select(
                    . as $h |
                    ($existing.hooks // []) |
                    map(.matcher) |
                    index($h.matcher) |
                    not
                )))
            )
        }
    ' "$existing" "$new_hooks" > "$existing.tmp" 2>/dev/null; then
        mv "$existing.tmp" "$existing"
        return 0
    else
        rm -f "$existing.tmp"
        mv "$backup" "$existing"
        return 1
    fi
}

create_project_readme() {
    local target="$1"
    local readme="$target/.ralph/README.md"

    cat > "$readme" << 'EOF'
# Ralph SDD - 無人值守 AI 開發

基於 [Geoffrey Huntley 的 Ralph Wiggum 技術](https://ghuntley.com/ralph/)。

## 快速開始

```bash
# 基本執行
./.ralph/ralph-sdd.sh

# 指定 Phase
./.ralph/ralph-sdd.sh --phase 11

# Dry run
./.ralph/ralph-sdd.sh --dry-run

# 使用 tmux 監控
./.ralph/ralph-sdd.sh --monitor
```

## 自訂模板

編輯 `.ralph/templates/prompt-template.md` 來自訂 AI 行為。

支援變數：
- `{{PHASE}}` - 當前 Phase
- `{{ITERATION}}` - 當前迭代
- `{{MAX_ITERATIONS}}` - 最大迭代
- `{{TASKS_FILE}}` - 任務檔案路徑

## 文件

- [架構設計](./docs/architecture.md)

---

*由 [ralph-sdd](https://github.com/ci-yang/ralph-sdd) 安裝*
EOF

    log OK "已建立 .ralph/README.md"
}

# 解析參數
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE=true
            shift
            ;;
        -u|--update)
            UPDATE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            log ERROR "未知選項: $1"
            usage
            exit 1
            ;;
        *)
            TARGET_DIR="$1"
            shift
            ;;
    esac
done

# 設定目標目錄
if [[ -z "$TARGET_DIR" ]]; then
    TARGET_DIR="$(pwd)"
fi

# 轉為絕對路徑
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
    log ERROR "目標目錄不存在: $TARGET_DIR"
    exit 1
}

# 確認不是安裝到自己
if [[ "$TARGET_DIR" == "$SCRIPT_DIR" ]]; then
    log ERROR "不能安裝到 ralph-sdd 本身"
    exit 1
fi

# 執行安裝
echo ""
echo "╔══════════════════════════════════════╗"
echo "║       Ralph SDD Installer            ║"
echo "╚══════════════════════════════════════╝"
echo ""

check_prerequisites
install_ralph "$TARGET_DIR"

echo ""
log OK "安裝完成！"
echo ""
echo "開始使用:"
echo "  cd $TARGET_DIR"
echo "  ./.ralph/ralph-sdd.sh --dry-run"
echo ""
