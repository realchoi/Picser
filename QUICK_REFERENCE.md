# Picser 项目快速参考指南

## 一、文件打开的完整调用链

```
ContentView.openFileOrFolder()
    ↓ (L672-679)
FileOpenService.openFileOrFolder()
    ↓ (L28-46)
FileOpenService.loadImageBatch()
    ↓ (L97-118)
ImageDiscovery.computeImageURLs(from:recursive:)
    ↓ (L14-119)
[返回排序后的 imageURLs]
    ↓
applyImageBatch()
    ↓ (ContentView+ImageManagement.swift, L18-45)
更新 imageURLs 状态 → 触发 onChange 监听
    ↓
SidebarView 自动重新渲染缩略图列表
```

## 二、递归设置的生命周期

```
AppSettings.swift (L193)
┌─ @AppStorage("imageScanRecursively") = true (默认值)
│
DisplaySettingsView.swift (L123-125)
┌─ Toggle UI 绑定到此属性
│
ContentView.swift (L674, L685)
┌─ 打开文件时传递: openFileOrFolder(recursive: appSettings.imageScanRecursively)
│
FileOpenService.swift (L120-126)
┌─ resolvedRecursiveFlag() 解析递归标志
│   优先级: 显式传递 > UserDefaults > 默认值(true)
│
ImageDiscovery.swift (L33-49)
└─ 根据 recursive 参数选择:
   - true: fileManager.enumerator() 递归遍历
   - false: contentsOfDirectory() 仅列出当前目录
```

## 三、图片列表状态管理

### ContentView 中的关键状态变量
```swift
@State var imageURLs: [URL] = []                    // 所有图片列表
@State var selectedImageURL: URL?                   // 当前选中的图片
@State var filteredImageURLs: [URL] = []            // 标签筛选后的列表
@State var currentSourceInputs: [URL] = []          // 打开源目录
@State var currentSecurityScopedInputs: [URL] = []  // 安全作用域 URL
@State var securityAccessGroup: SecurityScopedAccessGroup?
```

### 列表更新流程
```
用户打开文件
    ↓
applyImageBatch(batch)
    ↓
imageURLs = batch.imageURLs
    ↓
onChange 触发 (L185-194)
    ↓
filteredImageURLs = imageURLs  // 初始化过滤列表
ensureSelectionVisible()
updateSidebarVisibility()
    ↓
SidebarView 重新渲染
```

## 四、设置键一览表

| 功能分类 | 键名 | 类型 | 默认值 | 存储方式 |
|---------|------|------|--------|----------|
| 快捷键 | zoomModifierKey | String | "none" | @AppStorage |
| 快捷键 | panModifierKey | String | "none" | @AppStorage |
| 快捷键 | imageNavigationOptionsJSON | String | "" | @AppStorage |
| 快捷键 | deleteShortcutOptionsJSON | String | "" | @AppStorage |
| 显示 | zoomSensitivity | Double | 0.05 | @AppStorage |
| 显示 | zoomAnchorsToPointer | Bool | true | @AppStorage |
| 显示 | minZoomScale | Double | 0.1 | @AppStorage |
| 显示 | maxZoomScale | Double | 10.0 | @AppStorage |
| 小地图 | showMinimap | Bool | true | @AppStorage |
| 小地图 | minimapAutoHideSeconds | Double | 0.0 | @AppStorage |
| 图片扫描 | imageScanRecursively | Bool | true | @AppStorage |
| 幻灯片 | slideshowIntervalSeconds | Double | 3.0 | @AppStorage |
| 幻灯片 | slideshowLoopEnabled | Bool | true | @AppStorage |
| 语言 | appLanguage | String | "system" | @AppStorage |
| 删除 | deleteConfirmationEnabled | Bool | true | @AppStorage |
| 裁剪 | customCropRatiosJSON | String | "[]" | @AppStorage |

## 五、打开外部图片 (从 Finder 或 Dock)

```
ExternalOpenCoordinator 捕获请求
    ↓
ContentView.task (L240-252)
    ↓
externalOpenCoordinator.consumeLatestBatch()
    ↓
handleExternalImageBatch(batch)
    ↓
applyImageBatch(batch)
```

**关键代码** (ContentView.swift L126):
```swift
openResolvedURL: { url in openResolvedURL(url) }
```

