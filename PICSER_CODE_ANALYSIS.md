# Picser 项目代码分析总结

## 1. 打开单个图片的逻辑

### 核心入口
- **主文件**: `/Volumes/pssd/Users/eric/01.HelloWord/05.macos/Picser/Picser/ContentView/ContentView.swift`
- **关键函数**:
  - `openFileOrFolder()` (L672-679): 打开文件对话框入口
  - `handleDropProviders()` (L682-692): 处理拖放操作入口

### 打开流程
1. **用户操作**:
   ```swift
   func openFileOrFolder() {
     Task {
       // 调用 FileOpenService，传入递归标志
       guard let batch = await FileOpenService.openFileOrFolder(recursive: appSettings.imageScanRecursively) else { return }
       await MainActor.run {
         applyImageBatch(batch)  // 应用新的图片批次
       }
     }
   }
   ```

2. **FileOpenService 处理**:
   - 文件: `/Volumes/pssd/Users/eric/01.HelloWord/05.macos/Picser/Picser/Models/FileOpenService.swift`
   - 功能:
     - `openFileOrFolder()`: 弹出打开面板
     - `processDropProviders()`: 处理拖放提供者
     - `loadImageBatch()`: 统一的加载逻辑

3. **图片发现**:
   - 文件: `/Volumes/pssd/Users/eric/01.HelloWord/05.macos/Picser/Picser/Models/ImageDiscovery.swift`
   - 函数: `ImageDiscovery.computeImageURLs(from:recursive:)`
   - 功能:
     - 枚举目录中的图片
     - 按 Finder 风格排序
     - 去重处理

### 文件打开后的处理
- **函数**: `applyImageBatch()` (ContentView+ImageManagement.swift, L18-45)
- **处理**:
  - 更新 `imageURLs` 状态
  - 选择第一张图片或保留用户之前的选择
  - 重置缩放/旋转状态

---

## 2. 用户设置的定义和存储

### 设置管理类
- **主文件**: `/Volumes/pssd/Users/eric/01.HelloWord/05.macos/Picser/Picser/Models/AppSettings.swift`
- **类型**: `class AppSettings: ObservableObject`

### 存储方式
使用 `@AppStorage` (基于 UserDefaults) 和 JSON 持久化

#### 快捷键设置
```swift
@AppStorage("zoomModifierKey") private var zoomModifierKeyStorage: String = ModifierKey.none.rawValue
@AppStorage("panModifierKey") private var panModifierKeyStorage: String = ModifierKey.none.rawValue
@AppStorage("imageNavigationOptionsJSON") private var imageNavigationOptionsJSON: String = ""
@AppStorage("deleteShortcutOptionsJSON") private var deleteShortcutOptionsJSON: String = ""
```

#### 显示设置
```swift
@AppStorage("zoomSensitivity") var zoomSensitivity: Double = 0.05
@AppStorage("zoomAnchorsToPointer") private var zoomAnchorsToPointerStorage: Bool = true
@AppStorage("minZoomScale") var minZoomScale: Double = 0.1
@AppStorage("maxZoomScale") var maxZoomScale: Double = 10.0
```

#### 小地图设置
```swift
@AppStorage("showMinimap") var showMinimap: Bool = true
@AppStorage("minimapAutoHideSeconds") var minimapAutoHideSeconds: Double = 0.0
```

#### 幻灯片设置
```swift
@AppStorage("slideshowIntervalSeconds") private var slideshowIntervalSecondsStorage: Double = 3.0
@AppStorage("slideshowLoopEnabled") private var slideshowLoopEnabledStorage: Bool = true
```

#### 语言和删除设置
```swift
@AppStorage("appLanguage") private var appLanguageStorage: String = AppLanguage.system.rawValue
@AppStorage("deleteConfirmationEnabled") private var deleteConfirmationEnabledStorage: Bool = true
```

#### 裁剪设置
```swift
@AppStorage("customCropRatiosJSON") private var customCropRatiosJSON: String = "[]"
```

---

## 3. 递归打开子文件夹的设置

### 设置定义位置
- **文件**: `/Volumes/pssd/Users/eric/01.HelloWord/05.macos/Picser/Picser/Models/AppSettings.swift`
- **第193行**:
```swift
@AppStorage("imageScanRecursively") var imageScanRecursively: Bool = true
```

### 设置UI定位
- **文件**: `/Volumes/pssd/Users/eric/01.HelloWord/05.macos/Picser/Picser/Views/Settings/DisplaySettingsView.swift`
- **第123-125行**:
```swift
Toggle(isOn: $appSettings.imageScanRecursively) {
  Text(l10n: "image_scan_recursive_toggle")
}
```
- **位置**: 显示设置 → 图片扫描设置组

### 设置使用位置

