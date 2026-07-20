# 跨平台 WebView 的非同步彈窗防禦機制與 JSBridge 架構

[English Version](async_popup_blocker_history_en.md)
本文件記錄了為何在現代前端框架 (Vue / React) 中，使用非同步打 API 後呼叫 `window.open` 或動態建立 `<a>` 標籤，容易在行動裝置 App 內嵌 WebView 中遭遇攔截失效或被阻擋的根本原因。

## 1. 問題現象：前端非同步彈窗失敗

現代的前端開發習慣為「資料驅動畫面」。例如以下 Vue/React 的常見邏輯：
1. 使用者點擊按鈕
2. 觸發 Function 發送 HTTP 請求 (Ajax / Fetch)
3. 等待非同步回應 (Promise `await` 或 `.then`)
4. 取得新網址後，執行 `window.open(newUrl, '_blank')`

在一般桌面瀏覽器上，只要非同步等待時間不長，通常可以成功彈出新分頁。**但在行動裝置的 WebView（iOS WKWebView 或 Android WebView）上，這個 `window.open` 往往會失效（無反應或回傳 `null`）。**

## 2. 失敗的根本原因：使用者手勢遺失 (User Gesture Context Loss) 與防禦模式

現代 App（特別是金融、電商、超級 App）出於資安與防禦機制，通常會將 WebView 的「允許腳本自動開新視窗」權限關閉：
- **iOS**: `preferences.javaScriptCanOpenWindowsAutomatically = false`
- **Android**: `settings.setJavaScriptCanOpenWindowsAutomatically(false)`

這個嚴格設定的目的是：
1. **防範蓋版廣告與彈窗轟炸 (Popup Abuse)**：防止惡意代碼在背景無限開啟新視窗耗盡資源。
2. **防範釣魚詐騙 (Phishing & UI Spoofing)**：防止惡意腳本偷偷倒數後，突然彈出偽造的系統登入頁面騙取帳號密碼。強制將跳轉綁定在「實體點擊」的當下，讓使用者清楚知道是自己的點擊觸發了新視窗。
3. **防止惡意背景跳轉商店 (Drive-by Redirects)**：封殺未經使用者同意直接喚起 App Store 或外部 App 的跳轉行為。
4. **手機硬體資源嚴格管控**：每一個新視窗都會消耗大量的手機記憶體 (RAM)，背景偷偷開啟會導致 App 崩潰。

**為什麼非同步會死？**
當前端透過 `fetch` 或 `setTimeout` 等待時，Event Loop 會中斷（可以想像成被切為不同於使用者操作事件的執行緒做後續動作）。當非同步任務結束並執行到 `window.open` 時，系統底層核發的「實體點擊通行證 (User Gesture Token)」已經過期或遺失。
此時 WebView 會判定這是一個 **「沒有實體點擊（使用者操作）背書的惡意背景彈窗」**，進而將其無情封殺。

## 3. 解決方案：放棄 URL 攔截，擁抱 JSBridge

面對上述嚴格的防禦機制，純前端的繞過手法（如建立隱藏 `<a>` 並觸發 `.click()`）極度不穩定且易被阻擋。

**業界的終極標準解法是使用 JSBridge (JavaScript 橋接)：**
不要透過瀏覽器的 `window.open` 引擎，而是讓前端「直接命令」原生 App 去開畫面。

### 前端實作方式：
```javascript
async function handleOpenUrl() {
    // 1. 等待非同步 API
    const newUrl = await fetchUrlFromBackend();
    
    // 2. 透過 JSBridge 呼叫 Native (不經過瀏覽器的彈窗引擎)
    if (window.AndroidApp) {
        window.AndroidApp.openNewWindow(newUrl); // Android
    } else if (window.webkit && window.webkit.messageHandlers) {
        window.webkit.messageHandlers.openNewWindow.postMessage(newUrl); // iOS
    } else {
        window.open(newUrl, '_blank'); // 降級：一般瀏覽器
    }
}
```

### 原生端 (Android) 實作範例：
```kotlin
class WebAppInterface(private val context: Context) {
    @JavascriptInterface
    fun openNewWindow(url: String) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
        context.startActivity(intent)
    }
}
// 將介面注入給前端
webView.addJavascriptInterface(WebAppInterface(this), "AndroidApp")
```

