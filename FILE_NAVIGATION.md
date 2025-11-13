# Picser 项目文件导航地图

## 核心业务逻辑文件 (Models)

### 图片打开和发现
```
Picser/Models/FileOpenService.swift
├─ 功能: 处理文件打开、拖放、批量加载
├─ 核心函数:
│  ├─ openFileOrFolder(recursive:) → ImageBatch?
│  ├─ processDropProviders(_:recursive:) → ImageBatch?
│  ├─ loadImageBatch(from:recordRecents:recursive:) → ImageBatch
│  └─ resolvedRecursiveFlag(override:) → Bool
└─ 返回值: ImageBatch (包含排序后的图片列表)

Picser/Models/ImageDiscovery.swift
├─ 功能: 图片发现、排序、去重
├─ 核心函数:
│  └─ computeImageURLs(from:recursive:) async → [URL]
└─ 特性:
   ├─ Finder 风格排序 (目录 → 文件名)
   ├─ 稳定排序保持一致性
   └─ 去重处理 (按标准化路径)
```

### 设置管理
```
Picser/Models/AppSettings.swift (976行)
├─ 类: AppSettings: ObservableObject
├─ 设置分类:
│  ├─ 快捷键设置 (L22-90)
│  │  ├─ zoomModifierKey / panModifierKey
│  │  ├─ imageNavigationOptionsJSON (多选)
│  │  └─ deleteShortcutOptionsJSON (多选)
│  │
│  ├─ 显示设置 (L104-139)
│  │  ├─ zoomSensitivity (0.01-0.1)
│  │  ├─ zoomAnchorsToPointer
│  │  ├─ minZoomScale / maxZoomScale
│  │  └─ 验证逻辑 validateSettings()
│  │
│  ├─ 小地图设置 (L141-153)
│  │  ├─ showMinimap
│  │  └─ minimapAutoHideSeconds (0-10)
│  │
│  ├─ 幻灯片设置 (L155-188)
│  │  ├─ slideshowIntervalSeconds (1-10)
│  │  └─ slideshowLoopEnabled
│  │
│  ├─ 图片扫描设置 (L190-193)
│  │  └─ imageScanRecursively ★★★ (重点)
│  │
│  └─ 裁剪设置 (L195-202)
│     └─ customCropRatiosJSON
│
├─ 持久化方法:
│  ├─ loadImageNavigationOptions() (L389-399)
│  ├─ saveImageNavigationOptions() (L402-407)
│  ├─ loadDeleteShortcutOptions() (L410-420)
│  ├─ saveDeleteShortcutOptions() (L423-428)
│  ├─ loadCustomCropRatios() (L368-378)
│  └─ saveCustomCropRatios() (L380-385)
│
└─ 重置功能: resetToDefaults(settingsTab:) (L339-365)
```

## UI 视图文件 (Views)

