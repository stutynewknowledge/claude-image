#!/bin/bash

# Claude Relay Service Docker 部署脚本
# 使用外部 .env 文件进行配置

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE_NAME="claude-relay-service"
CONTAINER_NAME="claude-image"
# REDIS_CONTAINER_NAME="redis-7"  # Redis 已独立部署，不需要脚本管理
NETWORK_NAME="claude-relay-network"

# 默认配置
DEFAULT_PORT=3000
DEFAULT_ENV_FILE="$PROJECT_ROOT/.env"

# 显示使用帮助
show_help() {
    echo -e "${BLUE}Claude Relay Service Docker 部署脚本${NC}"
    echo ""
    echo "用法: $0 [选项] [命令]"
    echo ""
    echo "命令:"
    echo "  build       构建 Docker 镜像"
    echo "  start       启动服务（默认）"
    echo "  stop        停止服务"
    echo "  restart     重启服务"
    echo "  status      查看服务状态"
    echo "  logs        查看服务日志"
    echo "  clean       清理容器和镜像"
    echo "  setup       初始化环境配置"
    echo ""
    echo "选项:"
    echo "  -p, --port PORT     指定端口 (默认: $DEFAULT_PORT)"
    echo "  -e, --env-file FILE 指定环境文件 (默认: $DEFAULT_ENV_FILE)"
    echo "  -n, --no-network    不创建 Docker 网络（使用现有网络）"
    echo "  -d, --detach        后台运行"
    echo "  -h, --help          显示帮助"
    echo ""
    echo "示例:"
    echo "  $0 build                           # 构建镜像"
    echo "  $0 start -p 8080 -e .env.prod      # 使用指定端口和环境文件启动"
    echo "  $0 start --no-network               # 启动但不创建 Docker 网络"
    echo "  $0 logs -f                         # 跟踪日志输出"
}

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查依赖
check_dependencies() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker 未安装或不在 PATH 中"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker 服务未运行或权限不足"
        exit 1
    fi
}

# 检查环境文件
check_env_file() {
    if [ ! -f "$ENV_FILE" ]; then
        log_error "环境文件不存在: $ENV_FILE"
        echo "请运行 '$0 setup' 创建环境文件"
        exit 1
    fi
    
    # 检查必需的环境变量
    local required_vars=("JWT_SECRET" "ENCRYPTION_KEY")
    local missing_vars=()
    
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        
        var_name=$(echo "$line" | cut -d'=' -f1)
        for required in "${required_vars[@]}"; do
            if [[ "$var_name" == "$required" ]]; then
                var_value=$(echo "$line" | cut -d'=' -f2- | sed 's/^["'"'"']//;s/["'"'"']$//')
                if [[ -z "$var_value" ]]; then
                    missing_vars+=("$required")
                fi
            fi
        done
    done < "$ENV_FILE"
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "环境文件中缺少必需的变量: ${missing_vars[*]}"
        echo "请运行 '$0 setup' 生成完整的环境配置"
        exit 1
    fi
}

# 创建 Docker 网络
create_network() {
    if [ "$NO_NETWORK" = true ]; then
        log_info "跳过 Docker 网络创建"
        return
    fi
    
    if ! docker network ls | grep -q "$NETWORK_NAME"; then
        log_info "创建 Docker 网络: $NETWORK_NAME"
        docker network create "$NETWORK_NAME"
    else
        log_info "Docker 网络 $NETWORK_NAME 已存在"
    fi
}

# 检查 Redis 连接
check_redis() {
    log_info "检查 Redis 连接状态"
    if docker ps | grep -q "redis-7"; then
        log_info "Redis 容器 redis-7 运行正常"
    else
        log_warn "Redis 容器 redis-7 未运行，请确保 Redis 服务可用"
    fi
}

# 构建 Docker 镜像
build_image() {
    log_info "构建 Docker 镜像: $IMAGE_NAME"
    cd "$PROJECT_ROOT"
    
    docker build \
        --tag "$IMAGE_NAME:latest" \
        --build-arg NODE_ENV=production \
        .
    
    log_info "镜像构建完成"
}

