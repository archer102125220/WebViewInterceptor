# iOS WebView 嚴格度解析：從 WebKit 政策到第三方 App (In-App Browser) 限制

在進行跨平台 WebView 彈窗（`window.open` 或動態建立 `<a>` 標籤）測試時，許多前端開發者會發現 iOS 的行為不僅異常嚴格，而且在真實世界中（如放入 LINE、Facebook 等社群軟體開啟）甚至會遇到比原廠預設更惡劣的狀況。

本文件總結了 iOS WebView (主要是 WKWebView) 在不同版本、不同場景下的防禦機制與限制。

## 1. 跨 iOS 版本的防禦一致性 (Token 遺失鐵律)

Apple 的 WebKit 引擎對於「**非同步回呼會沒收 User Gesture Token**」這項資安鐵律，已經存在非常多年。

- **不存在寬限期**：不同於 Android Chromium 引擎擁有的「User Activation v2 (UAv2)」5 秒鐘寬限期，iOS WebKit **沒有**任何秒數的寬限期。
- **只要非同步必定失敗**：不管是 iOS 15、iOS 16 還是最新的 iOS 18，只要使用者的點擊事件進入了 `fetch`、`Promise` 或是 `setTimeout`，這張代表實體點擊的憑證就會立刻失效。隨後觸發的 `window.open` 就會被 WebKit 引擎底層判定為背景惡意彈窗而封殺。

因此，在不同的 iOS 現代版本中，針對非同步彈窗的嚴格阻擋行為是**高度一致**的。

## 2. 真實世界更嚴格的挑戰：第三方 App 內建瀏覽器 (In-App Browser)

在自行開發的 App 中，只要實作了 `WKUIDelegate` 協議，至少「同步」點擊的 `window.open` 是可以成功運作並被攔截的。但在真實的上線環境中，網頁經常是透過第三方 App (例如：LINE, Facebook, Instagram) 內的 WebView 開啟，這時前端往往會面臨**連最基本的同步 `window.open` 都失效**的窘境。

### 為什麼會被完全封殺？
1. **iOS 的預設行為是不作為**：在 iOS 的 WKWebView 中，`window.open` 與 `target="_blank"` 預設是**不具備任何行為**的。
2. **委派機制的掌握權**：要讓 `window.open` 生效，原生開發者**必須**手動實作 `WKUIDelegate` 中的 `createWebViewWithConfiguration` 函數，來主動「接住」前端的開新視窗請求。
3. **社群軟體的私心**：許多社群 App 為了把使用者的眼球「關在自己的 App 生態圈裡」，會刻意不實作這個函數，或者直接在函數內返回 `nil` (拒絕開啟)。
4. **結果**：這會導致前端的 `window.open` 請求就像丟進黑洞一樣，無聲無息地消失。

## 3. Apple 隱私權政策與 ITP (Intelligent Tracking Prevention) 影響

Apple 近年來在 Safari 與 WebKit 大幅增強了 ITP 防追蹤機制。

如果 `window.open` 跳轉目標是一個帶有跨站追蹤參數的第三方廣告網域（例如進行某種導購轉址或 Oauth 認證），在較新的 iOS 系統 (iOS 14+) 上，即使這是一個完美的同步點擊，WebKit 也可能因為判定該網址具有「跨站追蹤 (Cross-Site Tracking)」的嫌疑，而強制啟動隱私保護干預，進一步對彈窗或 Cookie 傳遞進行限縮或阻擋。

---

## 結論與對策

在本地測試 App 中測出的 iOS 嚴格防禦，其實只是 Apple 官方賦予的「**基本底線**」。

在真實的上線環境中，前端開發者面對的往往是**更不可控、更封閉**的 WebView 環境（第三方 App 根本不實作彈窗委派）。這進一步佐證了跨平台前端架構的最終結論：

**只要牽涉到瀏覽器的原生彈窗 (`window.open` / `target="_blank`)，防禦的主動權永遠掌握在 Apple 與原生 App 開發者手上。**

前端唯一能 100% 掌握且保證穩定運作的解決方案，就是**放棄依賴原生瀏覽器的彈窗行為**，改為：
1. **同頁路由跳轉 (SPA)**
2. **同頁跳轉 (`location.href`)** 避開 popup blocker
3. **透過 JSBridge** 呼叫原生 App 的 Function，讓原生 App 自行決定要開啟系統預設瀏覽器還是推入新的 WebView 視窗。
