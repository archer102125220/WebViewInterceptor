import UIKit
import WebKit

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

    var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // 1. 初始化 WKWebViewConfiguration
        let preferences = WKPreferences()
        
        // 【關鍵設定：模擬高資安防禦模式】
        // 企業級 App 通常會將此設為 false (WKWebView 預設為 false)。
        // iOS WebKit 引擎對於實體點擊 (User Gesture Token) 的管控極度嚴格，
        // 完全不像 Android (Chromium UAv2) 還有 5 秒的寬限期。
        // 只要進入 async/await、fetch、setTimeout 的非同步回呼，Token 就會立刻失效，
        // 隨後的 window.open 將會被底層當作惡意彈窗無情抹殺！
        preferences.javaScriptCanOpenWindowsAutomatically = false
        
        let config = WKWebViewConfiguration()
        config.preferences = preferences
        
        // 註冊 JSBridge
        let contentController = WKUserContentController()
        contentController.add(self, name: "NativeBridge")
        config.userContentController = contentController

        // 2. 建立 WKWebView
        webView = WKWebView(frame: self.view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.view.addSubview(webView)

        // 3. 準備與 Android 一模一樣的 HTML
        let htmlContent = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                body { font-family: sans-serif; padding: 20px; text-align: center; }
                button { padding: 15px; margin: 10px; font-size: 16px; background: #007bff; color: white; border: none; border-radius: 8px; width: 100%; box-sizing: border-box; transition: transform 0.1s, opacity 0.1s; }
                a { display: block; padding: 15px; margin: 10px; font-size: 16px; background: #28a745; color: white; border-radius: 8px; text-decoration: none; box-sizing: border-box; transition: transform 0.1s, opacity 0.1s; }
                button:active, a:active { transform: scale(0.96); opacity: 0.8; }
            </style>
            <script>
                function callNativeBridgeToOpenUrl(url) {
                    if (window.NativeBridge && window.NativeBridge.openUrl) {
                        window.NativeBridge.openUrl(url);
                    } else if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.NativeBridge) {
                        window.webkit.messageHandlers.NativeBridge.postMessage(url);
                    } else {
                        alert('找不到 NativeBridge');
                    }
                }
            </script>
        </head>
        <body>
            <h2>iOS WKWebView 跳轉測試</h2>
            
            <h3>🟢 雙平台皆成功：A Tag 實體點擊</h3>
            <a href="https://www.google.com">1. a tag 當頁跳轉</a>
            <a href="https://www.google.com" target="_blank">2. a tag 另開分頁 (target="_blank")</a>
            <button onclick="
                const a = document.createElement('a');
                a.href = 'https://www.google.com';
                a.target = '_blank';
                a.click();
            ">3. 同步動態建立 a tag 並 click (繞過 window.open)</button>
            
            <h3>🟢 雙平台皆成功：JS 同步跳轉</h3>
            <button onclick="location.href='https://www.google.com'">4. location.href 當頁跳轉</button>
            <button onclick="window.open('https://www.google.com', '_self')">5. window.open 當頁 (_self)</button>
            <button onclick="window.open('https://www.google.com', '_blank')">6. window.open 另開分頁 (_blank)</button>

            <h3>🟢 雙平台皆成功：非同步與 Event Loop (無視窗開啟限制)</h3>
            <button onclick="Promise.resolve().then(() => location.href='https://www.google.com')">7. Microtask (Promise) -> location.href</button>
            <button onclick="setTimeout(() => location.href='https://www.google.com', 1000)">8. Macrotask (setTimeout) -> location.href</button>
            <button onclick="
                Promise.resolve().then(() => {
                    const a = document.createElement('a');
                    a.href = 'https://www.google.com';
                    a.target = '_blank';
                    a.click();
                });
            ">9. Microtask (Promise) 動態建立 a tag (同 Tick 傳遞，雙平台成功)</button>
            <button onclick="Promise.resolve().then(() => window.open('https://www.google.com', '_blank'))">10. Microtask (Promise) -> window.open (同 Tick 傳遞，雙平台成功)</button>

            <hr style="margin-top: 30px; margin-bottom: 20px;">
            <h3>🟡 平台限制與差異：只有某一方會成功</h3>
            
            <h4 style="margin-bottom: 5px; color: #d39e00;">僅 Android 成功 (iOS 視為惡意彈窗封殺)</h4>
            <button onclick="setTimeout(() => window.open('https://www.google.com', '_blank'), 1000)">11. Macrotask (setTimeout 1s) -> window.open (iOS 必擋)</button>
            <button onclick="setTimeout(() => window.open('https://www.google.com', '_blank'), 3000)">12. 延遲 3 秒後 window.open</button>
            <button onclick="
                fetch('https://jsonplaceholder.typicode.com/todos/1')
                    .then(res => res.json())
                    .then(() => {
                        const w = window.open('https://www.google.com', '_blank');
                        if(!w) alert('攔截大失敗！window.open 被瀏覽器底層當作惡意彈窗封殺了！');
                    });
            ">13. 真實情境：Fetch API 回傳後才 window.open (Android 視網路速度 &lt; 5s 放行)</button>
            <button onclick="
                fetch('https://jsonplaceholder.typicode.com/todos/1')
                    .then(res => res.json())
                    .then(() => {
                        const a = document.createElement('a');
                        a.href = 'https://www.google.com';
                        a.target = '_blank';
                        a.click();
                    });
            ">14. 真實情境：Fetch API 後動態 a tag (Android 視網路速度 &lt; 5s 放行)</button>

            <h4 style="margin-bottom: 5px; color: #d39e00;">僅 iOS 成功 (Android 原生攔截器穿透)</h4>
            <form method="POST" action="https://www.google.com" style="margin: 10px;">
                <button type="submit" style="background: #dc3545; width: 100%; padding: 15px; font-size: 16px; color: white; border: none; border-radius: 8px;">15. 表單 POST 跳轉 (Android 穿透 / iOS 成功攔截)</button>
            </form>

            <hr style="margin-top: 30px; margin-bottom: 20px;">
            <h3 style="color: red;">🔴 雙平台皆失效 (攔截死角與超時封殺)</h3>
            <button onclick="history.pushState(null, '', '#new-page'); alert('網址已變更為 #new-page，但原生攔截器完全沒收到通知！')">16. SPA 路由切換 (history.pushState)</button>
            <button onclick="setTimeout(() => { const w = window.open('https://www.google.com', '_blank'); if(!w) alert('攔截大失敗！window.open 被瀏覽器底層當作惡意彈窗封殺了！'); }, 6000)">17. 延遲 6 秒後 window.open (超出 Android 5秒寬限期)</button>
            <button onclick="
                setTimeout(() => {
                    const a = document.createElement('a');
                    a.href = 'https://www.google.com';
                    a.target = '_blank';
                    a.click();
                }, 6000);
            ">18. Macrotask (延遲 6 秒) 動態建立 a tag (雙平台皆封殺)</button>

            <hr style="margin-top: 30px; margin-bottom: 20px;">
            <h3>🟣 JSBridge 原生通訊 (完美避開所有攔截與封殺)</h3>
            <button onclick="callNativeBridgeToOpenUrl('https://www.google.com')">19. 同步觸發 JSBridge 開啟網址</button>
            <button onclick="Promise.resolve().then(() => callNativeBridgeToOpenUrl('https://www.google.com'))">20. Microtask (Promise) 觸發 JSBridge 開啟網址</button>
            <button onclick="setTimeout(() => callNativeBridgeToOpenUrl('https://www.google.com'), 1000)">21. Macrotask (setTimeout) 觸發 JSBridge 開啟網址</button>
            <button onclick="
                fetch('https://jsonplaceholder.typicode.com/todos/1')
                    .then(res => res.json())
                    .then(() => callNativeBridgeToOpenUrl('https://www.google.com'));
            ">22. 真實情境：Fetch API 回傳後觸發 JSBridge 開啟網址</button>

            <hr style="margin-top: 30px; margin-bottom: 20px;">
            <h3>原有的自定義攔截測試</h3>
            <button onclick="location.href='myapp://open_profile?user_id=123'">觸發 myapp:// 協定</button>
            <button onclick="location.href='https://www.youtube.com'">跳轉 YouTube (攔截到外部)</button>
        </body>
        </html>
        """

        webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    // 共用的彈窗顯示邏輯
    func showInterceptDialog(url: URL, apiMethod: String, isUserGesture: Bool) {
        let gestureText = isUserGesture ? "是 (true)" : "否 (false)"
        
        let alert = UIAlertController(
            title: "跳轉攔截確認",
            message: "目標網址：\n\(url.absoluteString)\n\n攔截來源 API：\n\(apiMethod)\n\n物理點擊 (User Gesture)：\n\(gestureText)",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "跳轉出去", style: .default, handler: { _ in
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }))
        
        alert.addAction(UIAlertAction(title: "留在 App 內", style: .default, handler: { [weak self] _ in
            if url.scheme == "http" || url.scheme == "https" {
                let request = URLRequest(url: url)
                self?.webView.load(request)
            } else {
                print("自定義協定無法在 WebView 內部載入")
            }
        }))
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        
        self.present(alert, animated: true, completion: nil)
    }

    /*
     * 【歷史冷知識：iOS 對腳本跳轉的良好支援】
     * 在 iOS，從最古老的 UIWebView 時代 (shouldStartLoadWithRequest) 
     * 到現在的 WKWebView (decidePolicyFor)，Apple 始終保持良好的設計：
     * 不論是「人為實體點擊 (a tag)」還是「腳本觸發 (location.href)」，
     * 通通都會乖乖進入這同一個攔截器。
     * iOS 只是優雅地透過 navigationType (例如 .linkActivated 或 .other) 來讓開發者分辨觸發來源，
     * 所以 iOS 開發者從來不需要像早期的 Android 那樣，為了攔截腳本而到處掛載不同的生命週期事件。
     */
    // MARK: - WKNavigationDelegate (對應 Android 的 shouldOverrideUrlLoading)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        
        let urlString = url.absoluteString
        
        // iOS 沒有像 Android 的 hasGesture() boolean
        // 而是透過 navigationType 來精準區分：.linkActivated 代表物理點擊 a 標籤，.other 代表 JS 腳本跳轉
        let isUserGesture = (navigationAction.navigationType == .linkActivated)
        
        if urlString.starts(with: "myapp://") || urlString.contains("youtube.com") || urlString.contains("google.com") {
            showInterceptDialog(url: url, apiMethod: "WKNavigationDelegate\n(decidePolicyFor)", isUserGesture: isUserGesture)
            decisionHandler(.cancel)
            return
        }
        
        decisionHandler(.allow)
    }

    /*
     * 【歷史冷知識：iOS 以前對 window.open 的裝死黑歷史】
     * 雖然 iOS 對於當頁跳轉 (location.href) 的攔截做得很完美，
     * 但在早期的 UIWebView 時代，如果網頁呼叫了 `window.open`，iOS 預設是「完全裝死沒有反應」，
     * 而且也沒有提供原生的攔截 API，導致當年開發者被迫要注入自訂的 JS 去覆寫網頁的 window.open 函數。
     * 幸好現在的 WKWebView 引進了 WKUIDelegate，提供了 `createWebViewWith`，
     * 讓我們終於能像 Android 一樣正大光明地攔截新視窗的開啟了！
     */
    // MARK: - WKUIDelegate (對應 Android 的 onCreateWindow)
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        
        // 當 target="_blank" 或 window.open 被呼叫時，會觸發這裡
        if let url = navigationAction.request.url {
            let isUserGesture = (navigationAction.navigationType == .linkActivated)
            showInterceptDialog(url: url, apiMethod: "WKUIDelegate\n(createWebViewWith)", isUserGesture: isUserGesture)
        }
        
        // iOS 最棒的地方：回傳 nil 就等同於攔截掉這次的新視窗建立，完全不會像 Chromium 一樣閃退！
        return nil
    }

    // MARK: - WKScriptMessageHandler
    // 【JSBridge 原生通訊實作】
    // 為什麼要用 JSBridge 處理跳轉？
    // 因為 iOS WebKit 對於 window.open 管控極度嚴格，只要在非同步回呼 (setTimeout/fetch) 裡呼叫，
    // User Gesture Token 就會瞬間失效並導致視窗被底層直接封殺，完全不留情面。
    // 但透過 WKScriptMessageHandler 傳遞字串完全不是「開啟新視窗」的行為，因此免疫了所有的彈窗封殺政策。
    // 只要網頁成功把網址拋過來，原生就可以直接透過 UIApplication 開啟系統瀏覽器，達成 100% 的跳轉成功率。
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "NativeBridge" {
            if let urlString = message.body as? String, let url = URL(string: urlString) {
                DispatchQueue.main.async {
                    if UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    }
                }
            }
        }
    }
}
