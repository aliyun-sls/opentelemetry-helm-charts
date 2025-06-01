#!/bin/bash
# ===================================================================
# OpenTelemetry Demo 部署脚本 (Linux 版本)
# ===================================================================

set -e

# 配置变量
ACR_REGISTRY=${ACR_REGISTRY:-"o11y-demo-registry-vpc.cn-hongkong.cr.aliyuncs.com"}
ACR_NAMESPACE=${ACR_NAMESPACE:-"o11y-demo"}
CHART_VERSION=${CHART_VERSION:-"0.37.2"}
K8S_NAMESPACE=${K8S_NAMESPACE:-"opentelemetry-demo"}
RELEASE_NAME=${RELEASE_NAME:-"my-otel-demo"}

# ACR 凭据 (可选的环境变量)
ACR_USERNAME=${ACR_USERNAME:-"uname"}
ACR_PASSWORD=${ACR_PASSWORD:-"pword"}

CHART_NAME="opentelemetry-demo"
CHART_PATH="charts/$CHART_NAME"
VALUES_FILE="$CHART_PATH/values.yaml"
OUTPUT_DIR="./helm-packages"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 显示帮助信息
show_help() {
    echo -e "${MAGENTA}🚀 OpenTelemetry Demo ACR 部署工具${NC}"
    echo ""
    echo -e "${CYAN}用法:${NC}"
    echo "  $0 [ACTION] [OPTIONS]"
    echo ""
    echo -e "${CYAN}可用操作:${NC}"
    echo "  prepare         准备阶段：创建命名空间和 ACR Secret"
    echo "  test-local      本地测试：验证 chart 配置"
    echo "  package         打包阶段：生成 helm chart 包"
    echo "  push-to-acr     推送阶段：推送到阿里云 ACR"
    echo "  install-local   本地安装：从本地 chart 安装"
    echo "  install-acr     ACR 安装：从 ACR 仓库安装"
    echo "  show-commands   显示手动 helm install 命令"
    echo "  full-deploy     完整流程：执行所有步骤"
    echo "  uninstall       卸载已部署的应用"
    echo "  clean           清理生成的文件"
    echo "  force-login     强制重新登录到 ACR"
    echo ""
    echo -e "${CYAN}环境变量配置:${NC}"
    echo "  ACR_REGISTRY     = $ACR_REGISTRY"
    echo "  ACR_NAMESPACE    = $ACR_NAMESPACE"
    echo "  CHART_VERSION    = $CHART_VERSION"
    echo "  K8S_NAMESPACE    = $K8S_NAMESPACE"
    echo "  RELEASE_NAME     = $RELEASE_NAME"
    if [ -n "$ACR_USERNAME" ]; then
        echo -e "  ACR_USERNAME     = $ACR_USERNAME ${GREEN}(已设置)${NC}"
    else
        echo -e "  ACR_USERNAME     = ${RED}(未设置，将使用交互输入)${NC}"
    fi
    if [ -n "$ACR_PASSWORD" ]; then
        echo -e "  ACR_PASSWORD     = ${GREEN}(已设置)${NC}"
    else
        echo -e "  ACR_PASSWORD     = ${RED}(未设置，将使用交互输入)${NC}"
    fi
    echo ""
    echo -e "${CYAN}使用示例:${NC}"
    echo "  $0 prepare"
    echo "  RELEASE_NAME=prod-demo $0 install-local"
    echo "  $0 full-deploy"
    echo ""
    echo -e "${CYAN}自动化部署 (无交互):${NC}"
    echo "  ACR_USERNAME=user ACR_PASSWORD=pass $0 full-deploy"
}