### 主视图和内容
```
Picser/ContentView/ContentView.swift (主视图，696行)
├─ 核心状态 (@State):
│  ├─ imageURLs: [URL] (L20) - 所有图片列表
│  ├─ selectedImageURL: URL? (L22) - 当前选中
│  ├─ filteredImageURLs: [URL] (L61) - 过滤后的列表
│  ├─ currentSourceInputs: [URL] (L21) - 打开源
│  ├─ securityAccessGroup (L53) - 权限管理
│  └─ isCropping, imageTransform 等...
│
├─ 关键函数:
│  ├─ openFileOrFolder() (L672-679) ★ 打开文件入口
│  └─ handleDropProviders(_:) (L682-692) ★ 拖放入口
│
├─ 状态监听 (onChange):
│  ├─ imageURLs 变化 (L185-194) - 刷新过滤、侧栏
│  ├─ selectedImageURL 变化 (L195-197) - 加载 EXIF
│  └─ filteredImageURLs 变化 (L226-229) - 确保可见
│
├─ 环境对象 (@EnvironmentObject):
│  ├─ appSettings (L67) - 用户设置
│  ├─ tagService (L71) - 标签服务
│  └─ externalOpenCoordinator (L70) - 外部打开
│
└─ 子视图传参:
   ├─ SidebarView(imageURLs: visibleImageURLs, ...)
   └─ DetailView(imageURLs: visibleImageURLs, ...)

Picser/ContentView/ContentView+ImageManagement.swift (210行)
├─ 核心函数:
│  ├─ applyImageBatch(_:preserveSelection:) (L18-45)
│  │  └─ 应用新的图片批次、保持选择状态
│  ├─ refreshCurrentInputs() (L48-66)
│  │  └─ 刷新当前目录的图片列表
│  ├─ openResolvedURL(_:) (L78-114) ★★ 打开同目录图片
│  │  └─ 从外部打开时自动加载同目录
│  └─ prefetchNeighbors(around:) (L69-76)
│     └─ 预加载相邻图片
│
└─ 安全作用域管理类:
   └─ SecurityScopedAccessGroup (L138-209)
      ├─ init(urls:) - 初始化权限
      ├─ extend(with:) - 添加权限
      ├─ canAccess(_:) - 检查权限
      ├─ hasDeletePermission(for:) - 检查删除权限
      ├─ withScopedAccess(to:perform:) - 权限作用域执行
      └─ retainedURLs - 获取权限列表

Picser/Views/SidebarView.swift (138行)
├─ 组件: 左侧缩略图列表
├─ 传入参数:
│  ├─ imageURLs: [URL] - 图片列表
│  ├─ selectedImageURL: URL? - 当前选中
│  └─ onSelect: (URL) -> Void - 选中回调
│
├─ 关键逻辑:
│  ├─ ForEach(imageURLs) (L29) - 渲染缩略图
│  ├─ ThumbnailImageView - 缩略图组件
│  ├─ onChange(selectedImageURL) (L61) - 自动滚动到选中项
│  └─ onChange(imageURLs) (L64) - 列表变化处理
│
└─ 标签筛选:
   ├─ filterHeader - 筛选按钮和 Popover
   └─ TagFilterPanel - 筛选器面板

Picser/Views/DetailView.swift
├─ 组件: 右侧详情页 (显示当前选中的图片)
├─ 传入参数:
│  ├─ imageURLs: [URL] - 完整图片列表
│  ├─ selectedImageURL: URL? - 当前图片
│  └─ 各种回调函数
│
└─ 关键逻辑:
   ├─ AsyncZoomableImageContainer - 图片显示
   ├─ navigationContext - 导航状态
   └─ EdgeNavigationOverlay - 边缘导航提示
```

### 设置视图
```
Picser/Views/Settings/DisplaySettingsView.swift (147行)
├─ 页面: 显示设置
├─ 内容分组:
│  ├─ 缩放设置 (L28-83)
│  │  ├─ zoomSensitivity 滑块 (L33-44)
│  │  ├─ minZoomScale 滑块 (L46-58)
│  │  ├─ maxZoomScale 滑块 (L60-72)
│  │  └─ zoomAnchorsToPointer 开关 (L74-82)
│  │
│  ├─ 小地图设置 (L87-114)
│  │  ├─ showMinimap 开关 (L92-94)
│  │  └─ minimapAutoHideSeconds 滑块 (L96-113)
│  │
│  └─ 图片扫描设置 (L118-126) ★★★
│     └─ imageScanRecursively 开关 (L123-125)
│        关键字: "image_scan_recursive_toggle"
│
└─ 重置按钮 (L129-137)

Picser/Views/Settings/GeneralSettingsView.swift
├─ 页面: 常规设置
├─ 内容:
│  ├─ 应用语言 (appLanguage)
│  ├─ 删除确认 (deleteConfirmationEnabled)
│  ├─ 幻灯片间隔 (slideshowIntervalSeconds)
│  └─ 幻灯片循环 (slideshowLoopEnabled)
│
└─ 重置按钮

Picser/Views/Settings/SettingsView.swift
├─ 设置主窗口
├─ 标签页:
│  ├─ General - 常规设置
│  ├─ Keyboard - 键盘快捷键
│  ├─ Display - 显示设置 ★★★ (包含递归扫描)
│  ├─ Tags - 标签管理
│  ├─ Cache - 缓存管理
│  └─ About - 关于
│
└─ TabView 切换
```

## 基础设施文件 (Infrastructure)

```
Picser/Infrastructure/ExternalOpenCoordinator.swift
├─ 功能: 处理从 Finder/Dock 打开的外部文件
├─ 核心:
│  ├─ latestBatch: ImageBatch? - 最新的打开请求
│  ├─ consumeLatestBatch() - 消费一次性请求
│  └─ latestBatchPublisher - 发布者
│
└─ 集成: ContentView (L70, L240-251)

Picser/Infrastructure/KeyboardShortcutHandler.swift
├─ 功能: 处理全局键盘快捷键
└─ 与设置交互: AppSettings.imageNavigationOptions

Picser/PicserAppDelegate.swift
├─ 应用委托
└─ 系统事件处理

Picser/PicserApp.swift
├─ 应用入口
└─ 环境对象注入
```