#### 1. 打开文件对话框时
- **文件**: ContentView.swift, L674
```swift
guard let batch = await FileOpenService.openFileOrFolder(recursive: appSettings.imageScanRecursively) else { return }
```

#### 2. 处理拖放时
- **文件**: ContentView.swift, L685
```swift
if let batch = await FileOpenService.processDropProviders(providers, recursive: appSettings.imageScanRecursively) {
```

#### 3. 刷新当前文件夹时
- **文件**: ContentView+ImageManagement.swift, L57
```swift
recursive: appSettings.imageScanRecursively,
```

#### 4. 打开外部图片时
- **文件**: ContentView+ImageManagement.swift, L109
```swift
recursive: appSettings.imageScanRecursively,
```

### 递归标志解析
- **文件**: FileOpenService.swift, L120-126
```swift
private static func resolvedRecursiveFlag(override: Bool?) -> Bool {
  if let override { return override }  // 优先级1: 显式传递的值
  if let stored = UserDefaults.standard.object(forKey: "imageScanRecursively") as? Bool {
    return stored  // 优先级2: UserDefaults 存储的值
  }
  return true  // 优先级3: 默认值 (true)
}
```

---

## 4. 左侧图片列表的加载和管理

### 核心数据结构
- **主组件**: `SidebarView.swift`
- **传入参数**:
```swift
struct SidebarView: View {
  let imageURLs: [URL]  // 图片 URL 列表
  let selectedImageURL: URL?  // 当前选中的图片
  @Binding var showingFilterPopover: Bool
  let onSelect: (URL) -> Void
}
```

### 列表加载流程

#### 第1步: 获取 ImageBatch
- 调用 `FileOpenService.openFileOrFolder()` 或 `processDropProviders()`
- 返回 `ImageBatch` 结构:
```swift
struct ImageBatch {
  let inputs: [URL]  // 原始输入
  let securityScopedInputs: [URL]  // 安全作用域 URL
  let imageURLs: [URL]  // 排序后的图片列表
  let accessGroup: SecurityScopedAccessGroup
}
```

#### 第2步: 应用到 ContentView
- **函数**: `applyImageBatch()` (ContentView+ImageManagement.swift)
```swift
func applyImageBatch(_ batch: ImageBatch, preserveSelection selection: URL? = nil) {
  securityAccessGroup = batch.accessGroup
  currentSourceInputs = batch.inputs
  currentSecurityScopedInputs = batch.securityScopedInputs
  imageURLs = batch.imageURLs  // 更新列表
}
```

#### 第3步: 状态传递到 SidebarView
- **文件**: ContentView.swift
- 通过 NavigationSplitView 传递:
```swift
SidebarView(
  imageURLs: visibleImageURLs,  // 使用过滤后的列表
  selectedImageURL: selectedImageURL,
  ...
)
```

### 列表渲染
- **SidebarView.swift, L28-56**:
```swift
List {
  ForEach(imageURLs, id: \.self) { url in
    ZStack(alignment: .bottomLeading) {
      ThumbnailImageView(url: url, height: 80)
      Text(url.lastPathComponent)
    }
    .onTapGesture { onSelect(url) }  // 选中项目
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke((selectedImageURL == url) ? Color.accentColor : Color.clear, lineWidth: 2)
    )
  }
}
```

### 列表更新监听
- **ContentView.swift, L185-194**:
```swift
.onChange(of: imageURLs) { _, newURLs in
  Task {
    await tagService.refreshScope(with: newURLs)  // 更新标签作用域
  }
  filteredImageURLs = newURLs  // 初始化过滤列表
  ensureSelectionVisible()
  updateSidebarVisibility()
  handleSlideshowImageListChange()
}
```

---

## 5. 同目录图片加载

### 核心逻辑
- **文件**: ContentView+ImageManagement.swift, L78-114
- **函数**: `openResolvedURL(_ url: URL)`

### 逻辑流程

```swift
func openResolvedURL(_ url: URL) {
  Task { @MainActor in
    // 1. 获取图片所在目录
    let directoryURL = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
    
    // 2. 查找已获得权限的相关目录 (安全作用域)
    var scopedInputs: [URL] = []
    appendScoped(directoryURL)
    
    // 3. 从已有的安全作用域中查找相同目录下的其他 URL
    if let retained = securityAccessGroup?.retainedURLs {
      let directoryPath = standardizedDirectory.path
      for candidate in retained {
        if candidatePath == directoryPath || candidatePath.hasPrefix(directoryPrefix) {
          appendScoped(candidate)  // 添加权限覆盖的同目录 URL
        }
      }
    }
    
    // 4. 加载目录内的所有图片
    let batch = await FileOpenService.loadImageBatch(
      from: [standardizedDirectory],
      recordRecents: false,
      recursive: appSettings.imageScanRecursively,
      securityScopedInputs: scopedInputs
    )
    applyImageBatch(batch)
  }
}
```

