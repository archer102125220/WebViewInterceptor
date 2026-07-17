import UIKit
import WebKit

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // 1. 初始化 WKWebViewConfiguration
        let preferences = WKPreferences()
        
        // 【關鍵殺手設定：防禦惡意彈窗】
        // 許多 App 在實作時這裡會設為 false (或未特別開啟，WKWebView 預設可能因版本而異)。
        // 只要是 false，任何失去「同步實體點擊」手勢的 window.open 就會被 WebKit 核心直接抹殺！
        // (這會導致我們畫面上的第 13 顆按鈕直接跳出大失敗的警告)
        preferences.javaScriptCanOpenWindowsAutomatically = true
        
        let config = WKWebViewConfiguration()
        config.preferences = preferences

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
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                body { font-family: sans-serif; padding: 20px; text-align: center; }
                button { padding: 15px; margin: 10px; font-size: 16px; background: #007bff; color: white; border: none; border-radius: 8px; width: 100%; box-sizing: border-box; }
                a { display: block; padding: 15px; margin: 10px; font-size: 16px; background: #28a745; color: white; border-radius: 8px; text-decoration: none; box-sizing: border-box; }
            </style>
        </head>
        <body>
            <h2>iOS WKWebView 跳轉測試</h2>
            
            <h3>A Tag 跳轉</h3>
            <a href="https://www.google.com">1. a tag 當頁跳轉</a>
            <a href="https://www.google.com" target="_blank">2. a tag 另開分頁 (target="_blank")</a>
            
            <h3>JS 跳轉 (同步)</h3>
            <button onclick="location.href='https://www.google.com'">3. location.href 當頁跳轉</button>
            <button onclick="window.open('https://www.google.com', '_self')">4. window.open 當頁 (_self)</button>
            <button onclick="window.open('https://www.google.com', '_blank')">5. window.open 另開分頁 (_blank)</button>

            <h3>腳本觸發 (Event Loop 測試)</h3>
            <button onclick="Promise.resolve().then(() => location.href='https://www.google.com')">6. Microtask (Promise) -> location.href</button>
            <button onclick="setTimeout(() => location.href='https://www.google.com', 1000)">7. Macrotask (setTimeout) -> location.href</button>
            <button onclick="Promise.resolve().then(() => window.open('https://www.google.com', '_blank'))">8. Microtask (Promise) -> window.open</button>
            <button onclick="setTimeout(() => window.open('https://www.google.com', '_blank'), 1000)">9. Macrotask (setTimeout) -> window.open</button>

            <hr style="margin-top: 30px; margin-bottom: 20px;">
            <h3 style="color: red;">攔截失效 / 死角測試</h3>
            <!-- 1. history.pushState 雙平台都失效 -->
            <button onclick="history.pushState(null, '', '#new-page'); alert('網址已變更為 #new-page，但原生攔截器完全沒收到通知！')">10. SPA 路由切換 (history.pushState)</button>
            
            <!-- 2. Form POST 跳轉 (Android 穿透失效, iOS 成功攔截) -->
            <form method="POST" action="https://www.google.com" style="margin: 10px;">
                <button type="submit" style="background: #dc3545; width: 100%; padding: 15px; font-size: 16px; color: white; border: none; border-radius: 8px;">11. 表單 POST 跳轉 (Android穿透 / iOS成功)</button>
            </form>
            
            <!-- 3. 延遲過久的 window.open (iOS 底層可能阻擋, Android 可能放行) -->
            <button onclick="setTimeout(() => window.open('https://www.google.com', '_blank'), 3000)">12. 延遲 3 秒後 window.open</button>

            <!-- 4. 模擬真實 Vue 開發情境：先打 API 再開啟 -->
            <button onclick="
                fetch('https://jsonplaceholder.typicode.com/todos/1')
                    .then(res => res.json())
                    .then(() => {
                        // 經過真實的網路請求後，手勢 Token 幾乎必定遺失
                        let w = window.open('https://www.google.com', '_blank');
                        if(!w) alert('攔截大失敗！window.open 被瀏覽器底層當作惡意彈窗封殺了！');
                    });
            ">13. 真實情境還原：Fetch API 回傳後才 window.open</button>

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
}
