package com.example.webviewdemo

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView

    private fun showInterceptDialog(url: String, apiMethod: String, isUserGesture: Boolean?) {
        val gestureText = if (isUserGesture == true) "是 (true)" else "否 (false)"
        AlertDialog.Builder(this)
            .setTitle("跳轉攔截確認")
            .setMessage("目標網址：\n$url\n\n攔截來源 API：\n$apiMethod\n\n使用者手勢 (User Gesture)：\n$gestureText")
            .setPositiveButton("跳轉出去") { _, _ ->
                try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    startActivity(intent)
                } catch (e: Exception) {
                    Toast.makeText(this, "無法開啟外部應用程式", Toast.LENGTH_SHORT).show()
                }
            }
            .setNegativeButton("留在 App 內") { _, _ ->
                if (url.startsWith("http") || url.startsWith("https")) {
                    webView.loadUrl(url)
                } else {
                    Toast.makeText(this, "自定義協定無法在 WebView 內部載入", Toast.LENGTH_SHORT).show()
                }
            }
            .setNeutralButton("取消", null)
            .show()
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // 動態建立 WebView 並設定為 ContentView，省去 XML layout
        webView = WebView(this)
        setContentView(webView)

        // 啟用 JavaScript 與多視窗支援
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            
            // 允許開新視窗 (支援 window.open 與 target="_blank")
            setSupportMultipleWindows(true)
            
            // 【關鍵設定：模擬高資安防禦模式】
            // 企業級 App 通常會將此設為 false 避免廣告彈窗。
            // 但受惠於 Chromium 的「User Activation v2 (UAv2)」機制，
            // 只要使用者的實體點擊發生在 5 秒內 (kActivationLifespan)，
            // 即使是透過 async/await、fetch、setTimeout 觸發的 window.open 依然會被放行。
            // 網路延遲超過 5 秒時，此憑證才會失效。
            javaScriptCanOpenWindowsAutomatically = false 
        }
        
        // 設置 WebChromeClient 來支援 window.open 與 target="_blank"
        webView.webChromeClient = object : android.webkit.WebChromeClient() {
            override fun onCreateWindow(view: WebView?, isDialog: Boolean, isUserGesture: Boolean, resultMsg: android.os.Message?): Boolean {
                // 為了避免將目前的 WebView 實例傳入導致 Chromium 內部閃退，
                // 我們建立一個臨時的 WebView，並設定其 WebViewClient 來攔截被打開的網址
                val newWebView = WebView(this@MainActivity)
                newWebView.webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                        val url = request?.url.toString()
                        showInterceptDialog(url, "WebChromeClient.onCreateWindow\n(處理 target=\"_blank\" 或 window.open 另開分頁)", isUserGesture)
                        return true // 攔截該次跳轉，不真正載入網頁
                    }
                }
                
                val transport = resultMsg?.obj as? WebView.WebViewTransport
                transport?.webView = newWebView
                resultMsg?.sendToTarget()
                return true
            }
        }

        /* 
         * 【歷史冷知識：Android 腳本跳轉穿透的黑歷史】
         * 在早期 Android (約 API 24 以前) 的 WebChromeClient 與 WebViewClient 設計中，
         * shouldOverrideUrlLoading 只有在「使用者物理點擊 (a tag)」時才會被觸發。
         * 如果網頁透過 JS 腳本執行 `location.href = "..."`，會直接跳轉，完全無視這個攔截器！
         * 導致當年開發者被迫要在 `onPageStarted` 或 `shouldInterceptRequest` 另尋出路來攔截腳本跳轉。
         * 
         * 【現代的統一】
         * 如今的 Android WebView 已經將「人為點擊」與「腳本跳轉 (location.href)」統一，
         * 兩者都會進入這個 shouldOverrideUrlLoading 攔截器中。
         * 系統改由提供 `request.hasGesture()` 來讓開發者判斷這是否為使用者親手點擊。
         */
        // 設置 WebViewClient 來攔截跳轉
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val url = request?.url.toString()
                val hasGesture = request?.hasGesture()
                
                // 這裡示範如何攔截特定網址 (例如自定義的 scheme 或特定域名)
                if (url.startsWith("myapp://")) {
                    showInterceptDialog(url, "WebViewClient.shouldOverrideUrlLoading\n(攔截自定義協定 myapp://)", hasGesture)
                    return true
                } else if (url.contains("youtube.com")) {
                    // 攔截 YouTube 網址，並使用外部瀏覽器/App 打開
                    showInterceptDialog(url, "WebViewClient.shouldOverrideUrlLoading\n(模擬跳轉到外部 App 開啟)", hasGesture)
                    return true
                } else if (url.contains("google.com")) {
                    // 攔截我們的測試按鈕 (當頁跳轉)
                    showInterceptDialog(url, "WebViewClient.shouldOverrideUrlLoading\n(處理當頁跳轉 a tag 或 location.href / window.open _self)", hasGesture)
                    return true
                }

                // 其他一般網頁則讓 WebView 自己載入
                return super.shouldOverrideUrlLoading(view, request)
            }
        }

        // 載入一個測試用的 HTML，涵蓋各種跳轉情境
        val htmlContent = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                    body { font-family: sans-serif; padding: 20px; text-align: center; }
                    button { padding: 15px; margin: 10px; font-size: 16px; background: #007bff; color: white; border: none; border-radius: 8px; width: 100%; box-sizing: border-box; transition: transform 0.1s, opacity 0.1s; }
                    a { display: block; padding: 15px; margin: 10px; font-size: 16px; background: #28a745; color: white; border-radius: 8px; text-decoration: none; box-sizing: border-box; transition: transform 0.1s, opacity 0.1s; }
                    button:active, a:active { transform: scale(0.96); opacity: 0.8; }
                </style>
            </head>
            <body>
                <h2>WebView 跳轉攔截測試</h2>
                
                <h3>🟢 雙平台皆成功：A Tag 實體點擊</h3>
                <a href="https://www.google.com">1. a tag 當頁跳轉</a>
                <a href="https://www.google.com" target="_blank">2. a tag 另開分頁 (target="_blank")</a>
                <button onclick="
                    const a = document.createElement('a');
                    a.href = 'https://www.google.com';
                    a.target = '_blank';
                    a.click();
                ">15. 同步動態建立 a tag 並 click (繞過 window.open)</button>
                
                <h3>🟢 雙平台皆成功：JS 同步跳轉</h3>
                <button onclick="location.href='https://www.google.com'">3. location.href 當頁跳轉</button>
                <button onclick="window.open('https://www.google.com', '_self')">4. window.open 當頁 (_self)</button>
                <button onclick="window.open('https://www.google.com', '_blank')">5. window.open 另開分頁 (_blank)</button>

                <h3>🟢 雙平台皆成功：非同步與 Event Loop (無視窗開啟限制)</h3>
                <button onclick="Promise.resolve().then(() => location.href='https://www.google.com')">6. Microtask (Promise) -> location.href</button>
                <button onclick="setTimeout(() => location.href='https://www.google.com', 1000)">7. Macrotask (setTimeout) -> location.href</button>
                <button onclick="
                    Promise.resolve().then(() => {
                        const a = document.createElement('a');
                        a.href = 'https://www.google.com';
                        a.target = '_blank';
                        a.click();
                    });
                ">16. Microtask (Promise) 動態建立 a tag (同 Tick 傳遞，雙平台成功)</button>

                <hr style="margin-top: 30px; margin-bottom: 20px;">
                <h3>🟡 平台限制與差異：只有某一方會成功</h3>
                
                <h4 style="margin-bottom: 5px; color: #d39e00;">僅 Android 成功 (iOS 視為惡意彈窗封殺)</h4>
                <button onclick="Promise.resolve().then(() => window.open('https://www.google.com', '_blank'))">8. Microtask (Promise) -> window.open (iOS 視嚴格模式可能封殺)</button>
                <button onclick="setTimeout(() => window.open('https://www.google.com', '_blank'), 1000)">9. Macrotask (setTimeout 1s) -> window.open (iOS 必擋)</button>
                <button onclick="setTimeout(() => window.open('https://www.google.com', '_blank'), 3000)">12. 延遲 3 秒後 window.open</button>
                <button onclick="
                    fetch('https://jsonplaceholder.typicode.com/todos/1')
                        .then(res => res.json())
                        .then(() => {
                            const w = window.open('https://www.google.com', '_blank');
                            if(!w) alert('攔截大失敗！window.open 被瀏覽器底層當作惡意彈窗封殺了！');
                        });
                ">14. 真實情境：Fetch API 回傳後才 window.open</button>
                <button onclick="
                    fetch('https://jsonplaceholder.typicode.com/todos/1')
                        .then(res => res.json())
                        .then(() => {
                            const a = document.createElement('a');
                            a.href = 'https://www.google.com';
                            a.target = '_blank';
                            a.click();
                        });
                ">18. 真實情境：Fetch API 後動態 a tag (Android 視網路速度 &lt; 5s 放行)</button>

                <h4 style="margin-bottom: 5px; color: #d39e00;">僅 iOS 成功 (Android 原生攔截器穿透)</h4>
                <form method="POST" action="https://www.google.com" style="margin: 10px;">
                    <button type="submit" style="background: #dc3545; width: 100%; padding: 15px; font-size: 16px; color: white; border: none; border-radius: 8px;">11. 表單 POST 跳轉 (Android 穿透 / iOS 成功攔截)</button>
                </form>

                <hr style="margin-top: 30px; margin-bottom: 20px;">
                <h3 style="color: red;">🔴 雙平台皆失效 (攔截死角與超時封殺)</h3>
                <button onclick="history.pushState(null, '', '#new-page'); alert('網址已變更為 #new-page，但原生攔截器完全沒收到通知！')">10. SPA 路由切換 (history.pushState)</button>
                <button onclick="setTimeout(() => { const w = window.open('https://www.google.com', '_blank'); if(!w) alert('攔截大失敗！window.open 被瀏覽器底層當作惡意彈窗封殺了！'); }, 6000)">13. 延遲 6 秒後 window.open (超出 Android 5秒寬限期)</button>
                <button onclick="
                    setTimeout(() => {
                        const a = document.createElement('a');
                        a.href = 'https://www.google.com';
                        a.target = '_blank';
                        a.click();
                    }, 6000);
                ">17. Macrotask (延遲 6 秒) 動態建立 a tag (雙平台皆封殺)</button>

                <hr style="margin-top: 30px; margin-bottom: 20px;">
                <h3>原有的自定義攔截測試</h3>
                <button onclick="location.href='myapp://open_profile?user_id=123'">觸發 myapp:// 協定</button>
                <button onclick="location.href='https://www.youtube.com'">跳轉 YouTube (攔截到外部)</button>
            </body>
            </html>
        """.trimIndent()

        // 載入 HTML 字串
        webView.loadDataWithBaseURL(null, htmlContent, "text/html", "UTF-8", null)
    }

    // 處理返回鍵，讓 WebView 可以回上一頁而不是直接退出 App
    override fun onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack()
        } else {
            super.onBackPressed()
        }
    }
}
