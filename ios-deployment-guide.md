# 🚀 虾觅 iOS 构建 & 部署完全指南

> 无需 Mac、无需 Xcode，纯云端操作

---

## 📋 总览

```
你的代码 ──→ GitHub 仓库 ──→ Codemagic/GitHub Actions 云端 Mac 环境
                                ↓
                         编译 iOS 安装包
                                ↓
              下载 IPA → 用侧载工具安装到 iPhone
```

---

## 🏆 方案 A：Codemagic（推荐，最省心）

### 1. 注册 Codemagic

1. 打开 https://codemagic.io/signup
2. 用 **GitHub 账号** 登录（免费 500 分钟/月）
3. 点击 **"Add application"**

### 2. 连接仓库

1. 先把你们项目推送到 GitHub（如果没有 Git，后面会说怎么处理）
2. 在 Codemagic 中选择你的仓库
3. 选择 `supermarket_manager` 项目

### 3. 配置文件

我已经为你写好了 `codemagic.yaml`，放到项目根目录即可。推送到 GitHub 后，Codemagic 会自动识别并执行。

#### 你需要改的地方：

```yaml
# codemagic.yaml 第 18 行：
APP_ID: io.supermarket.manager    # ← 改成你的 Bundle ID，比如 com.yourname.supermarket

# 第 95 行：
- your-email@example.com           # ← 改成你的邮箱，构建结果会发邮件通知
```

### 4. 触发构建

在 Codemagic 网页上点击 **"Start build"**，等待约 10-15 分钟。

### 5. 下载 IPA

构建成功后，在 Codemagic 的 **"Artifacts"** 标签页下载 `.ipa` 文件。

---

### 🤔 我没有用 Git / 不会推 GitHub 怎么办？

用网页版上传：

1. 去 https://github.com 注册一个账号
2. 点 **"New repository"** → 取名 `supermarket-manager`
3. 创建后点 **"uploading an existing file"**
4. 把整个项目文件夹拖进去（**注意不要传 android/.gradle/ 这些编译缓存**）
5. 提交（Commit changes）
6. 回到上面方案 A 第 1 步

---

## 🏆 方案 B：GitHub Actions（备选，完全免费）

我的配置已经写好放 `.github/workflows/ios-build.yml` 了。

### 用法：

1. 推送到 GitHub
2. 打开仓库的 **Actions** 页面
3. 你会看到 **"虾觅 iOS 构建"** 工作流
4. 点 **"Run workflow"** → 选 **"release"** → 点击运行
5. 等 15-20 分钟后，在 build 详情页下载 **Artifacts**（IPA 文件）

---

## 📲 怎么把 IPA 装到 iPhone 上？

> ⚠️ 无签名的 IPA 不能直接安装。下面是免费侧载方案。

### 方案一：SideStore（免费，推荐）

| 步骤 | 说明 |
|------|------|
| 1️⃣ | 在 Windows 上打开 https://sidestore.io 下载 SideStore |
| 2️⃣ | 用数据线连接 iPhone，安装 SideStore |
| 3️⃣ | 在 SideStore 中登录你的 **免费 Apple ID** |
| 4️⃣ | 把下载的 IPA 文件通过 SideStore 安装到 iPhone |
| 5️⃣ | **每 7 天** 需要刷新一次（SideStore 会自动提醒） |

**优点**：完全免费，不需要 Mac

### 方案二：AltStore（免费，备选）

| 步骤 | 说明 |
|------|------|
| 1️⃣ | 下载 https://altstore.io （Windows 版已支持） |
| 2️⃣ | 安装 AltServer，连接 iPhone |
| 3️⃣ | 用 AltStore 安装 IPA |
| 4️⃣ | 每 7 天刷新一次 |

### 方案三：购买 Apple 开发者账号（$99/年，一劳永逸）

如果你打算让员工、客户都用这个 App，建议买开发者账号：

1. 去 https://developer.apple.com 注册（$99/年）
2. 在 Codemagic 中配置你的证书（网页 UI 操作，很简单）
3. 之后构建的 IPA 可以直接安装，**没有 7 天过期**
4. 还可以通过 **TestFlight** 分发给团队成员（最多 10000 人）

---

## 🏗️ 项目文件清单（我写了什么）

```
项目根目录/
├── codemagic.yaml                  ← 【核心】Codemagic 云端构建配置
└── .github/
    └── workflows/
        └── ios-build.yml           ← 【备选】GitHub Actions 构建工作流
```

**这两个文件放到项目的根目录**，推送后自动生效。

---

## 💰 成本对比

| 方案 | 费用 | 说明 |
|------|------|------|
| Codemagic 免费版 | **免费** | 每月 500 分钟，每个月能打 30-40 次包 |
| GitHub Actions | **免费** | macOS runner 免费额度，每月 2000 分钟 |
| Apple 开发者账号 | **$99/年** | 可选，装自己手机不需要 |
| SideStore/AltStore | **免费** | 侧载工具，不需要开发者账号 |

---

## ❗ 注意事项

1. **第一次构建比较慢**（约 15-20 分钟），因为要下载 Flutter SDK 和 CocoaPods 依赖。后面就快了（3-5 分钟）
2. **免费 Apple ID 安装的 App 7 天过期**，可以用 SideStore 自动续期
3. **相机扫码可以正常使用**，已经配好了 `NSCameraUsageDescription`
4. 所有核心功能（本地数据库、Supabase 同步、扫码、PDF 导出）**iOS 全部支持**

---

## 🎯 总结

你完全不需要接触 Mac、Xcode 这些 macOS 生态的玩意：

```
你只需要做的：
  1. 注册 GitHub
  2. 把项目代码上传
  3. 注册 Codemagic
  4. 点一下 "Start Build"
  5. 下载 IPA
  6. 用 SideStore 装到 iPhone

剩下的都是我搞定的：
  ✅ codemagic.yaml 配置
  ✅ Info.plist（相机权限）
  ✅ Podfile（iOS 依赖）
  ✅ GitHub Actions 备选方案
  ✅ 侧载安装指南
```

**开始吧！先从注册 GitHub 开始，把代码传上去，剩下的我来接。**
