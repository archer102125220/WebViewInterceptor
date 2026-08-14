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

        let isServerDisabled = SERVER_IP.isEmpty || SERVER_IP == "127.0.0.1"
        let btnSuffix = isServerDisabled ? " (未配置 WebServer)" : ""
        let aTagStyle = isServerDisabled ? "background-color: #6c757d; pointer-events: none; opacity: 0.5;" : "background-color: #0d6efd;"
        let btnStyle = isServerDisabled ? "background-color: #6c757d; opacity: 0.5;" : "background-color: #198754;"
        let btnDisabledAttr = isServerDisabled ? "disabled" : ""

        // 3. 從外部讀取 HTML，這會讓網頁源碼更容易獨立閱讀和修改
        if let htmlURL = Bundle.main.url(forResource: "index", withExtension: "html") {
            do {
                var htmlContent = try String(contentsOf: htmlURL, encoding: .utf8)
                
                // 動態替換變數 (因為是靜態檔，用取代的方式放回去)
                htmlContent = htmlContent.replacingOccurrences(of: "{{SERVER_IP}}", with: SERVER_IP)
                htmlContent = htmlContent.replacingOccurrences(of: "{{aTagStyle}}", with: aTagStyle)
                htmlContent = htmlContent.replacingOccurrences(of: "{{btnStyle}}", with: btnStyle)
                htmlContent = htmlContent.replacingOccurrences(of: "{{btnDisabledAttr}}", with: btnDisabledAttr)
                htmlContent = htmlContent.replacingOccurrences(of: "{{btnSuffix}}", with: btnSuffix)
                
                webView.loadHTMLString(htmlContent, baseURL: Bundle.main.bundleURL)
            } catch {
                print("讀取 HTML 失敗: \(error)")
            }
        } else {
            print("找不到 index.html！請確認已將檔案拖曳至 Xcode 專案中並勾選目標")
        }
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
