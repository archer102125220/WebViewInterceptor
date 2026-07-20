# Android WebView 碎片化解析：Chromium 核心、第三方內核與無 GMS 設備的影響

[English Version](android_webview_fragmentation_en.md)

Android 平台一直以來以「碎片化 (Fragmentation)」聞名。然而在探討 WebView 的彈窗與「User Activation v2 (UAv2)」機制時，其影響並非單純取決於手機硬體廠牌，而是取決於**底層瀏覽器內核的來源與版本**。

本文件將解析在不同 Android 環境下，前端使用 `window.open`、動態建立 `<a target="_blank">` 標籤，或進行非同步跳轉時可能遭遇的落差與限制。

## 1. 具備 GMS 的一般廠牌：高度一致的 Chromium 體驗

自從 Android 5.0 (Lollipop) 之後，Google 將 Android System WebView 從作業系統底層抽離，改為透過 Google Play Store 獨立發布與更新。

- **一致的 UAv2 機制**：無論是 Samsung 的 OneUI、Xiaomi 的國際版 MIUI、或是 Pixel 等系統，只要設備搭載 Google Mobile Services (GMS) 且有定期連網更新，底層運作的皆為官方最新版 Chromium 引擎。
- **測試結果通用**：在這些設備上，Chromium UAv2 的「5 秒鐘憑證寬限期 (`kActivationLifespan`)」機制會高度一致地嚴格運作。只要非同步 API 延遲在 5 秒內（且期間未受阻撓），`window.open` 或動態觸發的 `<a target="_blank">` 皆能順利被原生層捕捉並放行。

> [!NOTE]
> 關於 Android Chromium 在底層 Event Loop 中對 Macrotask 與 Microtask (Promise) 的 5 秒寬限期處理，已統一整理於：[async_popup_blocker_history.md](./async_popup_blocker_history.md) 的第 4 節。

## 2. 真正的碎片化地雷一：超級 App 的第三方內核 (如騰訊 X5)

在 Android 生態系中，影響最深遠的變數通常來自「第三方超級 App」。許多超級 App（如 WeChat / 微信、QQ）為了掌控渲染效能與安全性，並**不使用**系統內建的 Android WebView，而是搭載自家的瀏覽器內核（例如騰訊自研的 X5 內核）。

- **自定義防禦規則**：X5 內核的資安政策與彈窗（`window.open` 及 `<a target="_blank">`）攔截邏輯與 Chromium 截然不同，通常更為嚴格且包含未公開的黑盒限制。
- **機制失效**：在這種環境下，Chromium 的 5 秒寬限期並不適用。不僅非同步彈窗會失效，甚至在某些情境下，連同步的點擊事件也會遭到特製規則無情封殺。

## 3. 真正的碎片化地雷二：無 Google 服務的手機 (如華為 HarmonyOS)

在無 GMS 的設備上（如受制裁後的華為手機，或專供中國大陸市場販售的各廠牌境內版手機），由於無法存取 Google Play Store，因此無法獲取 Google 官方的 System WebView 更新。

- **滯後的內核版本**：這類設備通常依賴廠商自行維護的 WebView 引擎（如華為的 HMS Core 內建引擎，通常 Fork 自較舊版本的 Chromium）。
- **舊版標準殘留**：這些舊版或魔改版的 Chromium 引擎，對 User Gesture 的判定可能仍停留在較舊且嚴格的版本。這會導致原本預期能依賴 UAv2 機制過關的非同步跳轉，在此類設備上直接遭到阻擋。

## 4. 真正的碎片化地雷三：手機廠牌 (OEM) 的魔改與系統限制

儘管多數現代設備使用標準的 Chromium WebView，但各大手機廠牌 (OEM) 在系統層面仍會對 WebView 的行為與套件選擇進行不同程度的介入。這些系統級的限制會干擾標準 Web API 的預期行為：

