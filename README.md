# OpenClaw 快速部署包

用于在新服务器上快速部署 Mihomo(VPN) + OpenClaw 环境, 支持 Ollama、vLLM 和 API 模型（如 Moonshot/Kimi）。

## 特性

- ✅ **多模型后端支持** - 支持 Ollama、vLLM 和 API 三种模型来源
- ✅ **自动路径识别** - 脚本自动检测 openclaw 安装路径，无需手动修改
- ✅ **多环境兼容** - 支持 Ubuntu/Debian/CentOS 等多种 Linux 发行版
- ✅ **一键部署** - 交互式配置，快速完成环境搭建
- ✅ **代理支持** - 内置 Mihomo 代理配置，支持 Telegram API 访问

## 支持的模型后端

| 后端 | 适用场景 | 配置方式 |
|------|----------|----------|
| **Ollama** | 本地/远程部署，易用性强 | 选择选项 1 |
| **vLLM** | 高性能推理，生产环境 | 选择选项 2 |
| **API** | 使用第三方服务（Moonshot/Kimi等） | 选择选项 3 |

### Ollama vs vLLM

- **Ollama**: 简单易用，适合个人开发和测试，支持一键下载模型
- **vLLM**: 高性能推理引擎，支持并发请求，适合生产环境和高负载场景

## 快速开始

### 0. 准备工作

安装 OpenClaw（如果尚未安装）：

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

参考官网教程: <https://docs.openclaw.ai/start/getting-started>

### 1. 下载部署包

```bash
git clone https://github.com/MakerG9527/openclaw-deploy.git openclaw
cd openclaw
```

### 2. 运行交互式配置

```bash
./setup.sh
```

脚本会引导你完成：
- 检测系统环境
- **选择模型后端**：Ollama / vLLM / API
- 配置 Mihomo 代理端口
- 生成 .env 环境变量文件
- 添加 Shell 快捷命令到 ~/.bashrc

**如果选择 vLLM：**
- 输入 vLLM 服务器地址（默认: 127.0.0.1:8000）
- 脚本会测试连接并获取可用模型
- 可选择配置 API 密钥（如果 vLLM 启用了认证）

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

**注意：** vLLM 需要单独启动，不在 start-all.sh 中管理

### 6. 验证部署

```bash
claw-check
```

## 启动 vLLM 服务

如果你选择了 vLLM 作为模型后端，需要手动启动 vLLM 服务：

```bash
# 基础启动（单卡）
python -m vllm.entrypoints.openai.api_server \
  --model Qwen/Qwen2.5-7B-Instruct \
  --port 8000

# 多卡并行启动
python -m vllm.entrypoints.openai.api_server \
  --model Qwen/Qwen2.5-7B-Instruct \
  --port 8000 \
  --tensor-parallel-size 2

# 指定显存比例
python -m vllm.entrypoints.openai.api_server \
  --model Qwen/Qwen2.5-7B-Instruct \
  --port 8000 \
  --gpu-memory-utilization 0.9
```

更多参数请参考 [vLLM 文档](https://docs.vllm.ai/en/latest/)

## 目录结构

```
.
├── setup.sh              # 交互式配置脚本（主入口）⭐
├── install-mihomo.sh     # Mihomo 安装脚本
├── common.sh             # 公共函数库
├── .env                  # 环境变量配置（setup.sh 生成）
├── proxy-bootstrap.mjs   # Node.js 代理引导模块（自动检测路径）
├── start-all.sh          # 启动所有服务
├── stop-all.sh           # 停止所有服务
├── status-claw.sh        # 查看服务状态
├── health-check.sh       # 健康检查
├── start-mihomo.sh       # 启动 Mihomo
├── start-openclaw.sh     # 启动 OpenClaw（自动识别路径）
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
| `test-vllm` | 测试 vLLM 连接 |
| `mih-sub` | 管理代理订阅 |
| `test-proxy` | 测试代理连通性 |
| `test-ollama` | 测试 Ollama 连接 |

## 自动路径识别

本项目已优化为支持**任意服务器部署**：

- `start-openclaw.sh` 自动检测 `openclaw` 命令位置（支持 `~/.npm-global/bin`、`/usr/local/bin` 等）
- `proxy-bootstrap.mjs` 自动查找 `undici` 模块路径（通过 `npm root -g` 和多路径尝试）
- 无需手动修改任何硬编码路径

## 手动配置

如果你不想运行交互式脚本，可以手动编辑 `.env` 文件：

```bash
nano .env
```

关键配置项：
- `MIHOMO_HTTP_PORT`: HTTP 代理端口（默认: 7890）
- `DEFAULT_MODEL`: 默认 AI 模型（如 `moonshot/kimi-k2.5`、`vllm/Qwen2.5-7B-Instruct`）
- `VLLM_HOST`: vLLM 服务器地址（如 `http://127.0.0.1:8000`）
- `VLLM_API_KEY`: vLLM API 密钥（可选）

## 依赖要求

- curl
- python3
- nodejs (≥ 16)
- npm
- git

如果缺少依赖，setup.sh 会提示自动安装。

## 故障排除

### 1. 代理连接失败

```bash
# 测试代理
test-proxy

# 查看 Mihomo 日志
mih-log
```

### 2. vLLM 连接失败

```bash
# 测试 vLLM
test-vllm

# 直接测试
curl http://127.0.0.1:8000/v1/models

# 检查 vLLM 是否运行
ps aux | grep vllm
```

### 3. Telegram API 连接失败

```bash
# 检查 Mihomo 是否运行
claw-ps

# 检查代理端口
ss -tlnp | grep 7890
```

### 4. 服务无法启动

```bash
# 查看详细日志
tail -f ~/.local/log/openclaw.log
tail -f ~/.local/log/mihomo.log

# 健康检查
claw-check
```

### 5. 路径自动识别失败

如果自动检测失败，可以手动设置：

```bash
# 查找 openclaw 路径
which openclaw
# 或
npm root -g

# 然后编辑脚本中的路径变量
nano start-openclaw.sh
```

## 许可证

MIT
