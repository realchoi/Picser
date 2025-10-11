# 更新日志 模板（CHANGELOG_TEMPLATE.md）

遵循通用规范（参考：Keep a Changelog, 语义化版本控制 SemVer），用于记录应用每次版本发布的变更历史。

格式约定：
- 每个版本使用一级标题（## [版本号] - YYYY-MM-DD），按时间倒序排列。
- 版本号遵循语义化版本：MAJOR.MINOR.PATCH（例如：1.4.2）。
- 类别分组：Added / Changed / Fixed / Deprecated / Removed / Security / Performance / Documentation。
- 每条变更以短句开头，必要时加入简短说明或示例，尽量包含受影响模块/文件。
- 如果变更对应 PR、Issue 或提交，推荐在条目末尾包含链接：(#123, PR: #456) 或者使用完整链接。

示例：

## [1.4.2] - 2025-10-11
### Added
- 新增“快速打开”功能，支持按键 O 打开最近文件列表。（模块：OpenCoordinator）

### Changed
- 调整图片加载优先级，降低内存占用峰值。（模块：ImageLoader）

### Fixed
- 修复在无目录时主界面崩溃的问题。（PR: #789）

### Performance
- 缩短图片打开时间，达到“秒开”体验（参考：2025-01-27 性能优化记录）。

如何使用此模板（维护指南）：
1. 在每次发布前由发布负责人整理变更清单，分类到对应的节（Added/Changed/Fixed 等）。
2. 若发布为补丁（patch），只更新 Fixed/Performance 类别；若发布为小版本（minor），包含 Added/Changed/Fixed；若为大版本（major），应同时记录 Breaking Changes。
3. 日期使用 ISO 格式 YYYY-MM-DD；如果为预发布（beta/rc），在版本号后加上标签，例如：1.5.0-rc.1。
4. 保持条目简洁、面向用户，避免内部调试信息；把实现细节写在 PR 或 issue 中并在日志中链接。

常见条目模板（可复制使用）：
- Added: "- 新增 <功能描述>（模块：<模块名>，PR: #<号>）"
- Changed: "- 更新 <模块/接口> 行为，<简要说明>（详见 PR: #<号>）"
- Fixed: "- 修复 <问题描述>（受影响：<场景/平台>，PR: #<号>）"

自动化建议：
- 在 CI 中通过 commit message 或 PR 标签自动生成初步草稿（例如使用 conventional changelog 工具），发布负责人再人工校对与整理。 

版权与作者：
- 由项目维护团队维护，建议在 Release 页面与 `CHANGELOG.md` 中双写（即模板写在仓库，真正的变更写在 `CHANGELOG.md`）。

---

如果你希望，我可以：
- 把这个模板合并到现有的 `CHANGELOG.md`（覆盖或追加），
- 或把模板作为单独文件保留，并在 `README.md` 中加入引用说明。

请选择下一步操作。