### JSBridge 架構優勢：
- **100% 成功率**：這等同於「前端呼叫原生 App 的 Function」，完全繞過 WebView 的惡意彈窗阻擋機制。
- **無視非同步延遲**：不管 API 請求花多久時間，只要一呼叫 JSBridge，原生端必定會執行，沒有手勢憑證過期的問題。
- **權責分明**：前端專心處理商業邏輯（取得網址），開啟視窗這種需要掌控螢幕畫面的事交還給原生 App。


## 4. 雙平台底層引擎對非同步 Token 的處置差異 (Event Loop)

即使將原生的彈窗權限關閉，雙平台底層瀏覽器引擎對於「使用者點擊通行證 (User Gesture Token)」的生命週期，有著截然不同的底層實作：

### Android (Chromium 引擎)：UAv2 5 秒寬限期
自 Chrome 72 開始引入了 **「User Activation v2 (UAv2)」** 機制。
- 當使用者發生實體點擊時，系統會發放一個 **短暫的啟動憑證 (Transient Activation)**。
- 在 Android WebView 的環境與特定版本下，這個憑證的存活時間可長達 **5 秒鐘**。
- **憑證刷新機制 (Token Refresh)**：這 5 秒並非從第一下點擊死死綁定。只要在這 5 秒內，使用者**持續與畫面產生任何有效互動（例如滑動、再次點擊）**，這個 5 秒的倒數計時器就會被**重置刷新**。
- **最關鍵的是：Chromium 允許這個憑證穿透非同步的 `Promise` (包含 `fetch`) 與 `setTimeout`！**
- 因此，只要 API 回應速度或 `setTimeout` 的延遲時間沒有超過「最後一次互動後的 5 秒內」，當執行到 `window.open` 時，憑證仍在有效期限內，Android 就會判定這「依然是使用者點擊觸發的」，進而放行彈窗。一旦超過最後一次互動 5 秒，依然會面臨失效命運。

### iOS (WebKit 引擎)：1 秒寬限期與非同步機制的演進
iOS WebKit 的防禦機制與 Android (Chromium) 存在顯著差異，其歷史演進中也經歷了多次底層邏輯的修改：