## 工具和辅助文件 (Utilities)

```
Picser/Models/ImageLoader.swift
├─ 功能: 异步加载和缓存图片
├─ 方法:
│  ├─ loadImage(url:) - 加载单张图片
│  └─ prefetch(urls:) - 预加载图片列表
│
└─ 性能优化

Picser/Models/ExifExtractor.swift
├─ 功能: 提取图片 EXIF 元数据
└─ 集成: ContentView 的 EXIF 面板

Picser/Models/RecentOpensManager.swift
├─ 功能: 管理最近打开的文件
└─ 集成: FileOpenService 记录 recents

Picser/Models/DiskCache.swift
├─ 功能: 磁盘缓存管理
└─ 用途: 缓存缩略图等

Picser/Models/LocalizationManager.swift
├─ 功能: 多语言支持
└─ 调用: AppSettings.appLanguage 变化时
```

---

## 关键数据流向

### 1. 打开文件流
```
用户点击 File → Open / 拖拽文件
    ↓
ContentView.openFileOrFolder() (L672-679)
    ↓
FileOpenService.openFileOrFolder() (L28-46)
    ↓
FileOpenService.loadImageBatch() (L97-118)
    ↓
ImageDiscovery.computeImageURLs(recursive: appSettings.imageScanRecursively)
    ↓
排序 + 去重 + 返回 ImageBatch
    ↓
ContentView.applyImageBatch(batch)
    ↓
更新 imageURLs 状态
    ↓
onChange 监听触发 (L185-194)
    ↓
SidebarView 重新渲染缩略图列表
```

### 2. 递归设置流
```
用户在 DisplaySettingsView 改变 imageScanRecursively
    ↓
@AppStorage 自动保存到 UserDefaults["imageScanRecursively"]
    ↓
AppSettings 的 @Published var 更新
    ↓
下次打开文件时:
  ContentView.openFileOrFolder(recursive: appSettings.imageScanRecursively)
    ↓
  FileOpenService.resolvedRecursiveFlag() (L120-126)
    ↓
  返回 true/false
    ↓
  ImageDiscovery.computeImageURLs(from: inputs, recursive: true/false)
    ↓
  选择不同的枚举方式
```

### 3. 外部打开流
```
用户从 Finder/Dock 打开图片
    ↓
ExternalOpenCoordinator 捕获
    ↓
ContentView.task (L240-252)
    ↓
externalOpenCoordinator.consumeLatestBatch()
    ↓
handleExternalImageBatch(batch)
    ↓
applyImageBatch(batch)
    ↓
openResolvedURL 逻辑 (如果是单个图片)
    ↓
加载同目录所有图片
```

---

## 快速查询表

| 需要修改 | 主要文件 | 次要文件 |
|---------|--------|--------|
| 递归扫描逻辑 | ImageDiscovery.swift | FileOpenService.swift |
| 递归扫描 UI | DisplaySettingsView.swift | AppSettings.swift |
| 打开文件流程 | FileOpenService.swift | ContentView.swift |
| 图片列表显示 | SidebarView.swift | ContentView.swift |
| 图片排序规则 | ImageDiscovery.swift | - |
| 所有设置键 | AppSettings.swift (L1-200) | - |
| 安全权限 | ContentView+ImageManagement.swift | FileOpenService.swift |
| 同目录加载 | ContentView+ImageManagement.swift (L78-114) | - |

---

## 文件大小参考

```
ContentView.swift ............................ ~696 行
AppSettings.swift ........................... ~976 行
FileOpenService.swift ....................... ~128 行
ImageDiscovery.swift ........................ ~120 行
ContentView+ImageManagement.swift ........... ~210 行
SidebarView.swift ........................... ~138 行
DisplaySettingsView.swift ................... ~147 行
SecurityScopedAccessGroup ................... ~72 行 (在 ContentView+ImageManagement.swift)
```

---

**生成时间**: 2025-11-13

**相关文档**:
- PICSER_CODE_ANALYSIS.md - 详细分析
- QUICK_REFERENCE.md - 快速参考
