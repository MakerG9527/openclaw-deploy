// ES 模块代理 bootstrap - 为 Node.js fetch 配置代理
// 自动检测 undici 路径，支持多种安装方式

import { createRequire } from 'module';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { execSync } from 'child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

let ProxyAgent;

// 尝试多种方式加载 undici
async function loadUndici() {
  // 方法1: 通过 npm root -g 找到全局安装路径
  let globalPaths = [];
  try {
    const npmRoot = execSync('npm root -g', { encoding: 'utf8', timeout: 5000 }).trim();
    globalPaths.push(npmRoot);
  } catch (e) {
    // npm 命令失败，使用默认路径
  }
  
  // 添加其他可能的路径
  globalPaths.push(
    '/usr/lib/node_modules',
    '/usr/local/lib/node_modules',
    '/opt/node_modules',
    join(process.env.HOME || '', '.npm-global', 'lib', 'node_modules'),
    join(process.env.HOME || '', '.local', 'lib', 'node_modules')
  );
  
  // 尝试从各个路径加载 undici
  for (const basePath of globalPaths) {
    if (!basePath) continue;
    const undiciPaths = [
      join(basePath, 'openclaw', 'node_modules', 'undici'),
      join(basePath, 'undici'),
    ];
    
    for (const undiciPath of undiciPaths) {
      try {
        const undici = await import(undiciPath + '/index.js');
        if (undici.ProxyAgent) {
          return undici.ProxyAgent;
        }
      } catch (e) {
        // 继续尝试下一个路径
      }
    }
  }
  
  // 最后尝试当前目录的 node_modules
  try {
    const localUndici = await import(join(__dirname, 'node_modules', 'undici', 'index.js'));
    if (localUndici.ProxyAgent) {
      return localUndici.ProxyAgent;
    }
  } catch (e) {
    // 失败
  }
  
  throw new Error('无法找到 undici 模块，请确保 openclaw 已正确安装');
}

// 加载 undici 并配置代理
try {
  ProxyAgent = await loadUndici();
  
  const proxyUrl = process.env.HTTP_PROXY || process.env.http_proxy || "http://127.0.0.1:7890";
  
  if (proxyUrl && ProxyAgent) {
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
  }
} catch (e) {
  console.error("[proxy-bootstrap] Failed to configure proxy:", e.message);
  process.exit(1);
}
