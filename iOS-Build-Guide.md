# MyTuner iOS 版 —— 编译打包说明

> 本说明写给「有 Mac、负责编译」的同学。
> 目标是把这个项目编译成一个能在 iPhone 上运行的调音器 App，全程免费、无需付费开发者账号。

---

## 一、需要打包的文件清单（重点）

编译 App 只需要下面 **4 个 Swift 源码文件**（外加本说明文件）。打包时把这 5 个文件发给同学即可。

```
MyTuner/
├── MyTunerApp.swift        # App 入口（@main）
├── ContentView.swift       # 界面 UI（表盘 / 音名 / 乐器切换）
├── TunerEngine.swift       # 核心音频引擎（麦克风采集 + YIN 音高检测）
└── Models.swift            # 乐器、调弦、音高换算等数据模型
iOS-Build-Guide.md          # 本编译说明（给编译的同学看）
```

| 文件 | 相对路径 | 作用 |
|------|----------|------|
| `MyTunerApp.swift` | `MyTuner/MyTunerApp.swift` | App 入口，`@main` |
| `ContentView.swift` | `MyTuner/ContentView.swift` | 界面 UI（表盘、音名、音分、乐器切换、琴弦） |
| `TunerEngine.swift` | `MyTuner/TunerEngine.swift` | 核心：AVAudioEngine 麦克风采集 + YIN 时域自相关音高检测 |
| `Models.swift` | `MyTuner/Models.swift` | 乐器、调弦、音高换算等数据模型 |

> ⚠️ 4 个 `.swift` 文件**缺一不可**，否则编译会报错。

---

## 二、编译步骤

### 1. 准备

1. 一台 **Mac**，安装 **Xcode**（App Store 免费下载，登录一个 Apple ID，约 12 GB）。
2. 拿到第一节的 4 个源码文件。

### 2. 新建 Xcode 工程

1. 打开 Xcode → 菜单 **File → New → Project…**
2. 模板选 **iOS → App**，点 **Next**
3. 填写：
   - **Product Name**：`MyTuner`
   - **Interface**：`SwiftUI`
   - **Language**：`Swift`
   - 取消勾选 **Include Tests**
4. 选保存位置，点 **Create**

### 3. 放入源码

1. 在左侧导航栏，选中 Xcode 自动生成的 `MyTunerApp.swift` 和 `ContentView.swift`，右键 → **Delete → Move to Trash**。
2. 把 4 个 `.swift` 文件**拖进** Xcode 左侧导航栏（拖到 MyTuner 项目根下）。
   弹出框勾选：
   - ✅ **Copy items if needed**
   - ✅ **Add to targets: MyTuner**

### 4. 添加麦克风权限描述（⚠️ 必做，否则闪退）

调音器要访问麦克风，必须在 `Info.plist` 里声明用途：

1. 选中项目 → `MyTuner` target → **Info** 标签。
2. 点任意 Key 行末尾的 **＋**，新增一行：
   - **Key**：`Privacy - Microphone Usage Description`
   - **Value**：`需要使用麦克风来检测琴弦音高`

### 5. 运行

**方式 A：模拟器（先看界面）**
- 顶部设备选择器选任意 iPhone 模拟器，点 **▶**。
- ⚠️ 模拟器**没有麦克风**（拿不到真实声音），只能看界面；测音准请用真机。

**方式 B：真机（装到 iPhone 上，测真实音准）**
1. 数据线连 iPhone 到 Mac。
2. 顶部设备选择器选你的 iPhone。
3. 选中 `MyTuner` 项目 → `MyTuner` target → **Signing & Capabilities**。
4. 勾选 **Automatically manage signing**，**Team** 选自己的 Apple ID（免费账号即可）。
5. 若报 bundle identifier 冲突，把 **Bundle Identifier** 改成唯一的，如 `com.你的名字.MyTuner`。
6. 点 **▶**。首次装机会提示「未受信任的开发者」，去 iPhone **设置 → 通用 → VPN 与设备管理** → 信任证书。
7. 首次点「开始」会弹麦克风授权，点「允许」。

---

## 三、注意事项

- **免费证书的 App 有效期 7 天**，到期重连电脑运行一次即续期；长期使用建议上架 App Store 或走 TestFlight。
- **必须加麦克风权限描述**（第二节第 4 步），否则 App 一调麦克风就闪退。
- 调音时尽量在安静环境、靠近琴弦拨**单根**弦，结果更稳定。

---

## 四、常见问题

| 问题 | 解决 |
|------|------|
| 编译报错「No such module / Cannot find type」 | 确认 4 个文件都拖进了 target（Add to targets 勾选 MyTuner），且删除了自动生成的两个同名文件 |
| 一运行就闪退 | 检查是否漏加了 `Privacy - Microphone Usage Description` |
| 真机提示证书不受信任 | 去 设置→通用→VPN与设备管理 信任证书 |
| 点「开始」后没反应 | 确认已点「允许」麦克风权限；可去 设置→隐私→麦克风 里检查 |
| 模拟器没声音 / 测不出音高 | 正常现象，模拟器无麦克风，换真机测试 |
