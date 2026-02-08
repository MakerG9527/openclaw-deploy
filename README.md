# OpenClaw 快速部署包

用于在新服务器上快速部署 OpenClaw + Mihomo 环境。

## 快速开始

### 1. 下载到目标服务器

```bash
git clone git clone https://github.com/MakerG9527/openclaw-deploy.git
mv openclaw-deploy openclaw
```

### 2. 运行交互式配置

```bash
./setup.sh
```

脚本会引导你完成：
- 检测系统环境
- **选择 AI 模型来源**：
  - **选项 1**：使用 Ollama（本地/远程部署的模型）
  - **选项 2**：跳过 Ollama，只使用 API（如 Moonshot/Kimi）
- 配置 Mihomo 代理端口
- 配置默认模型
- 生成 .env 环境变量文件
- 添加 Shell 快捷命令到 ~/.bashrc

**如果你只想使用 API（如 Moonshot）：**
- 选择选项 2（跳过 Ollama）
- 输入 API 模型名称，如 `moonshot/kimi-k2.5`

### 3. 安装 Mihomo（如果未安装）

```bash
./install-mihomo.sh
```

### 4. 添加代理订阅

```bash
./mihomo-sub.sh
# 或直接运行快捷命令
mih-sub
```

### 5. 启动服务

```bash
# 加载新的 bash 配置
source ~/.bashrc

# 启动所有服务
claw-up
# 或
./start-all.sh
```

### 6. 验证部署

```bash
claw-check
```

## 目录结构

```
.
├── setup.sh              # 交互式配置脚本（主入口）⭐
├── install-mihomo.sh     # Mihomo 安装脚本
├── common.sh             # 公共函数库
├── .env                  # 环境变量配置（setup.sh 生成）
├── start-all.sh          # 启动所有服务
├── stop-all.sh           # 停止所有服务
├── status-claw.sh        # 查看服务状态
├── health-check.sh       # 健康检查
├── start-mihomo.sh       # 启动 Mihomo
├── start-openclaw.sh     # 启动 OpenClaw
├── switch-model.sh       # 切换 AI 模型
├── switch-ollama-host.sh # 切换 Ollama 服务器
├── mihomo-sub.sh         # 管理代理订阅
└── README.md             # 本文件
```

## 快捷命令

配置完成后，可以使用以下快捷命令：

| 命令 | 功能 |
|------|------|
| `claw-up` | 启动所有服务 |
| `claw-down` | 停止所有服务 |
| `claw-restart` | 重启所有服务 |
| `claw-ps` | 查看服务状态 |
| `claw-check` | 健康检查 |
| `claw-log` | 查看 OpenClaw 实时日志 |
| `mih-log` | 查看 Mihomo 实时日志 |
| `claw-models` | 列出可用 AI 模型 |
| `claw-model <模型名>` | 切换 AI 模型 |
| `claw-host <地址>` | 切换 Ollama 服务器 |
| `mih-sub` | 管理代理订阅 |
| `test-proxy` | 测试代理连通性 |
| `test-ollama` | 测试 Ollama 连接 |

## 手动配置

如果你不想运行交互式脚本，可以手动编辑 `.env` 文件：

```bash
nano .env
```

关键配置项：
- `OLLAMA_HOST`: Ollama 服务器地址（默认: http://127.0.0.1:11434）
- `MIHOMO_HTTP_PORT`: HTTP 代理端口（默认: 7890）
- `DEFAULT_MODEL`: 默认 AI 模型

## 依赖要求

- curl
- python3
- nodejs (≥ 16)
- npm
- Mihomo 代理

如果缺少依赖，setup.sh 会提示自动安装。

## 故障排除

### 1. 代理连接失败

```bash
# 测试代理
test-proxy

# 查看 Mihomo 日志
mih-log
```

### 2. Ollama 连接失败

```bash
# 测试 Ollama
curl http://localhost:11434/api/tags

# 或
test-ollama
```

### 3. 服务无法启动

```bash
# 查看详细日志
tail -f ~/.local/log/openclaw.log
tail -f ~/.local/log/mihomo.log

# 健康检查
claw-check
```

## 迁移说明

从旧服务器迁移配置：

1. 在原服务器运行导出：
   ```bash
   ~/openclaw/export-migration.sh
   ```

2. 复制到新服务器并安装

3. 修改 `.env` 中的 Ollama 地址（如果不同）

## 许可证

MIT