### 用途
- 当用户从外部应用打开单个图片时
- 自动加载该图片所在目录的所有同级图片
- 允许用户在该目录内浏览

### 调用时机
- **文件**: ContentView.swift, L126
- 通过 WindowCommandHandlers 触发:
```swift
openResolvedURL: { url in openResolvedURL(url) }
```

---

## 6. 图片排序和去重

### 排序逻辑
- **文件**: ImageDiscovery.swift, L94-113
- **排序规则**:
  1. 按目录路径（本地化标准比较）排序
  2. 同目录内按文件名排序
  3. 相同名称按原始顺序排序（稳定排序）

```swift
let sortedStable = enumerated.sorted { lhs, rhs in
  let (li, l) = lhs
  let (ri, r) = rhs
  let lDir = l.deletingLastPathComponent().path
  let rDir = r.deletingLastPathComponent().path
  
  if lDir != rDir {
    return lDir.localizedStandardCompare(rDir) == .orderedAscending
  }
  
  let lName = l.lastPathComponent
  let rName = r.lastPathComponent
  let nameOrder = lName.localizedStandardCompare(rName)
  if nameOrder != .orderedSame {
    return nameOrder == .orderedAscending
  }
  
  return li < ri  // 稳定排序
}.map { $0.1 }
```

### 去重逻辑
- **ImageDiscovery.swift, L83-92**:
```swift
var seen: Set<String> = []
var unique: [URL] = []
unique.reserveCapacity(collected.count)
for url in collected {
  let key = url.standardizedFileURL.path
  if !seen.contains(key) {
    seen.insert(key)
    unique.append(url)
  }
}
```
- 按标准化路径进行去重

---

## 7. 关键文件总结表

| 功能 | 文件路径 | 关键类/函数 |
|------|--------|----------|
| 设置管理 | Models/AppSettings.swift | AppSettings |
| 文件打开 | Models/FileOpenService.swift | FileOpenService |
| 图片发现 | Models/ImageDiscovery.swift | ImageDiscovery |
| 内容视图 | ContentView/ContentView.swift | ContentView |
| 图片管理 | ContentView/ContentView+ImageManagement.swift | applyImageBatch, openResolvedURL |
| 侧边栏 | Views/SidebarView.swift | SidebarView |
| 详情页 | Views/DetailView.swift | DetailView |
| 显示设置 | Views/Settings/DisplaySettingsView.swift | DisplaySettingsView |

---

## 8. 设置项命名规范

### UserDefaults 键命名
- 使用驼峰命名法，首字母小写
- 用途相关的名称
- 示例:
  - `zoomModifierKey` - 缩放修饰键
  - `panModifierKey` - 拖拽修饰键
  - `imageScanRecursively` - 递归扫描
  - `showMinimap` - 显示小地图
  - `zoomSensitivity` - 缩放灵敏度

### JSON 存储的设置
- 使用 `xxxJSON` 后缀表示
- 示例:
  - `imageNavigationOptionsJSON` - 导航快捷键选项
  - `deleteShortcutOptionsJSON` - 删除快捷键选项
  - `customCropRatiosJSON` - 自定义裁剪比例

---

## 9. 安全作用域管理

### 概念
- macOS 沙盒应用需要用户授予访问权限
- `SecurityScopedAccessGroup` 管理这些权限令牌

### 核心类
- **文件**: ContentView+ImageManagement.swift, L138-209
- **功能**:
  - `init(urls:)` - 初始化并保存权限
  - `extend(with:)` - 添加新的权限
  - `canAccess(_:)` - 检查是否有权限
  - `hasDeletePermission(for:)` - 检查删除权限
  - `withScopedAccess(to:perform:)` - 在权限作用域内执行操作

---

## 10. 流程图总结

### 打开图片流程
```
用户打开文件/拖放
    ↓
openFileOrFolder() / handleDropProviders()
    ↓
FileOpenService.openFileOrFolder() / processDropProviders()
    ↓
FileOpenService.loadImageBatch()
    ↓
ImageDiscovery.computeImageURLs() (应用递归设置)
    ↓
排序 + 去重 + Finder风格排序
    ↓
返回 ImageBatch
    ↓
applyImageBatch()
    ↓
更新 imageURLs 状态
    ↓
SidebarView 显示缩略图列表
```

### 设置应用流程
```
用户在 DisplaySettingsView 改变 imageScanRecursively
    ↓
@AppStorage 自动保存到 UserDefaults
    ↓
下次打开文件时调用 openFileOrFolder(recursive: appSettings.imageScanRecursively)
    ↓
FileOpenService.resolvedRecursiveFlag() 读取设置值
    ↓
ImageDiscovery 根据递归标志枚举文件
```