**函数** (ContentView+ImageManagement.swift L78-114):
```swift
func openResolvedURL(_ url: URL)
// 1. 获取图片所在目录
// 2. 查找已有权限的相关 URL
// 3. 加载目录内所有图片
// 4. 应用到视图
```

## 六、图片排序规则

**实现**: ImageDiscovery.swift (L94-113)

1. 按目录排序 (localizedStandardCompare)
2. 同目录按文件名排序
3. 相同名称保持原始顺序 (稳定排序)

示例结果:
```
/Users/eric/Pictures/Folder1/  (目录1)
  ├─ photo_001.jpg
  ├─ photo_002.jpg
/Users/eric/Pictures/Folder2/  (目录2)
  ├─ image_a.png
```

## 七、去重机制

**实现**: ImageDiscovery.swift (L83-92)

使用集合追踪已见的路径:
```swift
var seen: Set<String> = []
for url in collected {
  let key = url.standardizedFileURL.path
  if !seen.contains(key) {
    seen.insert(key)
    unique.append(url)
  }
}
```

## 八、安全作用域 (Sandbox)

**管理类**: SecurityScopedAccessGroup (ContentView+ImageManagement.swift L138-209)

关键方法:
```swift
// 初始化并获取权限
init(urls: [URL])

// 添加新权限
extend(with urls: [URL])

// 检查权限
canAccess(_ url: URL) -> Bool

// 在权限作用域内执行
withScopedAccess<T>(to url: URL, perform work: () throws -> T) -> T

// 获取持有的权限列表
var retainedURLs: [URL]
```

## 九、常见修改位置

### 添加新的用户设置
1. 在 `AppSettings.swift` 中添加 `@AppStorage` 属性
2. 在对应的设置视图中添加 UI 控件
3. 在 `resetToDefaults()` 中添加重置逻辑

示例:
```swift
// AppSettings.swift
@AppStorage("myNewSetting") var myNewSetting: Bool = true

// DisplaySettingsView.swift (或其他设置视图)
Toggle(isOn: $appSettings.myNewSetting) {
  Text(l10n: "my_new_setting_label")
}

// AppSettings.swift resetToDefaults()
case .display:
  myNewSetting = true
```

### 修改图片扫描逻辑
1. 编辑 `ImageDiscovery.computeImageURLs()`
2. 修改 `appendImages(in:)` 函数中的枚举逻辑

### 修改打开文件流程
1. 编辑 `FileOpenService` 中的相应方法
2. 或修改 `ImageDiscovery.computeImageURLs()` 的返回结果处理

## 十、调试技巧

### 查看当前打开的文件列表
```swift
print("Current images: \(imageURLs)")
print("Filtered images: \(visibleImageURLs)")
```

### 追踪设置变化
```swift
print("Recursive flag: \(appSettings.imageScanRecursively)")
```

### 检查安全作用域
```swift
if let group = securityAccessGroup {
  print("Retained URLs: \(group.retainedURLs)")
}
```

### 验证 ImageBatch
```swift
print("Input URLs: \(batch.inputs)")
print("Image URLs: \(batch.imageURLs)")
print("Count: \(batch.imageURLs.count)")
```

## 十一、性能优化要点

1. **图片预加载**: `prefetchNeighbors()` 预加载相邻图片
2. **异步加载**: 所有文件操作都在后台线程 (DispatchQueue.global)
3. **去重优化**: 使用 Set 进行 O(1) 查找
4. **稳定排序**: 保持用户预期的顺序一致性

## 十二、关键枚举和结构体

### ImageBatch
```swift
struct ImageBatch {
  let inputs: [URL]                              // 用户打开的源
  let securityScopedInputs: [URL]                // 安全作用域 URL
  let imageURLs: [URL]                           // 排序后的图片列表
  let accessGroup: SecurityScopedAccessGroup     // 权限管理器
}
```

### FilterTaskTrigger
```swift
struct FilterTaskTrigger: Equatable {
  var urlsHash: Int                    // 图片列表哈希
  var filter: TagFilter                // 标签筛选条件
  var assignmentsVersion: UUID         // 标签分配版本
}
```

---

**文档位置**: `/Volumes/pssd/Users/eric/01.HelloWord/05.macos/Picser/PICSER_CODE_ANALYSIS.md`

**更新时间**: 2025-11-13
