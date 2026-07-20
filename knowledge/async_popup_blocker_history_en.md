# Cross-Platform WebView Asynchronous Popup Defense Mechanisms and JSBridge Architecture

[中文版](async_popup_blocker_history.md)

This document records the fundamental reasons why using `window.open` or dynamically creating `<a>` tags after asynchronous API calls in modern front-end frameworks (Vue / React) easily suffers from interception failures or blockages in mobile App embedded WebViews.

## 1. Problem Phenomenon: Front-End Asynchronous Popups Fail

Modern front-end development habits are "data-driven interfaces". For example, the following common logic in Vue/React:
1. User clicks a button
2. Triggers a Function to send an HTTP request (Ajax / Fetch)
3. Waits for asynchronous response (Promise `await` or `.then`)
4. After getting the new URL, executes `window.open(newUrl, '_blank')`

On general desktop browsers, as long as the asynchronous waiting time is not long, a new tab can usually be successfully popped up. **But on mobile device WebViews (iOS WKWebView or Android WebView), this `window.open` often fails (no response or returns `null`).**

## 2. Root Cause of Failure: User Gesture Context Loss and Defense Modes

Modern Apps (especially finance, e-commerce, and super Apps), for security and defense mechanisms, usually turn off WebView's "allow scripts to open windows automatically" permission:
- **iOS**: `preferences.javaScriptCanOpenWindowsAutomatically = false`
- **Android**: `settings.setJavaScriptCanOpenWindowsAutomatically(false)`

The purpose of this strict setting is to:
1. **Prevent Overlay Ads and Popup Abuse**: Prevent malicious code from infinitely opening new windows in the background and exhausting resources.
2. **Prevent Phishing & UI Spoofing**: Prevent malicious scripts from secretly counting down and suddenly popping up fake system login pages to steal account passwords. Forcing the redirection to be bound to the moment of "physical click" allows the user to clearly know that their click triggered the new window.
3. **Prevent Malicious Background Store Redirects (Drive-by Redirects)**: Block redirection behaviors that directly call up the App Store or external Apps without the user's consent.
4. **Strict Control of Phone Hardware Resources**: Every new window consumes a large amount of phone memory (RAM), and opening them secretly in the background will cause the App to crash.

**Why does async die?**
When the front-end waits via `fetch` or `setTimeout`, the Event Loop is interrupted (it can be imagined as being cut into a thread different from the user operation event for subsequent actions). When the asynchronous task finishes and executes to `window.open`, the "physical click pass (User Gesture Token)" issued by the underlying system has expired or been lost.
At this time, WebView will determine this is a **"malicious background popup without physical click (user operation) endorsement"**, and ruthlessly block it.

## 3. Solution: Abandon URL Interception, Embrace JSBridge

Facing the strict defense mechanisms mentioned above, purely front-end bypass techniques (like creating hidden `<a>` and triggering `.click()`) are extremely unstable and easily blocked.

**The industry's ultimate standard solution is to use JSBridge (JavaScript Bridge):**
Do not go through the browser's `window.open` engine, but let the front-end "directly command" the native App to open the screen.

### Front-End Implementation Method:
```javascript
async function handleOpenUrl() {
    // 1. Wait for asynchronous API
    const newUrl = await fetchUrlFromBackend();
    
    // 2. Call Native via JSBridge (Does not go through the browser's popup engine)
    if (window.AndroidApp) {
        window.AndroidApp.openNewWindow(newUrl); // Android
    } else if (window.webkit && window.webkit.messageHandlers) {
        window.webkit.messageHandlers.openNewWindow.postMessage(newUrl); // iOS
    } else {
        window.open(newUrl, '_blank'); // Downgrade: General browser
    }
}
```

### Native End (Android) Implementation Example:
```kotlin
class WebAppInterface(private val context: Context) {
    @JavascriptInterface
    fun openNewWindow(url: String) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
        context.startActivity(intent)
    }
}
// Inject the interface to the front-end
webView.addJavascriptInterface(WebAppInterface(this), "AndroidApp")
```

