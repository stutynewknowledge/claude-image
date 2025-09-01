# Claude Relay Service Docker 部署手册

## 📋 概述

本手册提供了将 Claude Relay Service 打包为 Docker 镜像并部署的完整指南。支持外部 .env 文件配置，无需修改源码即可在不同环境中部署。

## 🚀 快速开始

### 1. 准备环境

**前置条件：Redis 容器已独立部署**
本部署方案假设您已经独立部署了名为 `redis-7` 的 Redis 容器。

```bash
# 复制环境文件模板
cp .env.docker .env

# 编辑环境文件，设置必需的配置
nano .env  # 或使用其他编辑器
```

**必须修改的配置项：**
- `JWT_SECRET`: 至少32字符的随机字符串
- `ENCRYPTION_KEY`: 32字符的加密密钥
- `ADMIN_PASSWORD`: 管理员密码

### 2. 构建并启动服务

```bash
# 赋予脚本执行权限
chmod +x scripts/docker-deploy.sh

# 初始化环境（自动生成密钥）
./scripts/docker-deploy.sh setup

# 构建 Docker 镜像
./scripts/docker-deploy.sh build

# 启动服务（会自动检查 redis-7 状态）
./scripts/docker-deploy.sh start -d
```

### 3. 访问服务

- 服务地址: http://localhost:3000
- 管理界面: http://localhost:3000/web
- 健康检查: http://localhost:3000/health

## 📁 文件结构

```
claude-image/
├── Dockerfile                   # Docker 镜像构建文件
├── .env.docker                 # 环境配置模板
├── scripts/
│   └── docker-deploy.sh        # 部署管理脚本
├── logs/                       # 日志文件目录（挂载）
└── data/                       # 数据文件目录（挂载）

注意：Redis 数据由独立的 redis-7 容器管理
```

## 🔧 部署脚本使用说明

### 基本命令

```bash
# 查看帮助
./scripts/docker-deploy.sh -h

# 初始化环境配置
./scripts/docker-deploy.sh setup

# 构建镜像
./scripts/docker-deploy.sh build

# 启动服务（前台）
./scripts/docker-deploy.sh start

# 启动服务（后台）
./scripts/docker-deploy.sh start -d

# 停止服务
./scripts/docker-deploy.sh stop

# 重启服务
./scripts/docker-deploy.sh restart

# 查看状态
./scripts/docker-deploy.sh status

# 查看日志
./scripts/docker-deploy.sh logs

# 跟踪日志
./scripts/docker-deploy.sh logs -f

# 清理所有资源
./scripts/docker-deploy.sh clean
```

### 高级选项

```bash
# 使用指定端口启动
./scripts/docker-deploy.sh start -p 8080

# 使用指定环境文件
./scripts/docker-deploy.sh start -e .env.production

# 不创建 Docker 网络（使用现有网络）
./scripts/docker-deploy.sh start --no-network

# 组合选项使用
./scripts/docker-deploy.sh start -p 8080 -e .env.prod -d --no-network
```

## 🔐 环境变量配置

### 必需配置

| 变量名 | 说明 | 示例值 |
|--------|------|--------|
| `JWT_SECRET` | JWT 密钥，至少32字符 | `your-random-32-plus-character-secret` |
| `ENCRYPTION_KEY` | 数据加密密钥，32字符 | `abcdefghijklmnopqrstuvwxyz123456` |

### 可选配置

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `PORT` | `3000` | 服务端口 |
| `ADMIN_USERNAME` | `admin` | 管理员用户名 |
| `ADMIN_PASSWORD` | - | 管理员密码 |
| `REDIS_HOST` | `redis-7` | Redis 主机地址 |
| `REDIS_PORT` | `6379` | Redis 端口 |
| `LOG_LEVEL` | `info` | 日志级别 |

### 生成安全密钥

```bash
# 生成 JWT_SECRET（至少32字符）
openssl rand -base64 32

# 生成 ENCRYPTION_KEY（32字符）
openssl rand -base64 32 | cut -c1-32

# 或使用部署脚本自动生成
./scripts/docker-deploy.sh setup
```

## 🐳 手动 Docker 操作

如果不使用部署脚本，也可以手动执行 Docker 命令：

### 前置条件：Redis 容器已存在

确保您已经有一个名为 `redis-7` 的 Redis 容器在运行：

```bash
# 检查 Redis 容器状态
docker ps | grep redis-7

# 如果 Redis 容器在同一网络中，可以跳过网络创建
```

