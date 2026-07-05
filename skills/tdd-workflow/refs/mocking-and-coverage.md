# Mock、覆蓋率與持續測試

外部服務 Mock 模式、測試覆蓋率驗證與門檻、常見測試錯誤避免，以及持續測試設定。

## Mock 外部服務

### Supabase Mock
```typescript
jest.mock('@/lib/supabase', () => ({
  supabase: {
    from: jest.fn(() => ({
      select: jest.fn(() => ({
        eq: jest.fn(() => Promise.resolve({
          data: [{ id: 1, name: 'Test Market' }],
          error: null
        }))
      }))
    }))
  }
}))
```

### Redis Mock
```typescript
jest.mock('@/lib/redis', () => ({
  searchMarketsByVector: jest.fn(() => Promise.resolve([
    { slug: 'test-market', similarity_score: 0.95 }
  ])),
  checkRedisHealth: jest.fn(() => Promise.resolve({ connected: true }))
}))
```

### OpenAI Mock
```typescript
jest.mock('@/lib/openai', () => ({
  generateEmbedding: jest.fn(() => Promise.resolve(
    new Array(1536).fill(0.1) // Mock 1536 維嵌入向量
  ))
}))
```

## 測試覆蓋率驗證

### 執行覆蓋率報告
```bash
npm run test:coverage
```

### 覆蓋率門檻
```json
{
  "jest": {
    "coverageThresholds": {
      "global": {
        "branches": 80,
        "functions": 80,
        "lines": 80,
        "statements": 80
      }
    }
  }
}
```

## 常見測試錯誤避免

### ❌ 錯誤：測試實作細節
```typescript
// 不要測試內部狀態
expect(component.state.count).toBe(5)
```

### ✅ 正確：測試使用者可見行為
```typescript
// 測試使用者看到的內容
expect(screen.getByText('Count: 5')).toBeInTheDocument()
```

### ❌ 錯誤：脆弱的選擇器
```typescript
// 容易壞掉
await page.click('.css-class-xyz')
```

### ✅ 正確：語意選擇器
```typescript
// 對變更有彈性
await page.click('button:has-text("Submit")')
await page.click('[data-testid="submit-button"]')
```

### ❌ 錯誤：無測試隔離
```typescript
// 測試互相依賴
test('creates user', () => { /* ... */ })
test('updates same user', () => { /* 依賴前一個測試 */ })
```

### ✅ 正確：獨立測試
```typescript
// 每個測試設置自己的資料
test('creates user', () => {
  const user = createTestUser()
  // 測試邏輯
})

test('updates user', () => {
  const user = createTestUser()
  // 更新邏輯
})
```

## 持續測試

### 開發期間的 Watch 模式
```bash
npm test -- --watch
# 檔案變更時自動執行測試
```

### Pre-Commit Hook
```bash
# 每次 commit 前執行
npm test && npm run lint
```

### CI/CD 整合
```yaml
# GitHub Actions
- name: Run Tests
  run: npm test -- --coverage
- name: Upload Coverage
  uses: codecov/codecov-action@v3
```