1. **Macrotask (宏任務) 與 1 秒寬限期**：
   - 早期許多開發者誤以為 iOS 只要進入 `setTimeout` 就會失效 (0 秒寬限期)，但實際上 WebKit 原始碼中曾有針對 `setTimeout` 的**「第一層 1 秒寬限期」**特殊處理 (可見於 WICG/interventions #12 的工程師討論)。
   - 如果使用者的點擊觸發了 `setTimeout`，且延遲在 1000 毫秒以內，第一層的 callback 是能繼承 Token 並彈窗的。但如果延遲超過 1 秒，或是發生「第二層 `setTimeout`」，Token 就會被中斷。

2. **Microtask (微任務) 與 Promise 的演進史**：
   - **【早期寬鬆期】2018 年以前 (iOS 12 早期及之前)**：當時的 WebKit 針對純微任務 (如 `Promise.resolve().then()`) 其實是**允許繼承手勢**的 (在 Mozilla Bugzilla #1469730 中，開發者證實了在 2018 年時 Safari 就能順利從微任務中觸發彈窗)。在當前 Event Loop 週期結束前插隊執行的純微任務，大多能順利觸發彈窗。
   - **【Fetch / 非同步網路請求的嚴格封殺】**：雖然純微任務可以過關，且 WebKit 在 2020 年 (WebKit Bugzilla #215014) 曾經針對 **WebAuthn** 等特定 API 實作了透過 Promise 轉送手勢的機制，但這**並不適用於彈窗 (`window.open`)**！根據 WebKit Bugzilla #225559 的開發者實測證明，在 iOS WebKit 中，只要呼叫了 `fetch` 或任何牽涉到網路、甚至讀取 Blob 的非同步 Promise 操作，即使耗時遠低於 1 秒，Token 也會被**立刻沒收**。這代表相對於 `setTimeout` 的 1 秒寬限期，`fetch` 等 Promise 操作在 iOS 上對於彈窗來說反而更加嚴格，等同於「0 秒寬限」。
   - **【薛丁格狀態】近年 (iOS 15 以後) 與 In-App Browser**：除了上述的底層非同步限制外，Apple 近年也大幅強化了隱私權與防彈窗濫用機制 (例如 ITP 相關防護)。在實際場景中 (特別是社群軟體的內建 WebView / In-App Browser，或開啟了進階防護)，Token 的審查變得更加不透明與嚴苛，導致前端開發者覺得彈窗機制「時好時壞」。
     
**總結與避坑指南**：
在純 Web 開發中，前端工程師常使用一個知名的繞過技巧：「先同步開啟空白視窗 `window.open('', '_blank')`，等非同步請求完成後再修改 `location.href`」(可見於下方 StackOverflow 參考資料)。
然而，**這個技巧在 Native App (In-App Browser / WebView) 開發中往往會引發災難**。當前端開啟空白視窗時，原生端的 `WKUIDelegate` 或 `WebChromeClient` 會第一時間攔截到一個網址為空 (`""`) 或 `about:blank` 的請求，導致原生端無法依據 URL 進行正確的攔截解析或 Deep Link 路由；若原生端勉強放行，使用者也會先看到令人困惑的白屏畫面，體驗極差。

因此，由於跨平台雙引擎的生命週期判定機制完全不一致，加上 Web 端的 workaround 在原生環境水土不服，採用 **JSBridge** 讓原生端徹底接管行為，依舊是唯一能保證雙平台 100% 穩定運作的標準解法。

## 5. 參考資料 (References)
- 📖 [Chromium 官方部落格：User Activation v2 (UAv2) 機制介紹](https://developer.chrome.com/blog/user-activation)
- 📖 [MDN Web Docs: Transient Activation (短暫啟動憑證時效說明)](https://developer.mozilla.org/en-US/docs/Glossary/Transient_activation)
- 📖 [Chromium 原始碼：user_activation_state.h (揭露 5 秒鐘常數 kActivationLifespan)](https://github.com/chromium/chromium/blob/7115760f2e6dafa470a579182b2709ded743e683/third_party/blink/public/common/frame/user_activation_state.h#L23)
- 📖 [Chromium 原始碼：user_activation_state.cc (憑證刷新實作)](https://source.chromium.org/chromium/chromium/src/+/main:third_party/blink/common/frame/user_activation_state.cc)
- 📖 [Android 官方文件：setJavaScriptCanOpenWindowsAutomatically](https://developer.android.com/reference/android/webkit/WebSettings#setJavaScriptCanOpenWindowsAutomatically(boolean))
- 📖 [Apple Developer 文件：WKPreferences.javaScriptCanOpenWindowsAutomatically](https://developer.apple.com/documentation/webkit/wkpreferences/javascriptcanopenwindowsautomatically)
- 📖 [Mozilla Bugzilla #1469730：window.open popup is blocked from microtask (證實 2018 年主流瀏覽器對純微任務的放行)](https://bugzilla.mozilla.org/show_bug.cgi?id=1469730)
- 📖 [GitHub WICG/interventions #12：user gesture required for sensitive operations (揭露 WebKit 對 setTimeout 的 1 秒寬限期)](https://github.com/WICG/interventions/issues/12)
- 📖 [WebKit Bugzilla #225559：Implement standards-compliant user gesture tracking (WebKit 邁向標準化手勢追蹤的起點)](https://bugs.webkit.org/show_bug.cgi?id=225559)
- 📖 [WebKit Bugzilla #215014：Move user gesture propagation over promise behind a feature flag (2020 年正式將 Promise 轉送機制預設開啟，但主要針對 WebAuthn) ](https://bugs.webkit.org/show_bug.cgi?id=215014)
- 📖 [WebKit Bug 313797 / Commit ebeb545：Propagate user gestures through sendMessage (展示 WebKit 至今仍在解決跨 IPC 與擴充功能非同步邊界的手勢遺失問題)](https://github.com/WebKit/WebKit/commit/ebeb54525a799f353a717f2492acf7066433efbc)
- 📖 [StackOverflow：Safari `window.open` async workaround (業界針對 Safari 非同步彈窗的標準實務解法，但注意其在 Native WebView 環境下會有嚴重副作用)](https://stackoverflow.com/questions/20696041/window-openurl-blank-not-working-on-imac-safari)

---

> [!TIP]
> **想看真實的實機測試結果與錄影？**
> 本專案的 iOS 與 Android 攔截測試錄影，已統一整理於專案首頁的 [README.md](../README.md) 中。