### JSBridge Architecture Advantages:
- **100% Success Rate**: This is equivalent to "front-end calling a Function of the native App", completely bypassing WebView's malicious popup blocking mechanism.
- **Ignores Asynchronous Delay**: No matter how long the API request takes, as long as JSBridge is called, the native end will definitely execute it, without the problem of gesture credential expiration.
- **Clear Responsibilities**: The front-end focuses on handling business logic (getting the URL), and matters requiring control over the screen like opening a window are handed back to the native App.


## 4. Differences in Underlying Engine Handling of Async Tokens Across Platforms (Event Loop)

Even if the native popup permission is turned off, the underlying browser engines of the dual platforms have completely different underlying implementations for the life cycle of the "User Gesture Token":

### Android (Chromium Engine): UAv2 5-Second Grace Period
Starting from Chrome 72, the **"User Activation v2 (UAv2)"** mechanism was introduced.
- When a user performs a physical click, the system issues a **Transient Activation**.
- In the Android WebView environment and specific versions, the survival time of this credential can be up to **5 seconds**.
- **Token Refresh Mechanism**: These 5 seconds are not rigidly bound from the first click. As long as within these 5 seconds, the user **continues to have any valid interaction with the screen (e.g., swiping, clicking again)**, this 5-second countdown timer will be **reset and refreshed**.
- **Most crucially: Chromium allows this credential to penetrate asynchronous `Promise` (including `fetch`) and `setTimeout`!**
- Therefore, as long as the API response speed or the delay time of `setTimeout` does not exceed "within 5 seconds after the last interaction", when executing to `window.open`, the credential is still within the validity period, Android will judge that "this is still triggered by user click", and thus allow the popup. Once it exceeds 5 seconds after the last interaction, it will still face a failure fate.

### iOS (WebKit Engine): 1-Second Grace Period and Evolution of Async Mechanisms
iOS WebKit's defense mechanism has significant differences from Android (Chromium), and its historical evolution has also undergone multiple modifications to underlying logic:

