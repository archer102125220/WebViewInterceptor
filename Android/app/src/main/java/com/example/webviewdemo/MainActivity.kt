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
    private val TAG = "WebViewDemo"
    private val SERVER_IP = BuildConfig.SERVER_IP

    // 【JSBridge 原生通訊實作】
    // 為什麼要用 JSBridge 處理跳轉？
    // 因為這完全避開了 WebView / Chromium 對於 window.open 的嚴格彈窗限制。
    // JSBridge 傳遞訊息不涉及開啟視窗的行為，因此它完全不需要 User Gesture Token，
    // 不受限於 Android 的 5 秒網路寬限期，也不管是否處在非同步回呼 (setTimeout/fetch) 的深處。
    // 只要網頁將網址丟給原生，原生就能直接透過 Intent 呼叫系統瀏覽器，達成 100% 成功率。
    inner class WebAppInterface {
        @android.webkit.JavascriptInterface
        fun openUrl(url: String) {
            runOnUiThread {
                try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    startActivity(intent)
                } catch (e: Exception) {
                    Toast.makeText(this@MainActivity, "無法開啟網址", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

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
        
        // 註冊 JSBridge
        webView.addJavascriptInterface(WebAppInterface(), "NativeBridge")
        
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

        val isServerDisabled = SERVER_IP.isEmpty()
        val btnSuffix = if (isServerDisabled) " (未啟動)" else ""
        val aTagStyle = if (isServerDisabled) "background-color: #6c757d; pointer-events: none; opacity: 0.5;" else "background-color: #0d6efd;"
        val btnStyle = if (isServerDisabled) "background-color: #6c757d; opacity: 0.5;" else "background-color: #198754;"
        val btnDisabledAttr = if (isServerDisabled) "disabled" else ""

        // 從 assets 資料夾讀取外部 HTML，這會讓網頁源碼更容易獨立閱讀和修改
        try {
            val inputStream = assets.open("index.html")
            var htmlContent = inputStream.bufferedReader().use { it.readText() }
            
            // 動態替換變數 (因為是靜態檔，用取代的方式放回去)
            htmlContent = htmlContent.replace("{{SERVER_IP}}", SERVER_IP)
            htmlContent = htmlContent.replace("{{aTagStyle}}", aTagStyle)
            htmlContent = htmlContent.replace("{{btnStyle}}", btnStyle)
            htmlContent = htmlContent.replace("{{btnDisabledAttr}}", btnDisabledAttr)
            htmlContent = htmlContent.replace("{{btnSuffix}}", btnSuffix)
            
            // 載入 HTML 字串
            webView.loadDataWithBaseURL(null, htmlContent, "text/html", "UTF-8", null)
        } catch (e: Exception) {
            e.printStackTrace()
            Toast.makeText(this, "找不到 index.html！", Toast.LENGTH_LONG).show()
        }
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
