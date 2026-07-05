# 測試模式與檔案組織

單元測試、API 整合測試、E2E 測試的完整範例模式，以及測試檔案組織結構。

## 測試模式

### 單元測試模式（Jest/Vitest）
```typescript
import { render, screen, fireEvent } from '@testing-library/react'
import { Button } from './Button'

describe('Button Component', () => {
  it('renders with correct text', () => {
    render(<Button>Click me</Button>)
    expect(screen.getByText('Click me')).toBeInTheDocument()
  })

  it('calls onClick when clicked', () => {
    const handleClick = jest.fn()
    render(<Button onClick={handleClick}>Click</Button>)

    fireEvent.click(screen.getByRole('button'))

    expect(handleClick).toHaveBeenCalledTimes(1)
  })

  it('is disabled when disabled prop is true', () => {
    render(<Button disabled>Click</Button>)
    expect(screen.getByRole('button')).toBeDisabled()
  })
})
```

### API 整合測試模式
```typescript
import { NextRequest } from 'next/server'
import { GET } from './route'

describe('GET /api/markets', () => {
  it('returns markets successfully', async () => {
    const request = new NextRequest('http://localhost/api/markets')
    const response = await GET(request)
    const data = await response.json()

    expect(response.status).toBe(200)
    expect(data.success).toBe(true)
    expect(Array.isArray(data.data)).toBe(true)
  })

  it('validates query parameters', async () => {
    const request = new NextRequest('http://localhost/api/markets?limit=invalid')
    const response = await GET(request)

    expect(response.status).toBe(400)
  })

  it('handles database errors gracefully', async () => {
    // Mock 資料庫失敗
    const request = new NextRequest('http://localhost/api/markets')
    // 測試錯誤處理
  })
})
```

### E2E 測試模式（Playwright）
```typescript
import { test, expect } from '@playwright/test'

test('user can search and filter markets', async ({ page }) => {
  // 導航到市場頁面
  await page.goto('/')
  await page.click('a[href="/markets"]')

  // 驗證頁面載入
  await expect(page.locator('h1')).toContainText('Markets')

  // 搜尋市場
  await page.fill('input[placeholder="Search markets"]', 'election')

  // 等待 debounce 和結果
  await page.waitForTimeout(600)

  // 驗證搜尋結果顯示
  const results = page.locator('[data-testid="market-card"]')
  await expect(results).toHaveCount(5, { timeout: 5000 })

  // 驗證結果包含搜尋詞
  const firstResult = results.first()
  await expect(firstResult).toContainText('election', { ignoreCase: true })

  // 依狀態篩選
  await page.click('button:has-text("Active")')

  // 驗證篩選結果
  await expect(results).toHaveCount(3)
})

test('user can create a new market', async ({ page }) => {
  // 先登入
  await page.goto('/creator-dashboard')

  // 填寫市場建立表單
  await page.fill('input[name="name"]', 'Test Market')
  await page.fill('textarea[name="description"]', 'Test description')
  await page.fill('input[name="endDate"]', '2025-12-31')

  // 提交表單
  await page.click('button[type="submit"]')

  // 驗證成功訊息
  await expect(page.locator('text=Market created successfully')).toBeVisible()

  // 驗證重導向到市場頁面
  await expect(page).toHaveURL(/\/markets\/test-market/)
})
```

## 測試檔案組織

```
src/
├── components/
│   ├── Button/
│   │   ├── Button.tsx
│   │   ├── Button.test.tsx          # 單元測試
│   │   └── Button.stories.tsx       # Storybook
│   └── MarketCard/
│       ├── MarketCard.tsx
│       └── MarketCard.test.tsx
├── app/
│   └── api/
│       └── markets/
│           ├── route.ts
│           └── route.test.ts         # 整合測試
└── e2e/
    ├── markets.spec.ts               # E2E 測試
    ├── trading.spec.ts
    └── auth.spec.ts
```
