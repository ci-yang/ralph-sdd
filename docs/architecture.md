# Ralph SDD - 無人值守 AI 開發架構

> 基於 [Geoffrey Huntley 的 Ralph Wiggum 技術](https://ghuntley.com/ralph/)，整合 Spec-Driven Development (SDD) 流程的無人值守開發解決方案。

---

## 目錄

1. [設計理念](#設計理念)
2. [架構概覽](#架構概覽)
3. [核心元件](#核心元件)
4. [執行流程](#執行流程)
5. [安全機制](#安全機制)
6. [打包與安裝](#打包與安裝)
7. [與其他實作的比較](#與其他實作的比較)
8. [限制與注意事項](#限制與注意事項)

---

## 設計理念

### 問題：為什麼需要 Ralph Loop？

傳統的 AI 輔助開發有一個根本性的限制：

```
┌─────────────────────────────────────────────────────────────┐
│  傳統模式：人機交替                                          │
│                                                             │
│  人類 → AI → 人類 → AI → 人類 → AI → ...                    │
│   │      │     │      │     │                               │
│   ↓      ↓     ↓      ↓     ↓                               │
│  提問  回答  確認  執行  檢查                                 │
│                                                             │
│  問題：每一步都需要人類參與，無法離開                         │
└─────────────────────────────────────────────────────────────┘
```

當任務量大（例如 100+ 個開發任務）時，這種模式效率極低。

### 解法：外部迴圈強制持續

Ralph Wiggum Loop 的核心理念是：**用外部腳本控制 AI，而不是依賴 AI 的「自律」**。

```
┌─────────────────────────────────────────────────────────────┐
│  Ralph 模式：外部迴圈控制                                    │
│                                                             │
│  ┌──────────────────────────────────────────────┐           │
│  │  Bash Script (外部迴圈)                       │           │
│  │                                              │           │
│  │  while [未完成]; do                          │           │
│  │      claude --dangerously-skip-permissions   │ ←─┐       │
│  │      分析輸出                                │   │       │
│  │      決定是否繼續                            │ ──┘       │
│  │  done                                        │           │
│  └──────────────────────────────────────────────┘           │
│                                                             │
│  人類只需要：啟動腳本，然後離開                               │
└─────────────────────────────────────────────────────────────┘
```

### 核心原則

| 原則 | 說明 |
|------|------|
| **外部控制** | 迴圈由 Bash 腳本控制，不依賴 AI 自己決定是否繼續 |
| **Promise 協議** | AI 用 `<promise>` 標籤告知狀態，腳本據此決定行為 |
| **安全護欄** | 使用 Hooks 阻擋危險操作，即使跳過權限確認也安全 |
| **可觀測性** | 狀態追蹤、日誌記錄，隨時可以了解進度 |
| **Circuit Breaker** | 自動偵測卡住狀態，防止無限迴圈 |

---

## 架構概覽

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Terminal (使用者啟動)                        │
│                                                                     │
│  $ ./scripts/ralph-sdd.sh --phase 11                                │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│                      ralph-sdd.sh (外部迴圈)                         │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Iteration 1                                                 │   │
│  │    ├── 讀取 tasks.md，計算剩餘任務                            │   │
│  │    ├── 執行: claude --dangerously-skip-permissions -p "..."  │   │
│  │    ├── 捕獲輸出，偵測 <promise> 標籤                          │   │
│  │    ├── 更新 .ralph/status.json                               │   │
│  │    └── 判斷：CONTINUE → 繼續 / COMPLETE → 停止               │   │
│  ├─────────────────────────────────────────────────────────────┤   │
│  │  Iteration 2                                                 │   │
│  │    └── ...                                                   │   │
│  ├─────────────────────────────────────────────────────────────┤   │
│  │  Iteration N                                                 │   │
│  │    └── 偵測到 <promise>PHASE COMPLETE</promise> → 停止       │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  Circuit Breaker: 連續 5 次無進度 → 自動停止                         │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│                      Claude Code (AI 執行層)                         │
│                                                                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │
│  │  PreToolUse     │  │  Tool 執行       │  │  PostToolUse    │     │
│  │  Hooks          │  │                 │  │  Hooks          │     │
│  │                 │  │  Bash           │  │                 │     │
│  │  safety-guard   │→ │  Write          │→ │  progress-      │     │
│  │  .sh            │  │  Edit           │  │  tracker.sh     │     │
│  │                 │  │  Read           │  │                 │     │
│  │  阻擋危險操作   │  │  WebFetch       │  │  追蹤進度       │     │
│  │                 │  │  ...            │  │  提醒 commit    │     │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘     │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Stop Hook                                                   │   │
│  │  強制 AI 在結束前輸出 <promise> 標籤                          │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│                          專案檔案系統                                 │
│                                                                     │
│  specs/                          .ralph/                            │
│  └── {feature}/                  ├── status.json    # 執行狀態      │
│      ├── spec.md                 ├── ralph-sdd.log  # 執行日誌      │
│      ├── plan.md                 └── .safety_stats  # 安全統計      │
│      └── tasks.md ←── 讀取任務                                      │
│                                                                     │
│  src/                            .claude/                           │
│  └── ... ←── 寫入程式碼          └── hooks/                         │
│                                      ├── hooks.json                 │
│                                      └── scripts/                   │
│                                          ├── safety-guard.sh        │
│                                          └── progress-tracker.sh    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 核心元件

### 1. ralph-sdd.sh（外部迴圈腳本）

**位置**：`scripts/ralph-sdd.sh`

**職責**：
- 讀取 `tasks.md` 計算任務進度
- 載入 prompt 模板並進行變數替換
- 執行 `claude --dangerously-skip-permissions`
- 分析輸出中的 `<promise>` 標籤
- 維護狀態檔案 `.ralph/status.json`
- 實作 Circuit Breaker 防止無限迴圈

**Prompt 模板機制**：

腳本支援自定義 prompt 模板，讓不同專案可以客製化 Claude 的行為：

```bash
# 使用自定義模板
./scripts/ralph-sdd.sh --prompt-template ./my-template.md

# 或放在預設位置（自動偵測）
.ralph/prompt-template.md
```

模板支援的變數：

| 變數 | 說明 |
|------|------|
| `{{PHASE}}` | 當前執行的 Phase |
| `{{ITERATION}}` | 當前迭代次數 |
| `{{MAX_ITERATIONS}}` | 最大迭代次數 |
| `{{TASKS_FILE}}` | 任務檔案路徑 |

**關鍵程式碼邏輯**：

```bash
main_loop() {
    local iteration=1
    local consecutive_no_progress=0

    while [[ $iteration -le $MAX_ITERATIONS ]]; do
        # 執行 Claude
        output=$(claude --dangerously-skip-permissions -p "$PROMPT")

        # 分析 Promise 標籤
        if echo "$output" | grep -q "<promise>PHASE COMPLETE</promise>"; then
            log "Phase 完成！"
            break
        elif echo "$output" | grep -q "<promise>BLOCKED"; then
            log "遇到阻塞，停止執行"
            break
        elif echo "$output" | grep -q "<promise>CONTINUE</promise>"; then
            consecutive_no_progress=0  # 重置計數器
        else
            ((consecutive_no_progress++))
        fi

        # Circuit Breaker
        if [[ $consecutive_no_progress -ge 5 ]]; then
            log "連續 5 次無進度，觸發 Circuit Breaker"
            break
        fi

        ((iteration++))
    done
}
```

### 2. safety-guard.sh（安全護欄）

**位置**：`.claude/hooks/scripts/safety-guard.sh`

**職責**：
- 在 `PreToolUse` 階段攔截危險操作
- 阻擋危險的 Bash 命令
- 保護敏感檔案
- 防止 SSRF 攻擊

**阻擋規則**：

| 類別 | 範例 |
|------|------|
| 破壞性刪除 | `rm -rf /`, `sudo rm` |
| 權限提升 | `sudo su`, `chmod 777` |
| 遠端程式碼執行 | `curl \| sh`, `eval $(curl ...)` |
| Git 危險操作 | `git push --force`, `git reset --hard` |
| 敏感檔案 | `.env`, `id_rsa`, `*.pem`, `credentials.json` |
| SSRF | `localhost`, `169.254.169.254`, 內網 IP |

**Exit Codes**：
- `0` = 允許執行
- `2` = 阻擋執行

### 3. progress-tracker.sh（進度追蹤）

**位置**：`.claude/hooks/scripts/progress-tracker.sh`

**職責**：
- 在 `PostToolUse` 階段追蹤檔案變更
- 記錄 Write/Edit 操作
- 提醒執行 Atomic Commit

### 4. hooks.json（Hooks 配置）

**位置**：`.claude/hooks/hooks.json`

**結構**：

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "command": "safety-guard.sh" }] },
      { "matcher": "Write|Edit|Read", "hooks": [{ "command": "safety-guard.sh" }] },
      { "matcher": "WebFetch", "hooks": [{ "command": "safety-guard.sh" }] }
    ],
    "PostToolUse": [
      { "matcher": "Write|Edit", "hooks": [{ "command": "progress-tracker.sh" }] }
    ],
    "Stop": [
      { "matcher": "*", "hooks": [{ "type": "prompt", "prompt": "輸出 <promise> 標籤..." }] }
    ]
  }
}
```

### 5. Promise 協議

AI 在每次迭代結束時必須輸出 Promise 標籤：

| 標籤 | 意義 | 腳本行為 |
|------|------|----------|
| `<promise>CONTINUE</promise>` | 還有任務未完成 | 繼續下一次迭代 |
| `<promise>PHASE COMPLETE</promise>` | 當前 Phase 完成 | 停止迴圈 |
| `<promise>E2E PASSED</promise>` | E2E 測試通過 | 停止迴圈 |
| `<promise>E2E FAILED: [reason]</promise>` | E2E 測試失敗 | 嘗試修復或停止 |
| `<promise>BLOCKED: [reason]</promise>` | 遇到無法解決的問題 | 停止迴圈 |

---

## 執行流程

### 完整開發流程

```
┌─────────────────────────────────────────────────────────────────────┐
│  Phase A-D4: 在 Claude Code 互動模式完成規劃                         │
│                                                                     │
│  $ claude                                                           │
│  > /idea-brainstorm ...      # 靈感發想                             │
│  > /product-plan ...         # 產品規劃                             │
│  > /speckit.specify ...      # 建立規格                             │
│  > /speckit.plan             # 技術規劃                             │
│  > /speckit.tasks            # 產生任務                             │
│  > exit                                                             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ↓ 切換到 Terminal（僅此一次）
┌─────────────────────────────────────────────────────────────────────┐
│  Phase D5-D6: 在 Terminal 執行 Ralph Loop                           │
│                                                                     │
│  $ ./scripts/ralph-sdd.sh --phase 2                                 │
│                                                                     │
│  # 可以離開去做別的事...                                             │
│  # 稍後回來查看 .ralph/status.json 或 git log                        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Ralph Loop 內部流程

```
開始
  │
  ↓
讀取 tasks.md
  │
  ↓
計算待處理任務 ──→ 0 個 ──→ 結束
  │
  ↓ > 0 個
執行 Claude CLI
  │
  ↓
Claude 執行任務
  │
  ├── PreToolUse Hook: 安全檢查
  │     ├── 通過 → 執行工具
  │     └── 阻擋 → 跳過該操作
  │
  ├── Tool 執行
  │
  └── PostToolUse Hook: 進度追蹤
  │
  ↓
Claude 輸出結果 + <promise> 標籤
  │
  ↓
腳本分析輸出
  │
  ├── CONTINUE → 回到「執行 Claude CLI」
  ├── PHASE COMPLETE → 執行 E2E 測試 → 結束
  ├── BLOCKED → 記錄原因 → 結束
  └── 無標籤 → 計數器 +1
        │
        ↓
      計數器 >= 5？
        ├── 是 → Circuit Breaker 觸發 → 結束
        └── 否 → 回到「執行 Claude CLI」
```

---

## 安全機制

### 為什麼需要安全機制？

`--dangerously-skip-permissions` 會跳過所有互動式確認，AI 可以直接：
- 執行任何 Bash 命令
- 讀寫任何檔案
- 存取任何 URL

這在無人值守時非常危險，因此需要 Hooks 作為安全護欄。

### 防護層級

```
┌─────────────────────────────────────────────────────────────────────┐
│  Level 1: 命令層級防護 (Bash)                                        │
│                                                                     │
│  阻擋：rm -rf, sudo, git push --force, curl|sh, ...                 │
│  允許：pnpm, npm, git status/add/commit, node, vitest, ...          │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│  Level 2: 檔案層級防護 (Write/Edit/Read)                             │
│                                                                     │
│  阻擋：.env, id_rsa, *.pem, credentials.json, ...                   │
│  阻擋：專案目錄外的檔案                                              │
│  阻擋：路徑穿越 (../)                                                │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│  Level 3: 網路層級防護 (WebFetch)                                    │
│                                                                     │
│  阻擋：localhost, 127.0.0.1, 內網 IP, metadata endpoint             │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│  Level 4: 迴圈層級防護 (Circuit Breaker)                             │
│                                                                     │
│  連續 5 次無進度 → 自動停止                                          │
│  達到最大迭代次數 → 自動停止                                         │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 安全統計

每次執行後，安全統計記錄於 `.ralph/.safety_stats`：

```json
{
  "allowed": 156,
  "blocked": 3,
  "tools": {
    "Bash": { "allowed": 45, "blocked": 2 },
    "Write": { "allowed": 67, "blocked": 1 },
    "Edit": { "allowed": 44, "blocked": 0 }
  }
}
```

---

## 打包與安裝

### 檔案結構

```
ralph-sdd/
├── install.sh                  # 一鍵安裝腳本
├── scripts/
│   └── ralph-sdd.sh           # 外部迴圈（核心）
├── hooks/
│   ├── hooks.json             # Claude Code hooks 配置
│   └── scripts/
│       ├── safety-guard.sh    # 安全護欄
│       └── progress-tracker.sh # 進度追蹤
├── templates/
│   ├── prompt-template.md         # 預設 prompt 模板
│   ├── prompt-template.generic.md # 通用模板範例
│   └── status.json                # 狀態檔案模板
└── README.md                  # 使用說明
```

### Prompt 模板客製化

其他專案安裝後，可以根據需求修改 `.ralph/prompt-template.md`：

```markdown
# 範例：Next.js 專案模板

執行 Next.js 開發任務。

任務檔案: {{TASKS_FILE}}

規則：
1. 使用 App Router 架構
2. 優先使用 Server Components
3. 遵循 TypeScript 嚴格模式
4. 執行 Phase {{PHASE}} 中的 [ ] 任務

迭代: {{ITERATION}} / {{MAX_ITERATIONS}}

完成後輸出 <promise>CONTINUE</promise> 或 <promise>PHASE COMPLETE</promise>
```

### 安裝方式

**方式 1：Clone + Install**

```bash
git clone https://github.com/user/ralph-sdd.git /tmp/ralph-sdd
/tmp/ralph-sdd/install.sh
```

**方式 2：一行安裝**

```bash
curl -fsSL https://raw.githubusercontent.com/user/ralph-sdd/main/install.sh | bash
```

### install.sh 邏輯

```bash
#!/bin/bash
set -euo pipefail

PROJECT_ROOT="${1:-$(pwd)}"

# 複製腳本
mkdir -p "$PROJECT_ROOT/scripts"
cp scripts/ralph-sdd.sh "$PROJECT_ROOT/scripts/"
chmod +x "$PROJECT_ROOT/scripts/ralph-sdd.sh"

# 複製 hooks
mkdir -p "$PROJECT_ROOT/.claude/hooks/scripts"
cp hooks/hooks.json "$PROJECT_ROOT/.claude/hooks/"
cp hooks/scripts/*.sh "$PROJECT_ROOT/.claude/hooks/scripts/"
chmod +x "$PROJECT_ROOT/.claude/hooks/scripts/"*.sh

# 建立 .ralph 目錄
mkdir -p "$PROJECT_ROOT/.ralph"

echo "Ralph SDD 安裝完成！"
echo "執行: ./scripts/ralph-sdd.sh --dry-run"
```

---

## 與其他實作的比較

| 特點 | Ralph SDD | snarktank/ralph | frankbria/ralph-claude-code |
|------|-----------|-----------------|------------------------------|
| **迴圈控制** | Bash while | Bash for | Bash while |
| **任務格式** | tasks.md (SDD) | prd.json | fix_plan.md |
| **安全護欄** | ✅ Hooks | ❌ 無 | ❌ 無 |
| **Promise 偵測** | grep | grep | JSON 解析 |
| **Circuit Breaker** | ✅ 5 次無進度 | ❌ 無 | ✅ 有 |
| **狀態追蹤** | status.json | ❌ 無 | ✅ 有 |
| **Rate Limiting** | ❌ 無 | ❌ 無 | ✅ 100/hour |
| **tmux 整合** | ✅ --monitor | ❌ 無 | ✅ 有 |
| **SDD 整合** | ✅ 原生 | ❌ 無 | ❌ 無 |
| **E2E 測試** | ✅ Playwright | ❌ 無 | ❌ 無 |

---

## 限制與注意事項

### 已知限制

1. **需要 tasks.md**：必須先執行 SDD 流程產生 tasks.md
2. **單一專案**：一次只能在一個專案中執行
3. **無 Rate Limiting**：高頻執行可能觸發 API 限制
4. **依賴 Git**：路徑偵測使用 `git rev-parse`

### 注意事項

1. **首次使用先 Dry Run**：
   ```bash
   ./scripts/ralph-sdd.sh --dry-run
   ```

2. **設定合理的 max-iterations**：
   ```bash
   ./scripts/ralph-sdd.sh --max-iterations 20
   ```

3. **監控執行狀態**：
   ```bash
   # 查看狀態
   cat .ralph/status.json

   # 查看日誌
   tail -f .ralph/ralph-sdd.log
   ```

4. **緊急停止**：
   ```bash
   # Ctrl+C 或
   pkill -f ralph-sdd.sh
   ```

---

## 版本歷史

| 版本 | 日期 | 說明 |
|------|------|------|
| 1.0.0 | 2026-01-28 | 初始版本：整合 SDD + 安全護欄 + Circuit Breaker |

---

## 參考資料

- [Geoffrey Huntley - Ralph Wiggum Technique](https://ghuntley.com/ralph/)
- [snarktank/ralph](https://github.com/snarktank/ralph)
- [frankbria/ralph-claude-code](https://github.com/frankbria/ralph-claude-code)
- [doggy8088/copilot-ralph](https://github.com/doggy8088/copilot-ralph)

---

*此文件描述 Ralph SDD 的設計理念與架構，供團隊參考或打包成獨立工具使用。*
