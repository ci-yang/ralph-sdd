# Ralph SDD

**無人值守 AI 開發** - 基於 [Geoffrey Huntley 的 Ralph Wiggum 技術](https://ghuntley.com/ralph/)

讓 Claude Code 在外部 Bash 迴圈中持續執行，直到所有任務完成，實現真正的無人值守開發。

## 特色

- **外部迴圈控制** - Bash 腳本持續執行 Claude，不受 context 限制
- **Promise 協議** - 透過 `<promise>` 標籤控制迴圈行為
- **安全護欄** - Hooks 阻擋危險操作，即使使用 `--dangerously-skip-permissions`
- **可自訂模板** - 支援變數替換，適用於任何專案
- **進度追蹤** - 即時狀態、Circuit Breaker 防止無限迴圈

## 快速安裝

### 方式 1: Clone 後安裝

```bash
git clone https://github.com/anthropics/ralph-sdd.git
cd ralph-sdd
./install.sh /path/to/your/project
```

### 方式 2: 一行安裝

```bash
curl -fsSL https://raw.githubusercontent.com/anthropics/ralph-sdd/main/install.sh | bash -s -- /path/to/your/project
```

### 方式 3: Git Submodule

```bash
cd your-project
git submodule add https://github.com/anthropics/ralph-sdd.git .ralph-sdd
./.ralph-sdd/install.sh .
```

## 使用方式

```bash
# 基本執行（自動偵測未完成任務）
./.ralph/ralph-sdd.sh

# 執行指定 Phase
./.ralph/ralph-sdd.sh --phase 11

# Dry run（預覽配置）
./.ralph/ralph-sdd.sh --dry-run

# 使用 tmux 監控
./.ralph/ralph-sdd.sh --monitor

# 限制迭代次數
./.ralph/ralph-sdd.sh --max-iterations 20

# 使用自訂模板
./.ralph/ralph-sdd.sh --prompt-template ./my-template.md
```

## 自訂 Prompt 模板

編輯 `.ralph/templates/prompt-template.md`：

```markdown
執行任務，專注於 Phase {{PHASE}} 的未完成任務。

任務檔案: {{TASKS_FILE}}

規則：
1. 只執行標記為 [ ] 的任務
2. 完成後標記為 [x]
3. 輸出 <promise>CONTINUE</promise> 或 <promise>PHASE COMPLETE</promise>

迭代: {{ITERATION}} / {{MAX_ITERATIONS}}
```

### 支援變數

| 變數 | 說明 |
|------|------|
| `{{PHASE}}` | 當前 Phase |
| `{{ITERATION}}` | 當前迭代次數 |
| `{{MAX_ITERATIONS}}` | 最大迭代次數 |
| `{{TASKS_FILE}}` | 任務檔案路徑 |

## Promise 標籤

| 標籤 | 意義 | 迴圈行為 |
|------|------|----------|
| `<promise>CONTINUE</promise>` | 還有任務未完成 | 繼續執行 |
| `<promise>PHASE COMPLETE</promise>` | Phase 完成 | 停止 |
| `<promise>BLOCKED: [原因]</promise>` | 遇到問題 | 停止 |

## 安全機制

即使使用 `--dangerously-skip-permissions`，Hooks 仍會保護：

| 保護類型 | 說明 |
|----------|------|
| **危險命令** | `rm -rf /`、`sudo`、`git push --force` |
| **敏感檔案** | `.env`、SSH 金鑰、雲端憑證 |
| **SSRF** | 內網存取 |
| **Circuit Breaker** | 連續 5 次無進度自動停止 |

## 狀態追蹤

執行狀態記錄於 `.ralph/status.json`：

```json
{
  "iteration": 5,
  "phase": "11",
  "status": "running",
  "tasks": { "total": 119, "completed": 112, "pending": 7 }
}
```

## 目錄結構

安裝後的專案結構：

```
your-project/
├── .ralph/
│   ├── ralph-sdd.sh          # 主執行腳本
│   ├── templates/
│   │   └── prompt-template.md
│   ├── docs/
│   │   └── architecture.md
│   └── status.json           # 執行狀態（自動產生）
├── .claude/
│   └── hooks/
│       ├── hooks.json        # Hooks 配置
│       └── scripts/
│           ├── safety-guard.sh
│           └── progress-tracker.sh
└── scripts/
    └── ralph -> ../.ralph/ralph-sdd.sh
```

## 前置需求

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- [jq](https://stedolan.github.io/jq/) - JSON 處理工具
- Bash 4.0+

## 與其他工具整合

### spec-kit

Ralph SDD 與 [spec-kit](https://github.com/anthropics/spec-kit) 搭配使用效果最佳：

```bash
# 1. 使用 spec-kit 產生任務
/speckit.specify
/speckit.plan
/speckit.tasks

# 2. 使用 Ralph 執行
./.ralph/ralph-sdd.sh
```

### 其他任務系統

只要任務檔案有明確的完成標記（如 `[ ]` / `[x]`），Ralph 都能使用。

## 貢獻

歡迎提交 Issue 和 PR！

## 授權

MIT License

---

*靈感來自 [Geoffrey Huntley 的 Ralph Wiggum 技術](https://ghuntley.com/ralph/)*
