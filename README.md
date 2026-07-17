# WebView Interceptor Demo

這是一個雙平台 (Android / iOS) 的 WebView 跳轉攔截測試與展示專案。
此專案旨在深度測試並驗證 WebView 在面對不同情境（如人為點擊、腳本跳轉、非同步任務、SPA 路由）時，原生端攔截器的極限與死角。

## 專案結構
* **`Android/`**：Android 版本，使用 Kotlin 與現代化 `WebViewClient` (處理當頁跳轉) 和 `WebChromeClient` (處理新視窗)。
* **`IOS/`**：iOS 版本，使用 Swift 與 `WKWebView`、`WKNavigationDelegate` (處理當頁跳轉)、`WKUIDelegate` (處理新視窗)。

## 測試情境涵蓋

1. **基本跳轉攔截**：`<a href="...">`、`location.href`、`window.open`。
2. **非同步腳本觸發 (Event Loop 測試)**：透過 `Promise.resolve().then` (微任務) 與 `setTimeout` (宏任務) 觸發的跳轉。
3. **攔截死角 / 失效測試**：
    * **SPA 路由切換 (`history.pushState`)**：雙平台皆攔截失效（無重新載入行為）。
    * **表單 POST 跳轉 (`<form method="POST">`)**：Android 攔截穿透失效（直接跳轉），iOS 成功攔截。
    * **非同步與延遲彈窗 (`setTimeout` + `window.open`)**：iOS WebKit 因 0 秒寬限期會立刻封殺；Android Chromium 則受惠於 UAv2 機制，在 5 秒的寬限期內通常會放行。

---

## 如何運行與測試

### 🍏 iOS 版測試方法

**【在模擬器上測試】 (推薦，最簡單)**
1. 使用 Xcode 打開 `IOS/WebViewInterceptorDemo.xcodeproj`。
2. 在 Xcode 頂部中央的裝置選單中，選擇任意一個 **iOS Simulator** (例如 iPhone 15 Pro)。
3. 點擊左上角的 **▶️ (Run)** 即可開始測試。
> *模擬器不需要開發者憑證 (Code Signing)，隨開隨測！*

**【在實體 iPhone 上測試】**
1. 將 iPhone 接上電腦。
2. 在 Xcode 左側導覽列點擊藍色的專案圖示 `WebViewInterceptorDemo`。
3. 切換到中間畫面的 **Signing & Capabilities** 標籤頁。
4. 勾選 **Automatically manage signing**。
5. 在 **Team** 選單中選擇 **Add an Account...** 並登入您一般的 Apple ID。
6. 選擇您剛加入的 Personal Team。如果 `Bundle Identifier` 報錯，請在後方加上幾個隨機數字使其不重複。
7. 點擊 **▶️ (Run)** 將 App 安裝進手機。
8. **信任開發者**：第一次開啟 App 前，請到手機的 `設定 -> 一般 -> VPN 與裝置管理`，點擊您的 Apple ID 並選擇「信任」，即可順利開啟 App！

---

### 🤖 Android 版測試方法

**【在模擬器 / 實體機上測試】**
1. **使用 Android Studio**：
   * 開啟 Android Studio，選擇 `Open` 並匯入 `Android/` 資料夾。
   * 等待 Gradle 同步完成後，將手機接上電腦並開啟「USB 偵錯模式」（或啟動 Android 模擬器）。
   * 點擊頂部的 **▶️ (Run)** 即可安裝並執行。

2. **使用終端機 (CLI) 快速安裝**：
   * 確認您已經連接好實體手機或開啟了模擬器 (`adb devices` 可看到裝置)。
   * 在終端機進入 Android 資料夾並執行編譯安裝：
     ```bash
     cd Android
     ./gradlew installDebug
     ```
   * 執行完畢後，在手機或模擬器上尋找並點開 `WebViewInterceptorDemo` App 即可。

---

### 測試結果錄影

#### 1. iOS 測試結果 (測試設備：Iphone Xs, iOS 18.7.9)
![iOS 攔截測試結果](./test-result/ios-webview-interceptor-test.gif)

#### 2. Android 測試結果 (測試設備：Samsung Galaxy Fold5, Android 16 / OneUI 8.5)
![Android 攔截測試結果](./test-result/android-webview-interceptor-test.gif)

---

## 開發者備註：歷史冷知識與架構文件
專案內的原始碼附帶了非常詳盡的「歷史註解」，記錄了 Android 早期 `shouldOverrideUrlLoading` 無法攔截腳本跳轉的痛苦黑歷史，以及 iOS 早期 `UIWebView` 對 `window.open` 裝死無反應的坑，非常適合想深入理解 WebView 底層演進的開發者閱讀。

除此之前，本專案也整理了進階的架構知識：
* 📖 [跨平台 WebView 的非同步彈窗防禦機制與 JSBridge 架構](knowledge/async_popup_blocker_history.md)：詳細解釋為何 Vue/React 的非同步 `window.open` 會被原生 App 阻擋，**深入探討 Event Loop (Microtask / Macrotask) 底層機制與雙平台引擎差異**，以及標準的 JSBridge 解決方案。
* 📖 [iOS WebView 嚴格度解析：從 WebKit 政策到第三方 App 限制](knowledge/ios_webview_strictness_and_in_app_browsers.md)：聚焦 iOS 真實上線環境會踩的坑，解析 **ITP 隱私防追蹤封殺、原生保守配置**，以及在 LINE、Facebook 等真實環境 In-App Browser 中的極端封殺狀況與版本生命週期。
* 📖 [Android WebView 碎片化解析：Chromium 核心與第三方內核的影響](knowledge/android_webview_fragmentation.md)：探討為何在多數搭載 GMS 的 Android 手機表現一致，但在微信 (X5 內核) 或無 Google 服務設備上卻依然會失效。