# 启动应用容器
start_app() {
    if docker ps | grep -q "$CONTAINER_NAME"; then
        log_warn "应用容器已在运行"
        return
    fi
    
    if docker ps -a | grep -q "$CONTAINER_NAME"; then
        log_info "启动现有应用容器"
        docker start "$CONTAINER_NAME"
    else
        log_info "创建并启动应用容器"
        
        # 构建 docker run 命令
        local docker_args=(
            "run"
        )
        
        if [ "$DETACH" = true ]; then
            docker_args+=("-d")
        else
            docker_args+=("-it")
        fi
        
        docker_args+=(
            "--name" "$CONTAINER_NAME"
            "--network" "$NETWORK_NAME"
            "--restart" "unless-stopped"
            "--env-file" "$ENV_FILE"
            "-p" "$PORT:3000"
            "-v" "$PROJECT_ROOT/logs:/app/logs"
            "-v" "$PROJECT_ROOT/data:/app/data"
        )
        
        # Redis 主机设置（使用独立的 redis-7 容器）
        docker_args+=("-e" "REDIS_HOST=redis-7")
        
        docker_args+=("$IMAGE_NAME:latest")
        
        docker "${docker_args[@]}"
    fi
}

# 停止服务
stop_service() {
    log_info "停止应用服务"
    
    if docker ps | grep -q "$CONTAINER_NAME"; then
        docker stop "$CONTAINER_NAME"
        log_info "应用容器已停止"
    else
        log_warn "应用容器未运行"
    fi
    
    log_info "注意：Redis 容器 redis-7 为独立部署，不会被此脚本停止"
}

# 重启服务
restart_service() {
    log_info "重启服务"
    stop_service
    start_service
}

# 启动服务
start_service() {
    log_info "启动 Claude Relay Service"
    create_network
    check_redis
    start_app
    
    if [ "$DETACH" != true ]; then
        log_info "服务正在前台运行，按 Ctrl+C 停止"
    else
        log_info "服务已在后台启动"
        log_info "访问地址: http://localhost:$PORT"
        log_info "查看日志: $0 logs"
        log_info "查看状态: $0 status"
    fi
}

# 查看服务状态
show_status() {
    echo -e "${BLUE}=== 服务状态 ===${NC}"
    
    echo -e "\n${YELLOW}Docker 网络:${NC}"
    if docker network ls | grep -q "$NETWORK_NAME"; then
        echo "✅ $NETWORK_NAME (已创建)"
    else
        echo "❌ $NETWORK_NAME (未创建)"
    fi
    
    echo -e "\n${YELLOW}Redis 容器 (独立部署):${NC}"
    if docker ps | grep -q "redis-7"; then
        echo "✅ redis-7 (运行中，独立管理)"
    elif docker ps -a | grep -q "redis-7"; then
        echo "⏸️  redis-7 (已停止，请手动启动)"
    else
        echo "❌ redis-7 (未找到，请确保 Redis 容器已部署)"
    fi
    
    echo -e "\n${YELLOW}应用容器:${NC}"
    if docker ps | grep -q "$CONTAINER_NAME"; then
        echo "✅ $CONTAINER_NAME (运行中)"
        echo "   端口映射: $PORT -> 3000"
        echo "   访问地址: http://localhost:$PORT"
    elif docker ps -a | grep -q "$CONTAINER_NAME"; then
        echo "⏸️  $CONTAINER_NAME (已停止)"
    else
        echo "❌ $CONTAINER_NAME (未创建)"
    fi
    
    echo -e "\n${YELLOW}环境配置:${NC}"
    echo "   环境文件: $ENV_FILE"
    if [ -f "$ENV_FILE" ]; then
        echo "   配置状态: ✅ 存在"
    else
        echo "   配置状态: ❌ 不存在"
    fi
}

# 查看日志
show_logs() {
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        log_error "应用容器未运行"
        exit 1
    fi
    
    local follow_flag=""
    if [[ "$*" == *"-f"* ]] || [[ "$*" == *"--follow"* ]]; then
        follow_flag="-f"
    fi
    
    docker logs $follow_flag "$CONTAINER_NAME"
}

