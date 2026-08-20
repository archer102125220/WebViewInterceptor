const http = require("http");
const fs = require("fs");
const path = require("path");
const os = require("os");
const { exec } = require("child_process");

const PORT = 3000;

// 自動獲取本機的區域網路 IP
function getLocalIp() {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === "IPv4" && !iface.internal) {
        return iface.address;
      }
    }
  }
  return "127.0.0.1";
}

const currentIp = getLocalIp();

// 動態寫入 IP 到 env.properties (Android 使用) 與 ServerConfig.swift (iOS 使用)
function writeIpToEnvFiles(ip) {
  // 1. Android 使用 env.properties (在 build.gradle 讀取)
  const envPath = path.join(__dirname, "env.properties");
  const envData = `SERVER_IP=${ip}\n`;
  fs.writeFileSync(envPath, envData, "utf8");
  console.log(
    `[Auto-Inject] Successfully wrote local IP (${ip}) to mock-server/env.properties`,
  );

  // 2. iOS 使用 ServerConfig.swift
  const iosConfigPath = path.join(
    __dirname,
    "../IOS/WebViewInterceptorDemo/ServerConfig.swift",
  );
  const iosConfigData = `// 自動生成的 IP 設定檔 (由 mock-server 產生)
// 由於此檔案已經被標記為 assume-unchanged，因此不會產生 git 異動紀錄
import Foundation

let SERVER_IP = "${ip}"
`;
  fs.writeFileSync(iosConfigPath, iosConfigData, "utf8");
  console.log(
    `[Auto-Inject] Successfully wrote local IP (${ip}) to IOS/WebViewInterceptorDemo/ServerConfig.swift`,
  );

  // 自動執行 git 命令，讓此檔案的修改被 Git 忽略
  exec(
    "git update-index --assume-unchanged IOS/WebViewInterceptorDemo/ServerConfig.swift",
    (err) => {
      if (!err) {
        console.log(
          `[Auto-Inject] Successfully applied git assume-unchanged to ServerConfig.swift`,
        );
      }
    },
  );
}

// 啟動伺服器前先寫入 env.properties 與 ServerConfig.swift
writeIpToEnvFiles(currentIp);

// 模擬非同步查詢資料庫生成 URL (用於 302 重新導向)
const queryDatabaseForUrl = () => {
  return new Promise((resolve) => {
    const delay = 2000; // 模擬 2 秒的資料庫查詢延遲
    console.log(`[DB] Querying database... (simulating ${delay}ms delay)`);
    setTimeout(() => {
      resolve("https://www.google.com");
    }, delay);
  });
};

