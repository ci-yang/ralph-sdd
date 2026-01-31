# Generic Ralph Prompt Template
#
# 這是一個通用模板範例，適用於任何專案。
# 複製此檔案到 .ralph/prompt-template.md 並根據需求修改。
#
# 變數說明：
#   {{PHASE}}          - 當前執行的 Phase（可選）
#   {{ITERATION}}      - 當前迭代次數
#   {{MAX_ITERATIONS}} - 最大迭代次數
#   {{TASKS_FILE}}     - 任務檔案路徑

請執行任務檔案中的待辦事項。

任務檔案: {{TASKS_FILE}}

## 執行規則

1. 找到檔案中第一個標記為 [ ] 的任務
2. 完成任務後，將其標記為 [x]
3. 繼續執行下一個任務，直到所有任務完成或遇到問題

## 完成後的輸出

在回應最後，請輸出以下其中一個標籤（獨立一行）：

```
<promise>CONTINUE</promise>      - 還有任務未完成
<promise>PHASE COMPLETE</promise> - 所有任務已完成
<promise>BLOCKED: [原因]</promise> - 遇到無法解決的問題
```

## 當前進度

迭代: {{ITERATION}} / {{MAX_ITERATIONS}}

---

# 以下是一些常見的自定義範例：

## 範例 1：針對特定框架（如 Next.js）

```markdown
請執行以下 Next.js 開發任務：

任務檔案: {{TASKS_FILE}}

規則：
1. 使用 App Router 架構
2. 優先使用 Server Components
3. 遵循專案的 TypeScript 嚴格模式

完成後輸出 <promise>CONTINUE</promise> 或 <promise>PHASE COMPLETE</promise>
```

## 範例 2：針對 Bug 修復

```markdown
請修復任務檔案中列出的 bug：

任務檔案: {{TASKS_FILE}}

規則：
1. 先寫測試重現 bug
2. 修復 bug
3. 確認測試通過
4. 標記任務完成

完成後輸出適當的 promise 標籤。
```

## 範例 3：針對重構任務

```markdown
請執行程式碼重構任務：

任務檔案: {{TASKS_FILE}}

規則：
1. 確保所有測試仍然通過
2. 不改變外部行為
3. 每個小步驟都提交

迭代: {{ITERATION}} / {{MAX_ITERATIONS}}

完成後輸出 <promise>CONTINUE</promise> 或 <promise>PHASE COMPLETE</promise>
```
