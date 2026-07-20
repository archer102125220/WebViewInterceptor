# Android WebView Fragmentation Analysis: Impact of Chromium Core, Third-Party Kernels, and Non-GMS Devices

[中文版](android_webview_fragmentation.md)

The Android platform has always been known for its "Fragmentation". However, when exploring WebView popups and the "User Activation v2 (UAv2)" mechanism, the impact does not simply depend on the phone's hardware brand, but on the **source and version of the underlying browser kernel**.

This document will analyze the gaps and limitations that front-end may encounter when using `window.open`, dynamically creating `<a target="_blank">` tags, or performing asynchronous redirections under different Android environments.

## 1. General Brands with GMS: Highly Consistent Chromium Experience

Since Android 5.0 (Lollipop), Google decoupled the Android System WebView from the bottom layer of the operating system and changed it to be distributed and updated independently via the Google Play Store.

- **Consistent UAv2 Mechanism**: Whether it's Samsung's OneUI, Xiaomi's international MIUI, or Pixel systems, as long as the device is equipped with Google Mobile Services (GMS) and regularly updated online, the underlying engine running is the official latest version of the Chromium engine.
- **Universal Test Results**: On these devices, the Chromium UAv2 "5-second credential grace period (`kActivationLifespan`)" mechanism operates highly consistently and strictly. As long as the asynchronous API delay is within 5 seconds (and not obstructed during this period), `window.open` or dynamically triggered `<a target="_blank">` can be successfully captured and passed by the native layer.

> [!NOTE]
> The handling of the 5-second grace period for Macrotask and Microtask (Promise) in the underlying Event Loop of Android Chromium has been unified in Section 4 of: [async_popup_blocker_history_en.md](./async_popup_blocker_history_en.md).

## 2. True Fragmentation Minefield One: Third-Party Kernels of Super Apps (e.g., Tencent X5)

In the Android ecosystem, the most profound variables usually come from "third-party super Apps". Many super Apps (such as WeChat, QQ), in order to control rendering performance and security, **do not use** the system's built-in Android WebView, but instead embed their own browser kernel (such as Tencent's self-developed X5 kernel).

- **Custom Defense Rules**: The security policies and popup (`window.open` and `<a target="_blank">`) interception logic of the X5 kernel are completely different from Chromium, usually much stricter and contain undisclosed black-box restrictions.
- **Mechanism Failure**: In this environment, Chromium's 5-second grace period does not apply. Not only will asynchronous popups fail, but even in some scenarios, synchronous click events will be ruthlessly blocked by special rules.

## 3. True Fragmentation Minefield Two: Phones without Google Services (e.g., Huawei HarmonyOS)

On non-GMS devices (such as Huawei phones after sanctions, or domestic versions of various brands sold exclusively for the mainland China market), due to the inability to access the Google Play Store, they cannot obtain Google's official System WebView updates.