1. **Macrotask and 1-Second Grace Period**:
   - In the early days, many developers mistakenly believed that iOS would fail as long as it entered `setTimeout` (0-second grace period), but in fact, there used to be a special handling of the **"First Layer 1-Second Grace Period"** for `setTimeout` in the WebKit source code (can be seen in WICG/interventions #12 engineer discussions).
   - If the user's click triggers `setTimeout` and the delay is less than 1000 milliseconds, the first layer callback can inherit the Token and popup. But if the delay exceeds 1 second, or a "second layer `setTimeout`" occur, the Token will be interrupted.

2. **Microtask and Promise Evolution History**:
   - **[Early Lenient Period] Before 2018 (Early iOS 12 and before)**: WebKit at that time actually **allowed inheriting gestures** for pure microtasks (like `Promise.resolve().then()`) (In Mozilla Bugzilla #1469730, developers confirmed that Safari could smoothly trigger popups from microtasks in 2018). Pure microtasks inserted and executed before the end of the current Event Loop cycle mostly triggered popups smoothly.
   - **[Strict Blocking of Fetch / Async Network Requests]**: Although pure microtasks could pass, and WebKit in 2020 (WebKit Bugzilla #215014) once implemented a mechanism to forward gestures via Promise for specific APIs like **WebAuthn**, this **does not apply to popups (`window.open`)**! According to developer actual tests in WebKit Bugzilla #225559, in iOS WebKit, as long as `fetch` or any asynchronous Promise operation involving the network or even reading a Blob is called, even if the time spent is far less than 1 second, the Token will be **immediately confiscated**. This means compared to the 1-second grace period of `setTimeout`, Promise operations like `fetch` are even stricter for popups on iOS, equivalent to "0-second grace".
   - **[Schrödinger's State] Recent Years (iOS 15 and Later) and In-App Browsers**: In addition to the underlying asynchronous restrictions mentioned above, Apple has also significantly strengthened privacy and anti-popup abuse mechanisms (such as ITP related protections) in recent years. In actual scenarios (especially built-in WebViews of social software / In-App Browsers, or with advanced protections turned on), the review of Tokens has become more opaque and stringent, making front-end developers feel the popup mechanism is "sometimes good, sometimes bad".
     
**Summary and Pitfall Avoidance Guide**:
In pure Web development, front-end engineers often use a well-known bypass trick: "First open a blank window synchronously `window.open('', '_blank')`, wait for the asynchronous request to complete, then modify `location.href`" (can be seen in StackOverflow references below).
However, **this trick often triggers a disaster in Native App (In-App Browser / WebView) development**. When the front-end opens a blank window, the native end's `WKUIDelegate` or `WebChromeClient` will intercept a request with an empty URL (`""`) or `about:blank` in the first time, causing the native end to be unable to parse the interception or route the Deep Link correctly based on the URL; if the native end reluctantly allows it to pass, the user will first see a confusing blank screen, leading to a terrible experience.

Therefore, because the life cycle determination mechanisms of the dual-platform engines are completely inconsistent, coupled with the fact that the Web-end workaround is not acclimatized in the native environment, adopting **JSBridge** to let the native end completely take over the behavior remains the only standard solution that guarantees 100% stable operation across both platforms.

## 5. References
- 📖 [Chromium Official Blog: User Activation v2 (UAv2) Mechanism Introduction](https://developer.chrome.com/blog/user-activation)
- 📖 [MDN Web Docs: Transient Activation](https://developer.mozilla.org/en-US/docs/Glossary/Transient_activation)
- 📖 [Chromium Source Code: user_activation_state.h (Reveals the 5-second constant kActivationLifespan)](https://github.com/chromium/chromium/blob/7115760f2e6dafa470a579182b2709ded743e683/third_party/blink/public/common/frame/user_activation_state.h#L23)
- 📖 [Chromium Source Code: user_activation_state.cc (Token refresh implementation)](https://source.chromium.org/chromium/chromium/src/+/main:third_party/blink/common/frame/user_activation_state.cc)
- 📖 [Android Official Docs: setJavaScriptCanOpenWindowsAutomatically](https://developer.android.com/reference/android/webkit/WebSettings#setJavaScriptCanOpenWindowsAutomatically(boolean))
- 📖 [Apple Developer Docs: WKPreferences.javaScriptCanOpenWindowsAutomatically](https://developer.apple.com/documentation/webkit/wkpreferences/javascriptcanopenwindowsautomatically)
- 📖 [Mozilla Bugzilla #1469730: window.open popup is blocked from microtask](https://bugzilla.mozilla.org/show_bug.cgi?id=1469730)
- 📖 [GitHub WICG/interventions #12: user gesture required for sensitive operations (Reveals WebKit's 1-second grace period for setTimeout)](https://github.com/WICG/interventions/issues/12)
- 📖 [WebKit Bugzilla #225559: Implement standards-compliant user gesture tracking](https://bugs.webkit.org/show_bug.cgi?id=225559)
- 📖 [WebKit Bugzilla #215014: Move user gesture propagation over promise behind a feature flag](https://bugs.webkit.org/show_bug.cgi?id=215014)
- 📖 [WebKit Bug 313797 / Commit ebeb545: Propagate user gestures through sendMessage](https://github.com/WebKit/WebKit/commit/ebeb54525a799f353a717f2492acf7066433efbc)
- 📖 [StackOverflow: Safari `window.open` async workaround](https://stackoverflow.com/questions/20696041/window-openurl-blank-not-working-on-imac-safari)

---

> [!TIP]
> **Want to see actual test results and recordings?**
> The iOS and Android interception test recordings of this project have been unified and arranged in the [README_en.md](../README_en.md) on the project's homepage.
