# 跨平台 WebView 的非同步彈窗防禦機制與 JSBridge 架構

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
- **最關鍵的是：Chromium 允許這個憑證穿透非同步的 `Promise` (包含 `fetch`) 與 `setTimeout`！**
- 因此，只要 API 回應速度或 `setTimeout` 的延遲時間沒有超過憑證的有效期限（例如測試中的 3 秒），當執行到 `window.open` 時，憑證仍在有效期限內，Android 就會判定這「依然是使用者點擊觸發的」，進而放行彈窗。一旦超過 5 秒，依然會面臨失效命運。

### iOS (WebKit 引擎)：0 秒寬限期與薛丁格的微任務
iOS WebKit **完全沒有**任何秒數的寬限期。它的 Token 存活度取決於 JavaScript 的 Event Loop 排程：

1. **Macrotask (宏任務) 必擋**：不管是 iOS 15、iOS 16 還是最新的 iOS 18，只要使用者的點擊事件進入了需要等待瀏覽器 Event Loop 重新排程的宏任務 (例如 `setTimeout`)，Token 就會立刻失效 (0 秒寬限)。隨後觸發的 `window.open` 會被判定為背景惡意彈窗而封殺。

2. **Microtask (微任務) 的模糊地帶**：例如純粹的 `Promise.resolve().then()`，因為它會在當前 Event Loop 的週期 (Tick) 結束前立刻插隊執行，未交還控制權。
   - **WebKit 的歷史演進與版本差異**：WebKit 對於微任務是否能繼承 Token，在歷史上經歷過多次反覆：
     - **【極度嚴苛期】iOS 12.2 以前**：未完善 Promise 傳遞機制，Token 嚴格綁定在 `onclick` 的同步呼叫疊 (Synchronous Call Stack) 上。同步程式碼跑完，微任務一律封殺。
     - **【短暫放行期】iOS 12.2 ~ iOS 14 早期**：為了向 HTML5 標準靠攏，修正機制讓純微任務能合法繼承 Token，此段時間能成功彈出。
     - **【薛丁格狀態】iOS 15 以後**：即使底層允許微任務傳遞，由於 ITP (防追蹤) 與防彈窗濫用機制強化，如果原生端設為極度保守模式，或是在 In-App Browser 內被隱形攔截，微任務的 Token 仍可能隨時被強制沒收。
     
**總結**：由於跨平台雙引擎的生命週期判定機制完全不一致，採用 **JSBridge** 依舊是唯一能保證雙平台 100% 穩定運作的標準解法。

## 5. 參考資料 (References)
- 📖 [Chromium 官方部落格：User Activation v2 (UAv2) 機制介紹](https://developer.chrome.com/blog/user-activation)
- 📖 [MDN Web Docs: Transient Activation (短暫啟動憑證時效說明)](https://developer.mozilla.org/en-US/docs/Glossary/Transient_activation)
- 📖 [Chromium 原始碼：user_activation_state.h (揭露 5 秒鐘常數 kActivationLifespan)](https://github.com/chromium/chromium/blob/7115760f2e6dafa470a579182b2709ded743e683/third_party/blink/public/common/frame/user_activation_state.h#L23)
- 📖 [Android 官方文件：setJavaScriptCanOpenWindowsAutomatically](https://developer.android.com/reference/android/webkit/WebSettings#setJavaScriptCanOpenWindowsAutomatically(boolean))
- 📖 [Apple Developer 文件：WKPreferences.javaScriptCanOpenWindowsAutomatically](https://developer.apple.com/documentation/webkit/wkpreferences/javascriptcanopenwindowsautomatically)

---

### 附錄：實機測試結果

#### 1. iOS 測試結果 (測試設備：Iphone Xs, iOS 18.7.9)
- **結果**：`setTimeout` (3秒) 及 `fetch` 非同步彈窗 **均失敗**。
- **展示**：
  ![iOS 攔截測試結果](../test-result/ios-webview-interceptor-test.gif)

#### 2. Android 測試結果 (測試設備：Samsung Galaxy Fold5, Android 16 / OneUI 8.5)
- **結果**：`setTimeout` (3秒) 及 `fetch` 非同步彈窗 **均成功** (受惠於 UAv2 機制)。
- **展示**：
  ![Android 攔截測試結果](../test-result/android-webview-interceptor-test.gif)