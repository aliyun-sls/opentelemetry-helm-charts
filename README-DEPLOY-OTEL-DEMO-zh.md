# OpenTelemetry Demo 部署指南

本指南仅仅为了方便 demo 接入 ACK, ACR 等阿里云基础设施。

## 快速开始

### 🚀 一键部署

```bash
# 方式一：使用 Makefile (Linux/macOS 推荐)
make -f Makefile.otel.demo help

# 方式二：使用 Shell 脚本 (通用)
./deploy-otel-demo.sh help

# 完整自动化部署
make -f Makefile.otel.demo full-deploy

# 或者分步骤执行
make -f Makefile.otel.demo prepare
make -f Makefile.otel.demo install-local
```

## 部署方式对比

### 工具选择

我们提供了两种部署工具，功能完全相同：

| 功能 | 描述 | Makefile 命令 | Shell 脚本命令 |
|------|------|---------------|----------------|
| 帮助信息 | 显示所有可用命令 | `make -f Makefile.otel.demo help` | `./deploy-otel-demo.sh help` |
| 准备阶段 | 创建命名空间和 ACR Secret | `make -f Makefile.otel.demo prepare` | `./deploy-otel-demo.sh prepare` |
| 本地测试 | 验证 chart 配置 | `make -f Makefile.otel.demo test-local` | `./deploy-otel-demo.sh test-local` |
| 打包阶段 | 生成 helm chart 包 | `make -f Makefile.otel.demo package` | `./deploy-otel-demo.sh package` |
| 推送到 ACR | 推送到阿里云 ACR | `make -f Makefile.otel.demo push-to-acr` | `./deploy-otel-demo.sh push-to-acr` |
| 本地安装 | 从本地 chart 安装 | `make -f Makefile.otel.demo install-local` | `./deploy-otel-demo.sh install-local` |
| ACR 安装 | 从 ACR 仓库安装 | `make -f Makefile.otel.demo install-acr` | `./deploy-otel-demo.sh install-acr` |
| 显示命令 | 显示手动命令 | `make -f Makefile.otel.demo show-commands` | `./deploy-otel-demo.sh show-commands` |
| 完整流程 | 执行所有步骤 | `make -f Makefile.otel.demo full-deploy` | `./deploy-otel-demo.sh full-deploy` |
| 卸载应用 | 卸载部署的应用 | `make -f Makefile.otel.demo uninstall` | `./deploy-otel-demo.sh uninstall` |
| 清理文件 | 清理生成的文件 | `make -f Makefile.otel.demo clean` | `./deploy-otel-demo.sh clean` |

**选择建议：**
- **Linux/macOS + make 可用**: 使用 `Makefile.otel.demo`
- **Windows 或无 make**: 使用 `deploy-otel-demo.sh`
- **CI/CD 流水线**: 两者都支持，推荐 shell 脚本更通用

### 安装方式选择

支持三种 Helm 安装方式：

1. **本地 Chart 安装** (开发推荐)
   - 适用场景：开发测试、快速迭代
   - 优点：快速、无需网络
   - 使用：`install-local`

2. **ACR OCI 仓库安装** (生产推荐)
   - 适用场景：生产环境、CI/CD
   - 优点：版本管理、中央仓库
   - 使用：`install-acr`

3. **本地包安装** (特殊场景)
   - 适用场景：离线环境
   - 优点：完全离线
   - 使用：手动 `helm install` 本地 `.tgz` 文件

## 环境配置

### 必需的环境变量

```bash
# ACR 注册表信息
export ACR_REGISTRY="o11y-demo-registry-vpc.cn-hongkong.cr.aliyuncs.com"
export ACR_NAMESPACE="o11y-demo"

# 部署配置
export CHART_VERSION="0.37.2"
export K8S_NAMESPACE="opentelemetry-demo"
export RELEASE_NAME="my-otel-demo"

# ACR 凭据 (可选，不设置将交互式提示)
export ACR_USERNAME="your_acr_username"
export ACR_PASSWORD="your_acr_password"
```

### 自定义配置示例

```bash
# 自定义发布名称和命名空间
make -f Makefile.otel.demo install-local RELEASE_NAME=prod-demo K8S_NAMESPACE=production

# 使用环境变量提供 ACR 凭据
ACR_USERNAME=myuser ACR_PASSWORD=mypass make -f Makefile.otel.demo full-deploy
```

## 详细部署流程

### 方式一：完整自动化部署

**适用场景：** 一键部署，适合 CI/CD 和快速部署

#### Makefile 方式
```bash
# 显示帮助
make -f Makefile.otel.demo help

# 完整自动化部署
make -f Makefile.otel.demo full-deploy

# 查看部署状态
make -f Makefile.otel.demo show-status
```

#### Shell 脚本方式
```bash
# 显示帮助
./deploy-otel-demo.sh help

# 完整自动化部署
./deploy-otel-demo.sh full-deploy

# 查看应用状态
kubectl get pods -n opentelemetry-demo
```

