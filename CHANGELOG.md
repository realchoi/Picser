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