- **Samsung (客製化渲染與強制行為)**：三星在系統層面深度魔改了 WebView，即使在使用者「正常前景操作」時也會引發異常。最著名的災情是三星 WebView 會強制套用自家的「黑暗模式 (Dark Mode)」演算法，直接無視前端標準的 CSS `prefers-color-scheme`，導致網頁 UI 破版或顏色強制反轉（詳見知名討論 [Stack Overflow: Samsung Internet forces dark mode](https://stackoverflow.com/questions/66094087/samsung-internet-forces-dark-mode)）。這凸顯了 OEM 廠牌對標準 Web 行為的粗暴介入。
- **Xiaomi 等廠牌 (隱式 Intent 攔截與 URL Scheme 失效)**：在前景正常使用時，若網頁直接觸發 `market://` 或 `intent://` 等深層連結，Android WebView 預設不僅無法辨識，還會直接拋出 `ERR_UNKNOWN_URL_SCHEME` 錯誤（詳見經典除錯討論 [Stack Overflow: WebView ERR_UNKNOWN_URL_SCHEME](https://stackoverflow.com/questions/41693263/android-webview-err-unknown-url-scheme)）。更嚴重的是，在 Xiaomi (MIUI / HyperOS) 等高度客製化系統中，就算原生端試圖攔截處理，系統也經常會從底層直接綁架這些 Intent，並**強制導向自家的「GetApps 應用商店」或「內建瀏覽器」**。這種系統級別的惡意攔截，徹底打破了前端想單靠一套 Web Intent 通吃所有設備的幻想。

需要特別強調的是，雖然上述除錯討論的建立時間較早，但這正好反映了 **Android 底層 Intent 處理缺陷與 OEM 攔截策略是長年未解的「歷史共業」**。即便作業系統持續升級，各大 OEM 廠牌為了鞏固自家生態系，至今依然會在底層維持這類特規限制。這再次證明了，單純依賴前端原生的 `window.open` 或 `<a target="_blank">` 進行跨平台或跨 App 跳轉，在 Android 碎片化的環境下是極度脆弱且不可靠的。

## 5. 跨平台的共同死穴：App 拒絕實作 `WebChromeClient`

如同 iOS 端依賴 `WKUIDelegate` 一樣，Android 前端彈窗的生死也掌握在原生開發者手中。

如果網頁是透過 Facebook、LINE 等第三方 Android App 的內建瀏覽器開啟，只要該 App 的原生開發者沒有在 `WebChromeClient` 中實作 `onCreateWindow`（或者實作了但刻意不處理），那麼前端發出的 `window.open` 或點擊 `<a target="_blank">` 請求同樣會毫無反應。這與底層是否具備 Chromium 5 秒寬限期無關，純粹是應用層的刻意封閉。

## 6. 附錄：Android WebView 版本與支援生命週期 (紀錄於 2026-07-17)

在規劃跨平台 WebView 開發時，了解 Android WebView 的演進與支援界線是非常重要的：

- **獨立更新的起點**：Google 於 **Android 5.0 (Lollipop, 2014年)** 做出了重大架構改變，將 WebView 從作業系統核心中抽離，改為透過 Google Play Store 更新。這解決了以往「系統不更新，WebView 就永遠無法升級」的災難。
- **Play Store 更新的極限**：雖然能透過 Play Store 更新，但 Google 依然會定期淘汰過舊的 Android 系統。例如 Android 5、6、7 等舊系統，目前已經無法從 Play Store 獲取最新版本的 Chromium 核心。這意味著這些老舊設備的 WebView 引擎版本已被永久凍結，可能無法支援最新的 Web API 或存在未修補的安全性漏洞。
- **官方明定的版本支援**：截至 **2026 年 7 月**，多數現代化與主流 App 的最低支援版本通常設定在 **Android 8.0 (API 26)** 或 **Android 9.0 (API 28)**。
  - **選定 Android 8.0 (2017年8月發布) 的主因**：從此版本開始，WebView 預設啟用**多程序架構 (Multiprocess)**，網頁崩潰不再容易導致整個 App 閃退。
  - **選定 Android 9.0 (2018年8月發布) 的主因**：此版本開始**預設值改為封鎖 HTTP (強制 HTTPS)**，且正式引入**瀏海螢幕 (Display Cutout) API**，這兩者對 WebView 的安全性與前端版面避讓有著決定性的影響。
  - 將底線設於這兩個分水嶺，能確保絕大多數用戶的設備都能正常接收近幾年的 Chromium 引擎更新，保持相對一致的渲染與執行環境。

---

## 結論與對策

雖然搭載 GMS 的現代 Android 手機在 WebView 行為上大體一致，但只要專案的目標受眾包含**會使用超級 App (如微信) 的用戶**、**使用無 GMS 設備 (中國大陸市場) 的用戶**，甚至是**使用受到各大 OEM (Samsung, Xiaomi 等) 系統級限制的手機**，依賴原生彈窗 (`window.open` 或 `<a target="_blank">`) 的穩定性依然是一場災難。

這進一步強化了我們應採用 **JSBridge** 的結論：

透過 JSBridge 直接將跳轉需求與參數交接給原生 Native API，便能徹底繞過 Chromium、WebKit、騰訊 X5，甚至是各大手機廠牌的魔改與底層系統限制，達成 100% 穩定可控的跨平台網頁跳轉。