完整流程包含以下步骤：
1. 准备阶段：创建 K8s 命名空间和 ACR Secret
2. 本地测试：验证 Chart 配置和依赖
3. 打包阶段：生成 `.tgz` 格式的 Helm Chart 包
4. 推送阶段：推送 Chart 到 ACR OCI 仓库
5. 安装阶段：从 ACR 部署到 Kubernetes

### 方式二：分步骤执行

**适用场景：** 需要在每个步骤进行验证或自定义

#### 基础准备
```bash
# 1. 创建 K8s 命名空间和 ACR Secret
make -f Makefile.otel.demo prepare

# 2. 验证环境和 Chart 配置
make -f Makefile.otel.demo test-local
```

#### 开发模式：本地部署
```bash
# 直接从本地 chart 安装（跳过 ACR）
make -f Makefile.otel.demo install-local
```

#### 生产模式：通过 ACR 部署
```bash
# 1. 打包 Chart
make -f Makefile.otel.demo package

# 2. 推送到 ACR
make -f Makefile.otel.demo push-to-acr

# 3. 从 ACR 安装
make -f Makefile.otel.demo install-acr
```

### 方式三：生产环境部署

**适用场景：** 生产环境，需要严格的版本控制

```bash
# 设置生产环境变量
export RELEASE_NAME="prod-otel-demo"
export K8S_NAMESPACE="production"
export CHART_VERSION="0.37.2"

# 执行完整部署
make -f Makefile.otel.demo full-deploy RELEASE_NAME=prod-otel-demo K8S_NAMESPACE=production
```

## 特定场景使用

### CI/CD 流水线集成

**只需打包和推送（不部署）：**
```bash
# 设置凭据并执行打包推送
export ACR_USERNAME="ci_user"
export ACR_PASSWORD="ci_password"

make -f Makefile.otel.demo package
make -f Makefile.otel.demo push-to-acr
make -f Makefile.otel.demo install-acr
```

### 本地开发环境

**快速本地部署（跳过 ACR）：**
```bash
# 准备环境
make -f Makefile.otel.demo prepare

# 本地部署（无需 ACR 推送）
make -f Makefile.otel.demo full-deploy

# 或者更简单的
ACR_USERNAME=user ACR_PASSWORD=pass make -f Makefile.otel.demo prepare
```

### 多环境部署

**开发环境：**
```bash
make -f Makefile.otel.demo install-local
```

**测试/生产环境：**
```bash
make -f Makefile.otel.demo install-acr
```

## 故障排除

### 常见问题

1. **ACR 登录失败**
   ```bash
   # 手动登录测试
   helm registry login o11y-demo-registry-vpc.cn-hongkong.cr.aliyuncs.com --username <username>
   ```

2. **Chart 依赖问题**
   ```bash
   # 清理并重新构建依赖
   cd charts/opentelemetry-demo
   rm -rf charts/ Chart.lock
   helm dependency build
   ```

3. **Kubernetes 权限问题**
   ```bash
   # 检查 kubectl 配置
   kubectl config current-context
   kubectl auth can-i create pods --namespace opentelemetry-demo
   ```

### 卸载和清理

```bash
# 卸载应用
make -f Makefile.otel.demo uninstall

# 清理生成的文件
make -f Makefile.otel.demo clean
```

## 高级配置

### 自定义 ACR 配置

如果使用不同的 ACR 配置，可以设置环境变量：

```bash
export ACR_REGISTRY="your-registry.cr.aliyuncs.com"
export ACR_NAMESPACE="your-namespace"
export ACR_USERNAME="your-username"
export ACR_PASSWORD="your-password"

make -f Makefile.otel.demo prepare
```

### 环境变量优先级

1. **环境变量** (最高优先级)
2. **交互输入** (如果环境变量未设置)
3. **默认值** (最低优先级)

### 自动化集成示例

```bash
# CI/CD 脚本示例
#!/bin/bash
set -e

export ACR_USERNAME="${CI_ACR_USERNAME}"
export ACR_PASSWORD="${CI_ACR_PASSWORD}"
export RELEASE_NAME="otel-demo-${CI_ENVIRONMENT}"
export K8S_NAMESPACE="${CI_ENVIRONMENT}"

make -f Makefile.otel.demo full-deploy
```

## 架构说明

### 部署架构
- **镜像来源**: 阿里云 ACR 私有仓库
- **Chart 存储**: ACR OCI 仓库 (Helm v3+)
- **目标平台**: Kubernetes 集群
- **服务数量**: 17 个微服务 + 4 个基础设施组件

### 资源要求
- **内存**: ~4-5GB
- **CPU**: ~2-3 Core
- **存储**: ~10GB (包含日志和数据)

---

**需要帮助？** 运行 `make -f Makefile.otel.demo help` 或 `./deploy-otel-demo.sh help` 查看所有可用命令。 