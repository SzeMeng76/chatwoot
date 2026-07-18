# Chatwoot Docker 部署指南

## 部署架构

本项目使用 GitHub Actions 自动构建 Docker 镜像，支持 AMD64 和 ARM64 架构，镜像推送到：
- GitHub Container Registry (GHCR): `ghcr.io/szemeng76/chatwoot`

## 快速开始

### 1. 配置 GitHub 权限

GitHub Actions 会自动使用 `GITHUB_TOKEN` 推送镜像到 GHCR，**不需要额外配置 Secrets**。

只需确保：
1. 仓库设置 > Actions > General > Workflow permissions 设为 "Read and write permissions"
2. 仓库设置 > Packages > 确保包可见性设置正确（public 或 private）

### 2. 触发镜像构建

镜像会在以下情况自动构建：
- 推送代码到 `main`、`master` 或 `develop` 分支
- 创建新的版本标签（格式：`v*.*.*`，如 `v1.0.0`）
- 手动触发工作流（在 GitHub Actions 页面）

**标签规则：**
- 推送到分支：镜像标签为分支名（如 `main`）
- 创建版本标签：镜像标签为 `latest` 和版本号（如 `latest` 和 `1.0.0`）

### 3. 准备环境变量

复制并修改环境变量文件：

```bash
cp .env.example .env.production
```

编辑 `.env.production`，配置以下**必需**参数：

```bash
# === 必需配置 ===

# 密钥（使用 openssl rand -hex 64 生成）
SECRET_KEY_BASE=你的64位十六进制密钥

# 前端 URL（替换为你的域名）
FRONTEND_URL=https://chat.yourdomain.com

# 数据库配置
POSTGRES_HOST=postgres
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=你的强密码
POSTGRES_DATABASE=chatwoot

# Redis 配置
REDIS_URL=redis://redis:6379
REDIS_PASSWORD=你的Redis密码

# 邮件发送者
MAILER_SENDER_EMAIL=Chatwoot <noreply@yourdomain.com>

# SMTP 配置（如果使用 SMTP）
SMTP_ADDRESS=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_AUTHENTICATION=plain
SMTP_ENABLE_STARTTLS_AUTO=true

# === 可选配置 ===

# 禁用新用户注册（建议生产环境设为 false）
ENABLE_ACCOUNT_SIGNUP=false

# 强制 SSL（生产环境建议设为 true）
FORCE_SSL=true

# 时区
TZ=Asia/Shanghai

# Active Record 加密（用于 MFA/2FA，运行 rails db:encryption:init 生成）
# ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=
# ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=
# ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=
```

### 4. 登录 GitHub Container Registry

如果镜像是私有的，需要先登录：

```bash
# 生成 GitHub Personal Access Token（Settings > Developer settings > Personal access tokens > Tokens (classic)）
# 权限需要：read:packages
echo YOUR_GITHUB_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

如果镜像是公开的，可以跳过此步骤。

### 5. 部署应用

```bash
# 拉取最新镜像
docker compose -f docker-compose.deploy.yaml pull

# 启动服务
docker compose -f docker-compose.deploy.yaml --env-file .env.production up -d

# 查看日志
docker compose -f docker-compose.deploy.yaml logs -f

# 初始化数据库（首次部署）
docker compose -f docker-compose.deploy.yaml exec rails bundle exec rails db:chatwoot_prepare
```

### 6. 访问应用

打开浏览器访问 `http://your-server-ip:3000`（或你配置的域名）。

首次访问会引导你创建管理员账户。

## 服务说明

- **rails**: Chatwoot 主应用（Web 服务器，监听端口 3000）
- **sidekiq**: 后台任务处理器（邮件发送、通知等）
- **postgres**: PostgreSQL 数据库（监听端口 5432，带 pgvector 扩展，用于 AI 功能）
- **redis**: Redis 缓存和消息队列（监听端口 6379）

**网络模式**: 使用 `host` 网络模式，所有服务直接绑定到宿主机端口。

