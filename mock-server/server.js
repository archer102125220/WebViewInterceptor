const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');

const PORT = 3000;

// 自動獲取本機的區域網路 IP
function getLocalIp() {
    const interfaces = os.networkInterfaces();
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name]) {
            if (iface.family === 'IPv4' && !iface.internal) {
                return iface.address;
            }
        }
    }
    return '127.0.0.1';
}

const currentIp = getLocalIp();

// 動態寫入 IP 到 Android 與 iOS 的原始碼中，達成單一來源自動維護
function injectIpToNativeCode(ip) {
    console.log(`[Auto-Inject] Detecting local IP: ${ip}`);
    
    const androidPath = path.join(__dirname, '../Android/app/src/main/java/com/example/webviewdemo/MainActivity.kt');
    if (fs.existsSync(androidPath)) {
        let code = fs.readFileSync(androidPath, 'utf8');
        code = code.replace(/val SERVER_IP = ".*" \/\/ AUTO-INJECTED-IP/, `val SERVER_IP = "${ip}" // AUTO-INJECTED-IP`);
        fs.writeFileSync(androidPath, code);
        console.log(`[Auto-Inject] Successfully updated Android MainActivity.kt`);
    }

    const iosPath = path.join(__dirname, '../IOS/WebViewInterceptorDemo/ViewController.swift');
    if (fs.existsSync(iosPath)) {
        let code = fs.readFileSync(iosPath, 'utf8');
        code = code.replace(/let SERVER_IP = ".*" \/\/ AUTO-INJECTED-IP/, `let SERVER_IP = "${ip}" // AUTO-INJECTED-IP`);
        fs.writeFileSync(iosPath, code);
        console.log(`[Auto-Inject] Successfully updated iOS ViewController.swift`);
    }
}

// 啟動伺服器前先自動注入 IP
injectIpToNativeCode(currentIp);

// 模擬非同步查詢資料庫生成 URL
const queryDatabaseForUrl = () => {
    return new Promise((resolve) => {
        const delay = 2000; // 模擬 2 秒的資料庫查詢延遲
        console.log(`[DB] Querying database... (simulating ${delay}ms delay)`);
        setTimeout(() => {
            // 模擬查詢到的目標 URL (這邊以 Google 為例)
            resolve('https://www.google.com'); 
        }, delay);
    });
};

const server = http.createServer(async (req, res) => {
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);

    if (req.url === '/') {
        // 提供測試用的 HTML 頁面
        const htmlPath = path.join(__dirname, 'index.html');
        fs.readFile(htmlPath, (err, data) => {
            if (err) {
                res.writeHead(500);
                res.end('Error loading index.html');
                return;
            }
            res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
            res.end(data);
        });
    } else if (req.url === '/redirect') {
        // 處理跳轉請求
        try {
            // 異步等待資料庫查詢結果
            const targetUrl = await queryDatabaseForUrl();
            console.log(`[Redirect] Redirecting to ${targetUrl}`);
            
            // 執行 302 重新導向
            res.writeHead(302, {
                'Location': targetUrl
            });
            res.end();
        } catch (error) {
            res.writeHead(500);
            res.end('Server Error');
        }
    } else {
        res.writeHead(404);
        res.end('Not Found');
    }
});

server.listen(PORT, () => {
    console.log(`Server is running at http://localhost:${PORT}`);
    console.log(`Open this URL in your browser or WebView to test.`);
});
