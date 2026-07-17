# WebView Interceptor Demo

這是一個展示 Android WebView 跳轉攔截 (`shouldOverrideUrlLoading`) 的簡單專案。

## 如何用指令運行在模擬器上

要使用指令運行此專案，請先確保您已經開啟了 Android 模擬器 (Emulator)，或者已經連接了實體 Android 裝置（並開啟了 USB 偵錯）。

### 1. 確認裝置已連接
打開終端機，輸入以下指令確認有抓到裝置：
```bash
adb devices
```
*(如果顯示了 device，代表裝置連接成功)*

### 2. 編譯並安裝到裝置上
在專案根目錄 (`WebViewInterceptorDemo`) 中，執行以下指令：

對於 **Mac/Linux**:
```bash
./gradlew installDebug
```

對於 **Windows**:
```cmd
gradlew.bat installDebug
```

*(注意：第一次執行時 Gradle 會下載一些依賴套件，可能需要一點時間)*

### 3. 在模擬器上啟動 App
安裝成功後，您可以在模擬器的應用程式清單中找到名為 **WebViewInterceptorDemo** 的 App 並點擊開啟。

您也可以透過指令直接啟動它：
```bash
adb shell am start -n com.example.webviewdemo/.MainActivity
```

---

## 為什麼在 Android Studio 中找不到運行按鈕？
如果在 Android Studio 開啟時沒有出現綠色的「Run」按鈕（或者是反灰的），通常是因為 **Gradle 同步 (Sync)** 尚未完成。
請點擊選單列的 **File > Sync Project with Gradle Files**（或者點擊右上角的 Sync 圖示），等待同步完成後，就可以在上方選擇「app」並點擊綠色的播放鍵來運行了。
