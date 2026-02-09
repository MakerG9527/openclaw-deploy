// ES 模块代理 bootstrap - 为 Node.js fetch 配置代理
import { ProxyAgent } from "/usr/lib/node_modules/openclaw/node_modules/undici/index.js";

const proxyUrl = process.env.HTTP_PROXY || process.env.http_proxy || "http://127.0.0.1:7890";

if (proxyUrl) {
  try {
    // 创建 proxy agent
    const proxyAgent = new ProxyAgent(proxyUrl);
    
    // 保存原始 fetch
    const originalFetch = globalThis.fetch;
    
    // 覆盖全局 fetch，自动添加 dispatcher
    globalThis.fetch = function(input, init) {
      if (!init) init = {};
      if (!init.dispatcher) {
        init.dispatcher = proxyAgent;
      }
      return originalFetch(input, init);
    };
    
    console.log("[proxy-bootstrap] Fetch proxy configured:", proxyUrl);
  } catch (e) {
    console.error("[proxy-bootstrap] Failed to configure proxy:", e.message);
  }
}