# 获取 ACR 凭据
get_acr_credentials() {
    if [ -z "$ACR_USERNAME" ] || [ -z "$ACR_PASSWORD" ]; then
        echo -e "${YELLOW}请输入您的 ACR 凭据:${NC}"
        
        if [ -z "$ACR_USERNAME" ]; then
            read -p "ACR 用户名: " ACR_USERNAME_INPUT
        else
            ACR_USERNAME_INPUT="$ACR_USERNAME"
            echo -e "ACR 用户名: $ACR_USERNAME_INPUT ${GREEN}(来自环境变量)${NC}"
        fi
        
        if [ -z "$ACR_PASSWORD" ]; then
            read -s -p "ACR 密码: " ACR_PASSWORD_INPUT
            echo ""
        else
            ACR_PASSWORD_INPUT="$ACR_PASSWORD"
            echo -e "ACR 密码: ${GREEN}(来自环境变量)${NC}"
        fi
    else
        ACR_USERNAME_INPUT="$ACR_USERNAME"
        ACR_PASSWORD_INPUT="$ACR_PASSWORD"
        echo -e "${GREEN}使用环境变量中的 ACR 凭据${NC}"
    fi
}

# 检查是否已经登录到 ACR
check_acr_login() {
    # 简单而可靠的方法：尝试列出 registry 的内容
    # 如果成功，说明已登录；如果失败，说明未登录或登录过期
    
    echo -e "${CYAN}正在验证 ACR 登录状态...${NC}"
    
    # 尝试一个轻量级的操作来验证登录状态
    # 使用 helm registry login 的 --help 不会真正登录，所以我们用一个实际的验证方法
    
    # 方法：尝试 helm pull 一个可能不存在的 chart，但只检查认证是否通过
    local test_result
    test_result=$(helm pull oci://$ACR_REGISTRY/$ACR_NAMESPACE/non-existent-chart --version 999.999.999 2>&1 || true)
    
    # 如果错误信息包含 "authentication required" 或 "unauthorized"，说明未登录
    if echo "$test_result" | grep -iE "(authentication required|unauthorized|login|credentials)" >/dev/null 2>&1; then
        return 1  # 未登录
    fi
    
    # 如果错误信息是关于 chart 不存在或版本不存在，说明认证是成功的
    if echo "$test_result" | grep -iE "(not found|does not exist|no such)" >/dev/null 2>&1; then
        return 0  # 已登录
    fi
    
    # 检查配置文件作为备用方法
    local config_file="$HOME/.config/helm/registry/config.json"
    if [ ! -f "$config_file" ]; then
        config_file="$HOME/.docker/config.json"
    fi
    
    if [ -f "$config_file" ] && grep -q "$ACR_REGISTRY" "$config_file" 2>/dev/null; then
        return 0  # 已登录
    fi
    
    return 1  # 未登录
}

# 强制重新登录 ACR (可选功能)
force_acr_login() {
    echo -e "${YELLOW}强制重新登录到 ACR...${NC}"
    
    # 先登出（如果已登录）
    helm registry logout $ACR_REGISTRY 2>/dev/null || true
    
    # 获取凭据并登录
    get_acr_credentials
    echo "$ACR_PASSWORD_INPUT" | helm registry login $ACR_REGISTRY --username $ACR_USERNAME_INPUT --password-stdin
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ ACR 强制重新登录成功${NC}"
    else
        echo -e "${RED}❌ ACR 强制重新登录失败${NC}"
        exit 1
    fi
}

# 准备阶段
prepare() {
    echo -e "${MAGENTA}🎯 Step 1: 准备阶段 - 创建 ACR Secret${NC}"
    echo -e "${GREEN}创建 K8s 命名空间...${NC}"
    kubectl create namespace $K8S_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    echo -e "${GREEN}创建 ACR 镜像拉取 Secret...${NC}"
    get_acr_credentials
    
    kubectl create secret docker-registry acr-secret \
        --docker-server=$ACR_REGISTRY \
        --docker-username=$ACR_USERNAME_INPUT \
        --docker-password=$ACR_PASSWORD_INPUT \
        --docker-email=demo@example.com \
        --namespace=$K8S_NAMESPACE \
        --dry-run=client -o yaml | kubectl apply -f -
        
    echo -e "${GREEN}✅ ACR Secret 创建成功${NC}"
}

# 本地测试
test_local() {
    echo -e "${MAGENTA}🎯 Step 2: 本地测试阶段${NC}"
    
    if ! command -v helm &> /dev/null; then
        echo -e "${RED}❌ Helm 未安装，请先安装 Helm${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Helm 版本: $(helm version --short)${NC}"
    
    echo -e "${GREEN}添加必要的 Helm 仓库...${NC}"
    helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts || true
    helm repo add jaegertracing https://jaegertracing.github.io/helm-charts || true
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
    helm repo add grafana https://grafana.github.io/helm-charts || true
    helm repo add opensearch https://opensearch-project.github.io/helm-charts || true
    echo -e "${GREEN}更新 Helm 仓库...${NC}"
    helm repo update
    echo -e "${GREEN}✅ Helm 仓库配置完成${NC}"
    
    echo -e "${GREEN}构建 Chart 依赖...${NC}"
    cd $CHART_PATH && helm dependency build && cd ../..
    echo -e "${GREEN}✅ 依赖构建成功${NC}"
    
    echo -e "${GREEN}验证 Chart 语法...${NC}"
    helm lint $CHART_PATH --values $VALUES_FILE
    echo -e "${GREEN}✅ Chart 语法检查通过${NC}"
    
    echo -e "${GREEN}生成模板预览...${NC}"
    mkdir -p $OUTPUT_DIR/template-preview
    helm template $RELEASE_NAME $CHART_PATH \
        --values $VALUES_FILE \
        --namespace $K8S_NAMESPACE \
        --output-dir $OUTPUT_DIR/template-preview
    echo -e "${GREEN}✅ 模板生成成功，输出目录: $OUTPUT_DIR/template-preview${NC}"
}

# 打包阶段
package() {
    echo -e "${MAGENTA}🎯 Step 3: 打包阶段${NC}"
    mkdir -p $OUTPUT_DIR
    
    echo -e "${GREEN}检查并构建 Chart 依赖...${NC}"
    cd $CHART_PATH
    
    # 检查是否存在依赖
    if [ -f "Chart.yaml" ] && grep -q "dependencies:" "Chart.yaml"; then
        echo -e "${YELLOW}发现 Chart 依赖，正在配置仓库...${NC}"
        # 添加必要的 Helm 仓库
        helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts || true
        helm repo add jaegertracing https://jaegertracing.github.io/helm-charts || true
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
        helm repo add grafana https://grafana.github.io/helm-charts || true
        helm repo add opensearch https://opensearch-project.github.io/helm-charts || true
        helm repo update
        
        echo -e "${YELLOW}正在构建依赖...${NC}"
        helm dependency build
        echo -e "${GREEN}✅ 依赖构建成功${NC}"
    else
        echo -e "${CYAN}ℹ️  无需构建依赖${NC}"
    fi
    
    cd ../..
    
    echo -e "${GREEN}打包 Helm Chart...${NC}"
    helm package $CHART_PATH --version $CHART_VERSION --destination $OUTPUT_DIR
    
    PACKAGE_FILE="$OUTPUT_DIR/$CHART_NAME-$CHART_VERSION.tgz"
    if [ -f "$PACKAGE_FILE" ]; then
        echo -e "${GREEN}✅ Chart 打包成功: $PACKAGE_FILE${NC}"
        SIZE=$(du -h "$PACKAGE_FILE" | cut -f1)
        echo -e "${CYAN}📦 包大小: $SIZE${NC}"
    else
        echo -e "${RED}❌ 打包文件未找到${NC}"
        exit 1
    fi
}

# 推送到 ACR
push_to_acr() {
    echo -e "${MAGENTA}🎯 Step 4: 推送到 ACR 阶段${NC}"
    
    PACKAGE_FILE="$OUTPUT_DIR/$CHART_NAME-$CHART_VERSION.tgz"
    if [ ! -f "$PACKAGE_FILE" ]; then
        echo -e "${RED}❌ 打包文件不存在: $PACKAGE_FILE，请先执行打包步骤${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}检查 ACR 登录状态...${NC}"
    
    # 检查是否已经登录
    if check_acr_login; then
        echo -e "${GREEN}✅ 已登录到 ACR，跳过登录步骤${NC}"
    else
        echo -e "${YELLOW}未登录或登录已过期，正在登录到 ACR...${NC}"
        get_acr_credentials
        
        echo "$ACR_PASSWORD_INPUT" | helm registry login $ACR_REGISTRY --username $ACR_USERNAME_INPUT --password-stdin
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ ACR 登录成功${NC}"
        else
            echo -e "${RED}❌ ACR 登录失败${NC}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}推送 Chart 到 ACR...${NC}"
    ACR_CHART_URL="oci://$ACR_REGISTRY/$ACR_NAMESPACE"
    helm push $PACKAGE_FILE $ACR_CHART_URL
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Chart 推送成功到: $ACR_CHART_URL${NC}"
    else
        echo -e "${RED}❌ Chart 推送失败${NC}"
        exit 1
    fi
}

# 显示部署状态
show_status() {
    echo ""
    echo -e "${CYAN}📊 部署状态检查:${NC}"
    helm status $RELEASE_NAME -n $K8S_NAMESPACE
    echo ""
    echo -e "${CYAN}🔍 Pod 状态:${NC}"
    kubectl get pods -n $K8S_NAMESPACE
    echo ""
    echo -e "${CYAN}🌐 Service 状态:${NC}"
    kubectl get svc -n $K8S_NAMESPACE
    echo ""
    echo -e "${GREEN}🚀 访问应用:${NC}"
    echo -e "${YELLOW}端口转发命令 (在另一个终端执行):${NC}"
    echo -e "${CYAN}kubectl port-forward -n $K8S_NAMESPACE svc/frontend-proxy 8080:8080${NC}"
    echo -e "${YELLOW}然后访问: http://localhost:8080${NC}"
}

# 本地安装
install_local() {
    echo -e "${MAGENTA}🎯 Step 5: 本地安装 - 从本地 Chart 安装${NC}"
    
    if helm list -n $K8S_NAMESPACE | grep -q "^$RELEASE_NAME"; then
        echo -e "${YELLOW}⚠️  Release '$RELEASE_NAME' 已存在，将执行升级...${NC}"
        INSTALL_CMD="upgrade"
    else
        echo -e "${GREEN}🆕 Release '$RELEASE_NAME' 不存在，将执行安装...${NC}"
        INSTALL_CMD="install"
    fi
    
    echo -e "${GREEN}使用 helm $INSTALL_CMD 从本地 Chart 部署...${NC}"
    if [ "$INSTALL_CMD" = "install" ]; then
        helm install $RELEASE_NAME $CHART_PATH \
            --namespace $K8S_NAMESPACE \
            --create-namespace \
            --values $VALUES_FILE \
            --timeout 10m \
            --wait
    else
        helm upgrade $RELEASE_NAME $CHART_PATH \
            --namespace $K8S_NAMESPACE \
            --values $VALUES_FILE \
            --timeout 10m \
            --wait
    fi
    
    echo -e "${GREEN}✅ 部署成功！${NC}"
    show_status
}

# ACR 安装
install_acr() {
    echo -e "${MAGENTA}🎯 Step 6: ACR 安装 - 从 ACR 仓库安装${NC}"
    
    if helm list -n $K8S_NAMESPACE | grep -q "^$RELEASE_NAME"; then
        echo -e "${YELLOW}⚠️  Release '$RELEASE_NAME' 已存在，将执行升级...${NC}"
        INSTALL_CMD="upgrade"
    else
        echo -e "${GREEN}🆕 Release '$RELEASE_NAME' 不存在，将执行安装...${NC}"
        INSTALL_CMD="install"
    fi
    
    ACR_CHART_URL="oci://$ACR_REGISTRY/$ACR_NAMESPACE/$CHART_NAME"
    echo -e "${GREEN}使用 helm $INSTALL_CMD 从 ACR 仓库部署...${NC}"
    echo -e "${CYAN}Chart 地址: $ACR_CHART_URL${NC}"
    echo -e "${CYAN}版本: $CHART_VERSION${NC}"
    
    if [ "$INSTALL_CMD" = "install" ]; then
        helm install $RELEASE_NAME $ACR_CHART_URL \
            --version $CHART_VERSION \
            --namespace $K8S_NAMESPACE \
            --create-namespace \
            --values $VALUES_FILE \
            --timeout 10m \
            --wait
    else
        helm upgrade $RELEASE_NAME $ACR_CHART_URL \
            --version $CHART_VERSION \
            --namespace $K8S_NAMESPACE \
            --values $VALUES_FILE \
            --timeout 10m \
            --wait
    fi
    
    echo -e "${GREEN}✅ 部署成功！${NC}"
    show_status
}

# 显示手动命令
show_commands() {
    echo -e "${CYAN}📋 手动 Helm Install 命令参考${NC}"
    echo ""
    echo -e "${MAGENTA}🎯 方式一：从本地 Chart 安装${NC}"
    echo "helm install $RELEASE_NAME $CHART_PATH \\"
    echo "    --namespace $K8S_NAMESPACE \\"
    echo "    --create-namespace \\"
    echo "    --values $VALUES_FILE \\"
    echo "    --timeout 10m \\"
    echo "    --wait"
    echo ""
    echo -e "${MAGENTA}🎯 方式二：从 ACR OCI 仓库安装${NC}"
    echo "# 1. 首先登录 ACR"
    echo "helm registry login $ACR_REGISTRY --username <username>"
    echo ""
    echo "# 2. 安装应用"
    echo "helm install $RELEASE_NAME oci://$ACR_REGISTRY/$ACR_NAMESPACE/$CHART_NAME \\"
    echo "    --version $CHART_VERSION \\"
    echo "    --namespace $K8S_NAMESPACE \\"
    echo "    --create-namespace \\"
    echo "    --values $VALUES_FILE \\"
    echo "    --timeout 10m \\"
    echo "    --wait"
}

# 卸载应用
uninstall() {
    echo -e "${MAGENTA}🗑️  卸载应用: $RELEASE_NAME${NC}"
    
    if ! helm list -n $K8S_NAMESPACE | grep -q "^$RELEASE_NAME"; then
        echo -e "${YELLOW}⚠️  Release '$RELEASE_NAME' 不存在${NC}"
        exit 0
    fi
    
    echo -e "${GREEN}执行 helm uninstall...${NC}"
    helm uninstall $RELEASE_NAME -n $K8S_NAMESPACE
    echo -e "${GREEN}✅ 应用卸载成功${NC}"
}

# 清理
clean() {
    echo -e "${GREEN}清理输出目录...${NC}"
    rm -rf $OUTPUT_DIR
    echo -e "${GREEN}✅ 清理完成${NC}"
}

# 完整部署流程
full_deploy() {
    echo -e "${MAGENTA}🚀 开始完整部署流程...${NC}"
    prepare
    test_local
    package
    push_to_acr
    install_acr
    echo ""
    echo -e "${GREEN}🎉 完整部署流程成功完成！${NC}"
}

# 主函数
main() {
    case ${1:-help} in
        help|--help|-h)
            show_help
            ;;
        prepare)
            prepare
            ;;
        test-local)
            test_local
            ;;
        package)
            package
            ;;
        push-to-acr)
            push_to_acr
            ;;
        install-local)
            install_local
            ;;
        install-acr)
            install_acr
            ;;
        show-commands)
            show_commands
            ;;
        uninstall)
            uninstall
            ;;
        clean)
            clean
            ;;
        full-deploy)
            full_deploy
            ;;
        force-login)
            force_acr_login
            ;;
        *)
            echo -e "${RED}❌ 未知操作: $1${NC}"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@" 