# 清理资源
clean_resources() {
    log_info "清理应用 Docker 资源"
    
    # 停止并删除应用容器
    if docker ps -a | grep -q "$CONTAINER_NAME"; then
        docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
        log_info "已删除应用容器: $CONTAINER_NAME"
    fi
    
    log_warn "注意：Redis 容器 redis-7 为独立部署，不会被清理"
    
    # 删除镜像
    if docker images | grep -q "$IMAGE_NAME"; then
        docker rmi "$IMAGE_NAME:latest" 2>/dev/null || true
        log_info "已删除镜像: $IMAGE_NAME"
    fi
    
    # 删除网络
    if docker network ls | grep -q "$NETWORK_NAME"; then
        docker network rm "$NETWORK_NAME" 2>/dev/null || true
        log_info "已删除网络: $NETWORK_NAME"
    fi
    
    log_info "清理完成"
}

# 初始化环境配置
setup_environment() {
    log_info "初始化环境配置"
    
    # 创建环境文件
    if [ ! -f "$ENV_FILE" ]; then
        log_info "创建环境文件: $ENV_FILE"
        cat > "$ENV_FILE" << 'EOF'
# Claude Relay Service 环境配置
# 生成时间: $(date)

# 🔐 安全配置（必需）
JWT_SECRET=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -base64 32 | cut -c1-32)

# 👤 管理员凭据（可选，留空则使用默认）
ADMIN_USERNAME=
ADMIN_PASSWORD=

# 📊 Redis 配置
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0

# 🎯 Claude API 配置
CLAUDE_API_URL=https://api.anthropic.com/v1/messages
CLAUDE_API_VERSION=2023-06-01

# 📈 使用限制
DEFAULT_TOKEN_LIMIT=1000000

# 📝 日志配置
LOG_LEVEL=info

# 🔧 系统配置
NODE_ENV=production
PORT=3000
EOF
        
        # 替换变量
        JWT_SECRET=$(openssl rand -base64 32)
        ENCRYPTION_KEY=$(openssl rand -base64 32 | cut -c1-32)
        sed -i.bak "s/\$(openssl rand -base64 32)/$JWT_SECRET/g" "$ENV_FILE"
        sed -i.bak "s/\$(openssl rand -base64 32 | cut -c1-32)/$ENCRYPTION_KEY/g" "$ENV_FILE"
        sed -i.bak "s/\$(date)/$(date)/g" "$ENV_FILE"
        rm "$ENV_FILE.bak" 2>/dev/null || true
        
        log_info "环境文件创建完成"
    else
        log_warn "环境文件已存在: $ENV_FILE"
    fi
    
    # 创建必要的目录
    mkdir -p "$PROJECT_ROOT/logs"
    mkdir -p "$PROJECT_ROOT/data"
    
    log_info "目录结构创建完成"
    echo ""
    echo -e "${GREEN}初始化完成！${NC}"
    echo "请编辑环境文件进行自定义配置: $ENV_FILE"
    echo "然后运行: $0 build && $0 start"
}

# 解析命令行参数
PORT="$DEFAULT_PORT"
ENV_FILE="$DEFAULT_ENV_FILE"
NO_NETWORK=false
DETACH=false
COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -e|--env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        -n|--no-network)
            NO_NETWORK=true
            shift
            ;;
        -d|--detach)
            DETACH=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--follow)
            # 用于 logs 命令
            shift
            ;;
        build|start|stop|restart|status|logs|clean|setup)
            COMMAND="$1"
            shift
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 默认命令
if [ -z "$COMMAND" ]; then
    COMMAND="start"
fi

# 主逻辑
check_dependencies

case $COMMAND in
    build)
        build_image
        ;;
    start)
        if [ "$COMMAND" = "start" ]; then
            check_env_file
        fi
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        check_env_file
        restart_service
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs "$@"
        ;;
    clean)
        clean_resources
        ;;
    setup)
        setup_environment
        ;;
    *)
        log_error "未知命令: $COMMAND"
        show_help
        exit 1
        ;;
esac