### 1. 创建网络（可选）

只有在 Redis 容器不在同一网络中时才需要：

```bash
docker network create claude-relay-network

# 将现有的 redis-7 容器连接到网络
docker network connect claude-relay-network redis-7
```

### 2. 构建应用镜像

```bash
docker build -t claude-relay-service:latest .
```

### 3. 启动应用

```bash
docker run -d \
  --name claude-image \
  --network claude-relay-network \
  --restart unless-stopped \
  --env-file .env \
  -p 3000:3000 \
  -v ./logs:/app/logs \
  -v ./data:/app/data \
  -e REDIS_HOST=redis-7 \
  claude-relay-service:latest
```

## 📊 生产环境部署

### 推荐配置

```bash
# .env 文件示例（生产环境）
NODE_ENV=production
PORT=3000
LOG_LEVEL=warn

# 安全配置
JWT_SECRET=your-super-secure-random-jwt-secret-key-here
ENCRYPTION_KEY=your-32-character-encryption-key

# Redis 配置（如使用外部 Redis）
REDIS_HOST=your-redis-server.com
REDIS_PORT=6379
REDIS_PASSWORD=your-redis-password
REDIS_DB=0
REDIS_ENABLE_TLS=true

# 代理配置（如需要）
DEFAULT_PROXY_TIMEOUT=30000
MAX_PROXY_RETRIES=2
```

### 性能优化

1. **资源限制**：
```bash
# 启动时添加资源限制
docker run -d \
  --name claude-image \
  --memory=512m \
  --cpus=1.0 \
  # ... 其他参数
```

2. **日志轮转**：
```bash
# 环境变量配置
LOG_MAX_SIZE=50m
LOG_MAX_FILES=10
```

3. **健康检查**：
```bash
# 容器已内置健康检查
# 查看健康状态
docker ps  # STATUS 列显示健康状态
```

## 🔍 故障排查

### 常见问题

1. **容器启动失败**
```bash
# 查看容器日志
docker logs claude-image

# 检查环境文件
cat .env | grep -E "(JWT_SECRET|ENCRYPTION_KEY)"
```

2. **Redis 连接失败**
```bash
# 检查 Redis 容器状态
docker ps | grep redis-7

# 测试 Redis 连接
docker exec redis-7 redis-cli ping

# 检查 Redis 容器网络连接
docker network inspect claude-relay-network
```

3. **端口被占用**
```bash
# 检查端口占用
netstat -tlnp | grep 3000

# 使用其他端口启动
./scripts/docker-deploy.sh start -p 8080
```

### 调试模式

```bash
# 启用详细日志
echo "LOG_LEVEL=debug" >> .env

# 重启服务
./scripts/docker-deploy.sh restart

# 查看详细日志
./scripts/docker-deploy.sh logs -f
```

## 🔄 更新和维护

### 更新应用

```bash
# 拉取最新代码
git pull

# 重新构建镜像
./scripts/docker-deploy.sh build

# 重启服务
./scripts/docker-deploy.sh restart
```

### 数据备份

```bash
# 备份 Redis 数据（Redis 为独立管理）
docker exec redis-7 redis-cli BGSAVE

# 备份应用数据
tar -czf backup-$(date +%Y%m%d).tar.gz data/ logs/

# 注意：Redis 数据由 redis-7 容器独立管理，请单独备份
```

### 清理和重置

```bash
# 停止所有服务
./scripts/docker-deploy.sh stop

# 完全清理
./scripts/docker-deploy.sh clean

# 重新初始化
./scripts/docker-deploy.sh setup
./scripts/docker-deploy.sh build
./scripts/docker-deploy.sh start
```

## 🛡️ 安全建议

1. **环境文件权限**：
```bash
chmod 600 .env
```

2. **防火墙配置**：
```bash
# 只允许必要端口访问
ufw allow 3000/tcp
```

3. **定期更新**：
- 定期更新 Docker 镜像
- 更新系统安全补丁
- 轮换密钥和密码

4. **监控和日志**：
- 监控容器健康状态
- 定期检查日志异常
- 设置资源使用警报

## 📞 支持

如遇问题，请检查：
1. Docker 和操作系统日志
2. 应用容器日志：`./scripts/docker-deploy.sh logs`
3. 环境配置是否正确
4. 网络和端口配置

更多技术支持请参考项目文档或提交 Issue。