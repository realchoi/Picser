## [2.0.0(5)] - 2025-12-14

### Added
- 新增幻灯片播放功能，支持自动循环浏览图片，让图片欣赏更便捷。（模块：SlideshowService, ContentView）
- 新增标签管理功能（需要高级订阅），可为图片添加标签以便分类、快速检索以及批量删除。（模块：TagService, TagEditorView, SidebarView）
- 新增 SVG 矢量图格式支持，可查看和浏览 SVG 文件。（模块：ImageLoader）
- 新增围绕指针缩放功能，缩放时以鼠标指针位置为中心，操作更加直观。（模块：ZoomableImageView, AppSettings）
- 新增设置项：打开单张图片时可选择是否自动加载所在目录下的所有图片。（模块：AppSettings, DisplaySettingsView）
- 新增付费功能 PRO 标识，明确区分免费与高级功能。（模块：ProBadge）
- 侧边栏新增图片切换时的滚动同步功能，当前图片始终保持可见。（模块：SidebarView）

### Changed
- 免费开放旋转、镜像功能，降低使用门槛，提升用户体验。（模块：ContentView）
- 优化图片导航快捷键与删除快捷键，现支持多选操作。（模块：KeyboardShortcutCatalog）
- 优化 EXIF 信息面板加载状态显示，增加进度指示。（模块：ExifInfoView）
- 优化图片手动及幻灯片切换时的加载状态，过渡更加平滑。（模块：DetailView, SlideshowService）
- 优化滚轮缩放事件处理，滚动响应更加自然。（模块：ZoomableImageView）

### Fixed
- 修复 EXIF 信息面板滚动时界面卡死的问题。（模块：ExifInfoView）
- 修复右键打开图片时重复创建窗口的问题。（模块：ExternalOpenCoordinator）
- 修复右键同时打开多张图片时创建多个窗口的问题，现统一在单一窗口中显示。（模块：ExternalOpenCoordinator）

### Removed
- 移除冗余的本地化语言配置，清理代码。（模块：Localizable.xcstrings）

---

## [2.0.0(5)] - 2025-12-14 (English)

### Added
- Added slideshow playback feature with auto-cycling for easier image browsing. (Module: SlideshowService, ContentView)
- Added tag management feature for categorizing images and quick retrieval (need advanced subscription). (Module: TagService, TagEditorView, SidebarView)
- Added SVG vector format support for viewing and browsing SVG files. (Module: ImageLoader)
- Added zoom-around-cursor feature, centering zoom on mouse pointer position for more intuitive operation. (Module: ZoomableImageView, AppSettings)
- Added setting option to auto-load all images in directory when opening a single image. (Module: AppSettings, DisplaySettingsView)
- Added scroll sync in sidebar when switching images, keeping the current image always visible. (Module: SidebarView)

### Changed
- Made rotate and mirror features free, lowering the barrier to entry and improving user experience. (Module: ContentView)
- Enhanced navigation and delete shortcuts to support multi-selection. (Module: KeyboardShortcutCatalog)
- Improved EXIF panel loading state with progress indicators. (Module: ExifInfoView)
- Improved loading state during manual and slideshow image transitions for smoother experience. (Module: DetailView, SlideshowService)
- Optimized scroll wheel zoom event handling for more natural response. (Module: ZoomableImageView)

### Fixed
- Fixed UI freeze when scrolling the EXIF information panel. (Module: ExifInfoView)
- Fixed duplicate window creation when opening images via right-click. (Module: ExternalOpenCoordinator)
- Fixed multiple windows opening when right-clicking to open multiple images; now displays in a single window. (Module: ExternalOpenCoordinator)

### Removed
- Removed redundant localization configurations for cleaner code. (Module: Localizable.xcstrings)

---

## [1.1.0(4)] - 2025-11-01
### Added
- 新增图片删除功能，可选择移至废纸篓或直接删除，缺少权限时会弹出完整磁盘访问引导。（模块：ContentView+Deletion, FullDiskAccessChecker）
- 新增边缘悬浮导航按钮，鼠标经过即可上一张或下一张，裁剪时会自动禁用防止误触。（模块：DetailView）
- 设置新增“关于”页，整合作者信息与第三方开源许可证合规文档。（模块：AboutView, legal/THIRD_PARTY_LICENSES.md）
- 订阅宽限期增加专属横幅，实时提示剩余权益与续费建议。（模块：SubscriptionGraceBanner）

### Changed
- 快捷键系统改用 KeyboardShortcuts 库，设置页交互与数据结构全面重构，支持多组默认键位并允许关闭删除快捷键。（模块：KeyboardShortcutCatalog, KeyboardSettingsView, AppSettings）
- 图片信息面板改为右侧抽屉式布局，加载时提供渐进式遮罩，阅读体验更稳定。（模块：DetailView, ExifInfoView）
- 设置页面引入动态尺寸与滚动容器，整理文案与购买状态描述，适配不同窗口宽度。（模块：SettingsView, GeneralSettingsView）
- 应用图标更新为液态玻璃风格并统一圆角资源，提升品牌辨识度。（模块：AppIcon）

### Fixed
- 修复大尺寸图片放大后会弹回的渲染问题，缩放交互更平顺。（模块：ZoomableImageView）
- 切换图片时自动重置裁剪状态并刷新 EXIF 详情，避免残留上一次的状态。（模块：ContentView, ExifInfoView）
- 优化裁剪手柄样式与小地图显隐逻辑，裁剪过程更易操作。（模块：ZoomableImageView+Crop）
- 解决“最近打开”菜单在缺少权限时无提示的问题，异常情况下会给出正确指引。（模块：ContentView+ImageManagement）

## [1.0.2(3)] - 2025-10-17
### Added
- 新增 Finder 右键菜单支持，可直接用 Picser 打开单张或多张图片，省去手动拖拽。（模块：ExternalOpenCoordinator）
- 新增“扫描图片时包含子目录”开关，按需快速筛选素材文件夹。（模块：AppSettings & DisplaySettingsView）
- 新增支持查看图片完整路径功能。（模块：ExifInfo & ExifInfoView）

### Changed
- 应用正式启用 Picser 品牌与图标，菜单与系统展示名称保持一致。（模块：Assets & 项目配置）
- 试用提示与购买面板改版，可直观看到已购权益与订阅状态。（模块：PurchaseInfoView）
- 界面文案改用 String Catalog 管理，多语言同步更新更精准。（模块：Languages/Localizable.xcstrings）

### Fixed
- 修复因沙盒权限导致的外部文件或拖拽打开偶发失败问题。（模块：FileOpenService）

### Performance
- 重构图片加载与缓存策略，降低内存占用并提升大图加载稳定性。（模块：ImageLoader）
- 缩略图编码按需选择 PNG 或 JPEG，透明图片预览更清晰且加载更快。（模块：ImageLoader）

### Security
- 正式版默认启用内购票据校验，保护已购用户权益。（模块：PurchaseManager）

## [1.0.1(2)] - 2025-10-10
### Fixed
- 优化多语言展示。
- 优化内购项目的获取。

## [1.0.0(1)] - 2025-10-01
### Added
- 发布 1.0.0(1) 版本
