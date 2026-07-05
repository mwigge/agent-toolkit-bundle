---
name: tdd-workflow
description: Use this skill when writing new features, fixing bugs, or refactoring code. Enforces test-driven development with 80%+ coverage including unit, integration, and E2E tests.
---

# 測試驅動開發工作流程

此技能確保所有程式碼開發遵循 TDD 原則，並具有完整的測試覆蓋率。

## 何時啟用

- 撰寫新功能或功能性程式碼
- 修復 Bug 或問題
- 重構現有程式碼
- 新增 API 端點
- 建立新元件

---

## 核心原則

### 1. 測試先於程式碼
總是先寫測試，然後實作程式碼使測試通過。

### 2. 覆蓋率要求
- 最低 80% 覆蓋率（單元 + 整合 + E2E）
- 涵蓋所有邊界案例
- 測試錯誤情境
- 驗證邊界條件

### 3. 測試類型

#### 單元測試
- 個別函式和工具
- 元件邏輯
- 純函式
- 輔助函式和工具

#### 整合測試
- API 端點
- 資料庫操作
- 服務互動
- 外部 API 呼叫

#### E2E 測試（Playwright）
- 關鍵使用者流程
- 完整工作流程
- 瀏覽器自動化
- UI 互動

## TDD 工作流程步驟

### 步驟 1：撰寫使用者旅程
```
身為 [角色]，我想要 [動作]，以便 [好處]

範例：
身為使用者，我想要語意搜尋市場，
以便即使沒有精確關鍵字也能找到相關市場。
```

### 步驟 2：產生測試案例
為每個使用者旅程建立完整的測試案例：

```typescript
describe('Semantic Search', () => {
  it('returns relevant markets for query', async () => {
    // 測試實作
  })

  it('handles empty query gracefully', async () => {
    // 測試邊界案例
  })

  it('falls back to substring search when Redis unavailable', async () => {
    // 測試回退行為
  })

  it('sorts results by similarity score', async () => {
    // 測試排序邏輯
  })
})
```

### 步驟 3：執行測試（應該失敗）
```bash
npm test
# 測試應該失敗 - 我們還沒實作
```

### 步驟 4：實作程式碼
撰寫最少的程式碼使測試通過：

```typescript
// 由測試引導的實作
export async function searchMarkets(query: string) {
  // 實作在此
}
```

### 步驟 5：再次執行測試
```bash
npm test
# 測試現在應該通過
```

### 步驟 6：重構
在保持測試通過的同時改善程式碼品質：
- 移除重複
- 改善命名
- 優化效能
- 增強可讀性

### 步驟 7：驗證覆蓋率
```bash
npm run test:coverage
# 驗證達到 80%+ 覆蓋率
```

## 延伸參考

深入的程式碼範例與參考資料存放於companion檔案，按需載入。

- 測試模式（單元／API／E2E 範例）與測試檔案組織：見 `refs/test-patterns.md`。
- Mock 外部服務、測試覆蓋率驗證與門檻、常見測試錯誤避免、持續測試設定：見 `refs/mocking-and-coverage.md`。
- 品質度量（defect density、defect leakage、test effectiveness、MTTD、風險優先級、shift-left、mutation testing）：見 `refs/quality-metrics.md`。

## 最佳實務

1. **先寫測試** - 總是 TDD
2. **一個測試一個斷言** - 專注單一行為
3. **描述性測試名稱** - 解釋測試內容
4. **Arrange-Act-Assert** - 清晰的測試結構
5. **Mock 外部依賴** - 隔離單元測試
6. **測試邊界案例** - Null、undefined、空值、大值
7. **測試錯誤路徑** - 不只是快樂路徑
8. **保持測試快速** - 單元測試每個 < 50ms
9. **測試後清理** - 無副作用
10. **檢視覆蓋率報告** - 識別缺口

## 成功指標

- 達到 80%+ 程式碼覆蓋率
- 所有測試通過（綠色）
- 無跳過或停用的測試
- 快速測試執行（單元測試 < 30s）
- E2E 測試涵蓋關鍵使用者流程
- 測試在生產前捕捉 Bug

---

**記住**：測試不是可選的。它們是實現自信重構、快速開發和生產可靠性的安全網。

## 參考資料

- `refs/REFERENCES.md` — 外部文件連結（external documentation links）