**防火墙配置**:
```bash
# 必需：允许 Web 访问
sudo ufw allow 3000/tcp

# 可选：仅在需要外部访问数据库时开放（不推荐）
# sudo ufw allow 5432/tcp
# sudo ufw allow 6379/tcp
```

## 常用命令

```bash
# 停止服务
docker compose -f docker-compose.deploy.yaml down

# 重启服务
docker compose -f docker-compose.deploy.yaml restart

# 更新到最新镜像
docker compose -f docker-compose.deploy.yaml pull
docker compose -f docker-compose.deploy.yaml up -d

# 查看特定服务日志
docker compose -f docker-compose.deploy.yaml logs -f rails
docker compose -f docker-compose.deploy.yaml logs -f sidekiq

# 进入 Rails 容器
docker compose -f docker-compose.deploy.yaml exec rails sh

# 执行数据库迁移
docker compose -f docker-compose.deploy.yaml exec rails bundle exec rails db:migrate

# 创建管理员账户（通过控制台）
docker compose -f docker-compose.deploy.yaml exec rails bundle exec rails console
# 在控制台中运行：
# user = User.create!(email: 'admin@example.com', password: 'Password123!', name: 'Admin')
# Account.create!(name: 'Acme Inc')
```

## 数据备份

### 备份数据库

```bash
docker compose -f docker-compose.deploy.yaml exec postgres pg_dump -U postgres chatwoot > backup_$(date +%Y%m%d_%H%M%S).sql
```

### 恢复数据库

```bash
cat backup_file.sql | docker compose -f docker-compose.deploy.yaml exec -T postgres psql -U postgres chatwoot
```

### 备份文件存储

```bash
docker run --rm -v chatwoot_storage_data:/data -v $(pwd):/backup alpine tar czf /backup/storage_backup_$(date +%Y%m%d_%H%M%S).tar.gz -C /data .
```

## Nginx 反向代理配置示例

如果需要使用域名和 SSL，可以配置 Nginx：

```nginx
server {
    listen 80;
    server_name chat.yourdomain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name chat.yourdomain.com;

    ssl_certificate /path/to/ssl/fullchain.pem;
    ssl_certificate_key /path/to/ssl/privkey.pem;

    client_max_body_size 50M;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
    }
}
```

## 故障排查

### 检查服务状态

```bash
docker compose -f docker-compose.deploy.yaml ps
```

### Rails 应用无法启动

1. 检查日志：`docker compose -f docker-compose.deploy.yaml logs rails`
2. 确认环境变量是否正确设置
3. 确认数据库连接是否正常

### Sidekiq 任务不执行

1. 检查 Sidekiq 日志：`docker compose -f docker-compose.deploy.yaml logs sidekiq`
2. 确认 Redis 连接是否正常
3. 检查 `REDIS_PASSWORD` 是否与 Redis 配置一致

### 数据库连接失败

1. 检查 `POSTGRES_PASSWORD` 是否正确
2. 确认 postgres 容器正在运行
3. 检查网络连接：`docker compose -f docker-compose.deploy.yaml exec rails ping postgres`

## 生产环境建议

1. **使用强密码**：为 `SECRET_KEY_BASE`、`POSTGRES_PASSWORD`、`REDIS_PASSWORD` 设置强密码
2. **启用 SSL**：设置 `FORCE_SSL=true` 并配置 Nginx/Caddy 反向代理
3. **禁用注册**：设置 `ENABLE_ACCOUNT_SIGNUP=false`
4. **定期备份**：配置自动备份数据库和文件存储
5. **监控日志**：使用日志聚合工具监控应用日志
6. **资源限制**：在 docker-compose 中配置内存和 CPU 限制
7. **外部数据库**：生产环境建议使用托管的 PostgreSQL 和 Redis 服务

## 配置文件说明

- `docker-compose.deploy.yaml`: 生产环境部署配置
- `.env.production`: 生产环境变量（不要提交到 Git）
- `.github/workflows/docker-publish.yml`: GitHub Actions 自动构建配置

## 更多信息

- Chatwoot 官方文档: https://www.chatwoot.com/docs
- 环境变量完整列表: https://www.chatwoot.com/docs/self-hosted/configuration/environment-variables
