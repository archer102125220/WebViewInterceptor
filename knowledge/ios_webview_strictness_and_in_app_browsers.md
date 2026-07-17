# iOS WebView 嚴格度解析：從 WebKit 政策到第三方 App (In-App Browser) 限制

在進行跨平台 WebView 彈窗（`window.open` 或動態建立 `<a>` 標籤）測試時，許多前端開發者會發現 iOS 的行為不僅異常嚴格，而且在真實世界中（如放入 LINE、Facebook 等社群軟體開啟）甚至會遇到比原廠預設更惡劣的狀況。

本文件總結了 iOS WebView (主要是 WKWebView) 在不同版本、不同場景下的防禦機制與限制。

## 1. 跨 iOS 版本的防禦一致性 (Token 遺失鐵律)

Apple 的 WebKit 引擎對於「**非同步回呼會沒收 User Gesture Token**」這項資安鐵律，已經存在非常多年。

- **不存在寬限期**：不同於 Android Chromium 引擎擁有的「User Activation v2 (UAv2)」5 秒鐘寬限期，iOS WebKit **沒有**任何秒數的寬限期。
- **只要非同步必定失敗 (Macrotask 必擋)**：不管是 iOS 15、iOS 16 還是最新的 iOS 18，只要使用者的點擊事件進入了需要等待瀏覽器 Event Loop 重新排程的宏任務 (Macrotask，例如 `setTimeout`)，這張代表實體點擊的憑證就會立刻失效 (0 秒寬限)。隨後觸發的 `window.open` 就會被 WebKit 引擎底層判定為背景惡意彈窗而封殺。

### 特別解析：Microtask (Promise) 的模糊地帶
前端開發中的微任務 (Microtask，例如純粹的 `Promise.resolve().then()`) 是一個特例。因為微任務會在當前 Event Loop 的週期 (Tick) 結束前就立刻插隊執行，並未將控制權交還給瀏覽器。
- **純微任務的存活機率 (WebKit 的歷史演進與版本差異)**：WebKit 對於「微任務是否能繼承點擊 Token」的判定，在歷史上經歷過多次反覆：
  - **【極度嚴苛期】iOS 12.2 以前**：早期的 WebKit 未完善 Promise 的手勢傳遞機制，將 Token 嚴格綁定在 `onclick` 的**同步呼叫疊 (Synchronous Call Stack)** 上。只要同步程式碼跑完，微任務一律被視為無使用者互動而遭封殺。
  - **【短暫放行期】iOS 12.2 ~ iOS 14 早期**：Apple 為了向 HTML5 標準靠攏，修正了這個機制，讓純微任務 (`Promise.resolve()`) 能夠合法繼承點擊 Token，這段時間內的微任務彈窗**能成功彈出**。
  - **【薛丁格狀態】iOS 15 以後**：隨著 ITP (智慧防追蹤) 與防彈窗濫用機制的極端強化，即使 WebKit 底層允許微任務傳遞 Token，但在以下 **3 種真實情境**中，微任務的 Token 仍會被無情沒收：
    1. **ITP 判定為「跨站追蹤」**：如果 `window.open` 準備跳轉的網址，被系統內建的 ITP 機制判定為高風險的廣告追蹤網域或是不斷轉址的 Affiliate Link，WebKit 會直接以保護隱私為由封殺該次微任務彈窗。
    2. **原生端配置極度保守 (iOS 15+ 的新特性)**：若原生開發者將 `WKPreferences` 中的 `javaScriptCanOpenWindowsAutomatically` 設為 `false` (這也是預設值)，在舊版系統中這只會擋掉 `onload` 自動彈窗；但在 iOS 15 以後，這個設定會連帶讓 WebKit 進入「極度敏感模式」，拒絕承認微任務內的 Token，只認純同步程式碼。
    3. **社群軟體的隱形攔截**：在 LINE 或 Facebook 的 In-App Browser 裡，官方往往會偷偷注入一段自己的 JavaScript (WKUserScript) 來側錄使用者的點擊行為，這個側錄過程可能涉及非同步處理，導致「您的點擊」傳遞到「您的程式碼」時，早就已經被降級成 Macrotask 了，此時您自己寫的 `Promise` 根本回天乏術。

- **嚴格模式與網路延遲**：然而，只要 `Promise` 內部包含了真正的網路請求 (如 `fetch().then()`)，等待網路回應本身就會跨越宏任務，Token 依然會 100% 遺失。

因此，在不同的 iOS 現代版本中，針對非同步彈窗的嚴格阻擋行為是**高度一致且不可依賴的**。

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

## 4. 附錄：iOS WebView 版本與支援生命週期 (紀錄於 2026-07-17)

在規劃跨平台 WebView 開發時，了解 iOS 版本的演進與支援界線是非常重要的：

- **WKWebView 的引入 (最舊支援起點)**：Apple 於 **iOS 8 (2014年9月發布)** 首度引入 `WKWebView`，用以取代效能低落且存在記憶體外洩問題的 `UIWebView`。
- **UIWebView 的全面封殺 (停止支援)**：Apple 於 **2020年4月 (iOS 13 時期)** 宣布全面停止支援 `UIWebView`，並從那時起，所有包含 `UIWebView` 程式碼的新 App 或更新版本都會被 App Store 拒絕上架。這意味著目前市場上活躍的 iOS App 已 100% 轉移至 `WKWebView`。
- **官方明定的版本支援**：截至 **2026 年 7 月**，多數現代化與主流 App 的最低支援版本通常設定在 **iOS 15 (2021年9月發布)** 或 **iOS 16 (2022年9月發布)**。iOS 15 是一批經典舊設備（如 iPhone 6s、iPhone 7）所能升級的最後極限。對於低於此版本的舊系統，Apple 已實質上停止了常規的安全與框架更新支援。

---

## 結論與對策

在本地測試 App 中測出的 iOS 嚴格防禦，其實只是 Apple 官方賦予的「**基本底線**」。

在真實的上線環境中，前端開發者面對的往往是**更不可控、更封閉**的 WebView 環境（第三方 App 根本不實作彈窗委派）。這進一步佐證了跨平台前端架構的最終結論：

**只要牽涉到瀏覽器的原生彈窗 (`window.open` / `target="_blank`)，防禦的主動權永遠掌握在 Apple 與原生 App 開發者手上。**

前端唯一能 100% 掌握且保證穩定運作的解決方案，就是**放棄依賴原生瀏覽器的彈窗行為**，改為：
1. **同頁路由跳轉 (SPA)**
2. **同頁跳轉 (`location.href`)** 避開 popup blocker
3. **透過 JSBridge** 呼叫原生 App 的 Function，讓原生 App 自行決定要開啟系統預設瀏覽器還是推入新的 WebView 視窗。