- **Lagging Kernel Versions**: These devices usually rely on the WebView engine maintained by the manufacturer (such as Huawei's HMS Core built-in engine, usually forked from an older version of Chromium).
- **Residual Old Standards**: These old or heavily modified Chromium engines may still be stuck in older and stricter versions regarding the determination of User Gesture. This causes asynchronous redirections that were expected to pass relying on the UAv2 mechanism to be directly blocked on such devices.

## 4. True Fragmentation Minefield Three: OEM Heavy Modifications and System Restrictions

Although most modern devices use the standard Chromium WebView, major smartphone brands (OEMs) still intervene to varying degrees in WebView behaviors and package selections at the system level. These system-level restrictions interfere with the expected behavior of standard Web APIs:

- **Samsung (Custom Rendering and Forced Behavior)**: Samsung deeply modified the WebView at the system level, which can cause abnormalities even when the user is doing "normal foreground operations". The most famous disaster is that Samsung WebView forces its own "Dark Mode" algorithm, directly ignoring the front-end standard CSS `prefers-color-scheme`, resulting in broken Web UI layouts or forced color inversion (see the famous discussion [Stack Overflow: Samsung Internet forces dark mode](https://stackoverflow.com/questions/66094087/samsung-internet-forces-dark-mode)). This highlights the brutal intervention of OEM brands in standard Web behaviors.
- **Xiaomi and Other Brands (Implicit Intent Interception and URL Scheme Failure)**: During normal foreground use, if a webpage directly triggers deep links like `market://` or `intent://`, the default Android WebView not only fails to recognize them but also directly throws an `ERR_UNKNOWN_URL_SCHEME` error (see the classic debugging discussion [Stack Overflow: WebView ERR_UNKNOWN_URL_SCHEME](https://stackoverflow.com/questions/41693263/android-webview-err-unknown-url-scheme)). More seriously, in highly customized systems like Xiaomi (MIUI / HyperOS), even if the native end tries to intercept and handle it, the system often kidnaps these Intents directly from the bottom layer and **forces redirection to its own "GetApps Store" or "Built-in Browser"**. This system-level malicious interception completely breaks the illusion that the front-end can rely solely on a set of Web Intents to eat all devices.

It must be emphasized that although the above debugging discussions were created early, this exactly reflects that **Android's underlying Intent handling flaws and OEM interception strategies are a long-unsolved "historical karma"**. Even as operating systems continue to upgrade, major OEM brands still maintain such special restrictions at the bottom layer to consolidate their own ecosystems. This proves once again that relying solely on front-end native `window.open` or `<a target="_blank">` for cross-platform or cross-App redirection is extremely fragile and unreliable in the fragmented Android environment.

## 5. The Common Dead End Across Platforms: App Refusing to Implement `WebChromeClient`

Just as the iOS side relies on `WKUIDelegate`, the life and death of front-end popups on Android are also in the hands of native developers.

If a webpage is opened through the built-in browser of third-party Android Apps like Facebook or LINE, as long as the native developer of the App does not implement `onCreateWindow` in `WebChromeClient` (or implements it but deliberately does not handle it), then the `window.open` issued by the front-end or clicking `<a target="_blank">` will also have no response. This has nothing to do with whether the bottom layer has a Chromium 5-second grace period; it is purely a deliberate enclosure at the application layer.

## 6. Appendix: Android WebView Versions and Support Lifecycle (Recorded on 2026-07-17)

When planning cross-platform WebView development, it is very important to understand the evolution and support boundaries of Android WebView:

- **The Starting Point of Independent Updates**: Google made a major architectural change in **Android 5.0 (Lollipop, Released 2014)**, decoupling WebView from the operating system core and changing it to update via the Google Play Store. This solved the previous disaster where "if the system doesn't update, WebView can never be upgraded".
- **The Limit of Play Store Updates**: Although it can be updated via the Play Store, Google still periodically phases out excessively old Android systems. For example, old systems like Android 5, 6, 7 can no longer obtain the latest version of the Chromium core from the Play Store. This means that the WebView engine version of these old devices has been permanently frozen and may not support the latest Web APIs or may have unpatched security vulnerabilities.
- **Officially Stated Version Support**: As of **July 2026**, the minimum support version for most modern and mainstream Apps is usually set at **Android 8.0 (API 26)** or **Android 9.0 (API 28)**.
  - **Main Reason for Choosing Android 8.0 (Released Aug 2017)**: Starting from this version, WebView enables **Multiprocess Architecture** by default, so webpage crashes are no longer likely to cause the entire App to crash.
  - **Main Reason for Choosing Android 9.0 (Released Aug 2018)**: From this version, the **default is changed to block HTTP (forcing HTTPS)**, and the **Display Cutout API** is officially introduced. Both of these have a decisive impact on the security of WebView and front-end layout avoidance.
  - Setting the bottom line at these two watersheds can ensure that the vast majority of users' devices can normally receive Chromium engine updates in recent years, maintaining a relatively consistent rendering and execution environment.

---

## Conclusion and Countermeasures

Although modern Android phones equipped with GMS behave largely consistently on WebView, as long as the target audience of the project includes **users who use super Apps (like WeChat)**, **users using non-GMS devices (mainland China market)**, or even **phones subjected to system-level restrictions from major OEMs (Samsung, Xiaomi, etc.)**, the stability of relying on native popups (`window.open` or `<a target="_blank">`) remains a disaster.

This further reinforces our conclusion that we should adopt **JSBridge**:

By directly passing redirection requests and parameters to native Native APIs via JSBridge, we can completely bypass Chromium, WebKit, Tencent X5, and even the heavy modifications and underlying system restrictions of major phone brands, achieving a 100% stable and controllable cross-platform webpage redirection.
