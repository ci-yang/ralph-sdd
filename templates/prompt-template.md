# Ralph SDD Prompt Template
#
# 變數說明：
#   {{PHASE}}          - 當前執行的 Phase
#   {{ITERATION}}      - 當前迭代次數
#   {{MAX_ITERATIONS}} - 最大迭代次數
#   {{TASKS_FILE}}     - 任務檔案路徑
#
# 此模板適用於使用 spec-kit SDD 流程的專案

執行 /speckit.implement，專注於 Phase {{PHASE}} 的未完成任務。

任務檔案: {{TASKS_FILE}}

## 規則

1. 只執行 Phase {{PHASE}} 中標記為 [ ] 的任務
2. 每完成一個任務，立即在 tasks.md 中標記為 [x]
3. 遵循 TDD 原則：先寫測試，再實作
4. 每完成一組相關任務後執行 atomic commit

## Promise 標籤（必須輸出）

在回應最後，根據狀態輸出對應的 promise 標籤（獨立一行）：

- 如果 Phase {{PHASE}} 所有任務完成：`<promise>PHASE COMPLETE</promise>`
- 如果還有任務未完成：`<promise>CONTINUE</promise>`
- 如果遇到無法解決的問題：`<promise>BLOCKED: [原因]</promise>`

## 當前狀態

迭代: {{ITERATION}} / {{MAX_ITERATIONS}}
