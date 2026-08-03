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
const { exec } = require('child_process');

// 動態寫入 IP 到 env.properties (Android 使用) 與 ServerConfig.swift (iOS 使用)
function writeIpToEnvFiles(ip) {
    // 1. Android 使用 env.properties (在 build.gradle 讀取)
    const envPath = path.join(__dirname, 'env.properties');
    const envData = `SERVER_IP=${ip}\n`;
    fs.writeFileSync(envPath, envData, 'utf8');
    console.log(`[Auto-Inject] Successfully wrote local IP (${ip}) to mock-server/env.properties`);

    // 2. iOS 使用 ServerConfig.swift
    const iosConfigPath = path.join(__dirname, '../IOS/WebViewInterceptorDemo/ServerConfig.swift');
    const iosConfigData = `// 自動生成的 IP 設定檔 (由 mock-server 產生)
// 由於此檔案已經被標記為 assume-unchanged，因此不會產生 git 異動紀錄
import Foundation

let SERVER_IP = "${ip}"
`;
    fs.writeFileSync(iosConfigPath, iosConfigData, 'utf8');
    console.log(`[Auto-Inject] Successfully wrote local IP (${ip}) to IOS/WebViewInterceptorDemo/ServerConfig.swift`);

    // 自動執行 git 命令，讓此檔案的修改被 Git 忽略
    exec('git update-index --assume-unchanged IOS/WebViewInterceptorDemo/ServerConfig.swift', (err) => {
        if (!err) {
            console.log(`[Auto-Inject] Successfully applied git assume-unchanged to ServerConfig.swift`);
        }
    });
}

// 啟動伺服器前先寫入 env.properties 與 ServerConfig.swift
writeIpToEnvFiles(currentIp);

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
