# iOS WebView Strictness Analysis: From WebKit Policies to Third-Party App (In-App Browser) Restrictions

[中文版](ios_webview_strictness_and_in_app_browsers.md)

When testing cross-platform WebView popups (`window.open` or dynamically creating `<a>` tags), many front-end developers find that iOS behavior is not only unusually strict, but in the real world (such as opening in social software like LINE, Facebook), they may even encounter situations worse than the original factory defaults.

This document summarizes the defense mechanisms and restrictions of iOS WebView (mainly WKWebView) under different versions and scenarios.

## 1. iOS WebKit's Strict Review of Asynchronous Tokens

Compared to Android Chromium engine's relatively lenient "User Activation v2 (UAv2)" 5-second grace period, Apple's WebKit engine is noticeably stricter in reviewing "Async Callbacks":
- **0-Second Grace for Promises like `fetch`**: As long as network requests or other asynchronous Promise operations are involved, the Token is immediately confiscated, causing subsequent `window.open` calls to inevitably be judged by the underlying layer as malicious background popups and thus blocked.
- **Extremely Short Grace for `setTimeout`**: Only the first layer of `setTimeout` is given an extremely short grace period of about 1 second. Timeouts or nested calls will also cause immediate failure.

> [!NOTE]
> More detailed historical evolution and handling differences for Macrotask (`setTimeout`) and Microtask (`Promise`) in the underlying Event Loop of iOS WebKit have been unified in Section 4 of: [async_popup_blocker_history_en.md](./async_popup_blocker_history_en.md).

## 2. Stricter Challenges in the Real World: Third-Party App Built-in Browsers (In-App Browsers)

In self-developed Apps, as long as the `WKUIDelegate` protocol is implemented, at least "synchronous" click `window.open` can operate successfully and be intercepted. But in real online environments, webpages are often opened through WebViews within third-party Apps (e.g., LINE, Facebook, Instagram), and front-end often faces the dilemma where **even the most basic synchronous `window.open` fails**.

### Why is it completely blocked?
1. **iOS Default Behavior is Inaction**: In iOS WKWebView, `window.open` and `target="_blank"` default to having **no behavior whatsoever**.
2. **Control over the Delegation Mechanism**: To make `window.open` take effect, the native developer **must** manually implement the `createWebViewWithConfiguration` function in `WKUIDelegate` to actively "catch" the front-end's request to open a new window.
3. **Selfishness of Social Software**: Many social Apps, in order to keep users' eyeballs "locked in their own App ecosystem", will deliberately not implement this function, or directly return `nil` (refusing to open) within the function.
4. **Result**: This causes front-end `window.open` requests to disappear silently, as if thrown into a black hole.

## 3. Apple Privacy Policies and ITP (Intelligent Tracking Prevention) Impact

Apple has significantly enhanced the ITP anti-tracking mechanism in Safari and WebKit in recent years.

If the target of a `window.open` redirection is a third-party advertising domain with cross-site tracking parameters (for example, for some kind of affiliate redirect or OAuth authentication), on newer iOS systems (iOS 14+), even if this is a perfect synchronous click, WebKit may forcibly activate privacy protection interventions because it judges the URL as suspected of "Cross-Site Tracking", further restricting or blocking popups or Cookie transmissions.

## 4. Appendix: iOS WebView Versions and Support Lifecycle (Recorded on 2026-07-17)

When planning cross-platform WebView development, it is very important to understand the evolution and support boundaries of iOS versions:

- **Introduction of WKWebView (Oldest Support Starting Point)**: Apple first introduced `WKWebView` in **iOS 8 (Released Sep 2014)** to replace the low-performance `UIWebView` which suffered from memory leaks.

- **Total Ban of UIWebView (End of Support)**: Apple announced the policy in **December 2019**, and from **April 2020** stopped accepting new Apps using UIWebView. Since **December of the same year**, even updates for existing Apps were banned. This means that active iOS Apps on the market today have 100% migrated to `WKWebView`.
- **Officially Stated Version Support**: As of **July 2026**, the minimum support version for most modern and mainstream Apps is usually set at **iOS 15 (Released Sep 2021)** or **iOS 16 (Released Sep 2022)**. iOS 15 is the absolute limit to which a batch of classic old devices (like iPhone 6s, iPhone 7) can be upgraded. For older systems below this version, Apple has effectively ceased regular security and framework update support.

---

## Conclusion and Countermeasures

The strict iOS defense tested in local test Apps is actually just the "**basic bottom line**" given by Apple officially.

In real online environments, front-end developers often face **more uncontrollable and closed** WebView environments (third-party Apps simply do not implement popup delegation). This further corroborates the final conclusion of the cross-platform front-end architecture:

**As long as the browser's native popups (`window.open` / `target="_blank"`) are involved, the initiative for defense will always remain in the hands of Apple and native App developers.**

The only solution that the front-end can grasp 100% and guarantee stable operation is to **abandon reliance on the native browser's popup behavior**, and switch to:
1. **In-Page Routing Redirection (SPA)**
2. **In-Page Redirection (`location.href`)** avoiding popup blocker
3. **Via JSBridge** calling native App Functions, letting the native App decide whether to open the system default browser or push a new WebView window.