function escapeHtml(str) {
  if (str == null) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function renderFormResultPage(res, method, params) {
  const rows = Object.entries(params)
    .map(
      ([k, v]) => `
        <tr>
            <td style="padding: 12px; border: 1px solid #dee2e6; font-weight: bold; background-color: #f8f9fa; color: #495057;">${escapeHtml(k)}</td>
            <td style="padding: 12px; border: 1px solid #dee2e6; word-break: break-all; color: #212529;">${escapeHtml(v)}</td>
        </tr>
    `,
    )
    .join("");

  const isPost = method === "POST";
  const html = `<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>表單跳轉結果 (Form Result)</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            padding: 20px;
            background-color: #f0f2f5;
            color: #212529;
            margin: 0;
        }
        .container {
            max-width: 600px;
            margin: 20px auto;
            background: white;
            padding: 24px;
            border-radius: 12px;
            box-shadow: 0 4px 16px rgba(0,0,0,0.08);
        }
        .badge {
            display: inline-block;
            padding: 6px 16px;
            border-radius: 20px;
            font-size: 14px;
            font-weight: bold;
            margin-bottom: 15px;
        }
        .badge-get { background-color: #d0ebff; color: #1864ab; }
        .badge-post { background-color: #ffe3e3; color: #c92a2a; }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
            margin-bottom: 20px;
        }
        .desc {
            color: #6c757d;
            font-size: 14px;
            line-height: 1.5;
        }
        .info-box {
            background-color: ${isPost ? "#fff9db" : "#e7f5ff"};
            border: 1px solid ${isPost ? "#ffe066" : "#a5d8ff"};
            border-radius: 8px;
            padding: 12px;
            font-size: 14px;
            margin-bottom: 15px;
            color: ${isPost ? "#e67700" : "#1971c2"};
        }
    </style>
</head>
<body>
    <div class="container">
        <span class="badge ${isPost ? "badge-post" : "badge-get"}">HTTP ${method} 接收成功</span>
        <h2 style="margin-top: 0;">🎉 表單跳轉目的地頁面</h2>
        
        <div class="info-box">
            ${
              isPost
                ? "✅ 成功透過 <b>POST 請求</b> 傳送資料到後端！此頁面由 <code>form.submit()</code> 觸發。"
                : "✅ 成功透過 <b>GET 請求</b> 帶參數導向此頁面！此頁面由 <code>form.submit()</code> 觸發。"
            }
        </div>

        <p class="desc">後端解析到的表單參數內容如下：</p>
        
        <table>
            <thead>
                <tr>
                    <th style="padding: 10px; border: 1px solid #dee2e6; background-color: #e9ecef; width: 38%;">參數名稱 (Key)</th>
                    <th style="padding: 10px; border: 1px solid #dee2e6; background-color: #e9ecef;">參數值 (Value)</th>
                </tr>
            </thead>
            <tbody>
                ${rows || '<tr><td colspan="2" style="padding: 12px; text-align: center; color: #999;">無接收到參數</td></tr>'}
            </tbody>
        </table>

        <p style="font-size: 12px; color: #adb5bd; margin-bottom: 0;">接收時間：${new Date().toLocaleString()}</p>
    </div>
</body>
</html>`;

  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  res.end(html);
}

const server = http.createServer(async (req, res) => {
  const parsedUrl = new URL(
    req.url,
    `http://${req.headers.host || "localhost:3000"}`,
  );
  const pathname = parsedUrl.pathname;

  console.log(`[${new Date().toISOString()}] ${req.method} ${pathname}`);

  if (pathname === "/") {
    // 提供測試用的首頁
    const htmlPath = path.join(__dirname, "index.html");
    fs.readFile(htmlPath, (err, data) => {
      if (err) {
        res.writeHead(500);
        res.end("Error loading index.html");
        return;
      }
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      res.end(data);
    });
  } else if (pathname === "/redirect") {
    // 處理 302 延遲跳轉請求
    try {
      // 異步等待資料庫查詢結果
      const targetUrl = await queryDatabaseForUrl();
      console.log(`[Redirect] Redirecting to ${targetUrl}`);

      // 執行 302 重新導向
      res.writeHead(302, { Location: targetUrl });
      res.end();
    } catch (error) {
      res.writeHead(500);
      res.end("Server Error");
    }
  } else if (pathname === "/form-bridge") {
    // 提供中繼跳轉頁面 (在 <script> 內頂層呼叫 API 並透過 Form 跳轉)
    const htmlPath = path.join(__dirname, "form-bridge.html");
    fs.readFile(htmlPath, (err, data) => {
      if (err) {
        res.writeHead(500);
        res.end("Error loading form-bridge.html");
        return;
      }
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      res.end(data);
    });
  } else if (pathname === "/api/target-info") {
    // 模擬 API 提供目的地 URL 與表單參數
    const requestedMethod = (
      parsedUrl.searchParams.get("method") || "GET"
    ).toUpperCase();
    const delayParam = parsedUrl.searchParams.get("delay");
    const delay = delayParam ? parseInt(delayParam, 10) : 600; // 支援動態延遲 (預設 600ms)
    console.log(`[API] /api/target-info requested: method=${requestedMethod}, delay=${delay}ms`);

    setTimeout(() => {
      res.writeHead(200, {
        "Content-Type": "application/json; charset=utf-8",
        "Access-Control-Allow-Origin": "*",
      });
      res.end(
        JSON.stringify({
          targetUrl: "/form-result",
          method: requestedMethod,
          params: {
            tradeNo: "TRADE_" + Date.now(),
            userId: "user_888",
            authCode:
              "AUTH_" +
              Math.random().toString(36).substring(2, 8).toUpperCase(),
            timestamp: new Date().toISOString(),
            formMethod: requestedMethod,
            source: "mock_server_api",
            apiDelay: delay + "ms",
          },
        }),
      );
    }, delay);
  } else if (pathname === "/form-result") {
    // 表單跳轉目的地頁面 (處理 GET 與 POST)
    if (req.method === "POST") {
      let body = "";
      req.on("data", (chunk) => {
        body += chunk.toString();
      });
      req.on("end", () => {
        const params = {};
        const searchParams = new URLSearchParams(body);
        for (const [key, value] of searchParams.entries()) {
          params[key] = value;
        }
        renderFormResultPage(res, "POST", params);
      });
    } else {
      const params = {};
      for (const [key, value] of parsedUrl.searchParams.entries()) {
        params[key] = value;
      }
      renderFormResultPage(res, "GET", params);
    }
  } else {
    res.writeHead(404);
    res.end("Not Found");
  }
});

server.listen(PORT, () => {
  console.log(`Server is running at http://localhost:${PORT}`);
  console.log(`Open this URL in your browser or WebView to test.`);
});
