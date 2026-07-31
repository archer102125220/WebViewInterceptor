const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 3000;

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
