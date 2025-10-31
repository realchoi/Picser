# 第三方组件许可证清单

本文件用于在项目打包和发布时集中展示已集成的第三方组件及其许可证要求，便于研发、法务和审核团队追踪合规状态。

## 1. KeyboardShortcuts

- 作者：Sindre Sorhus 等贡献者
- 仓库：https://github.com/sindresorhus/KeyboardShortcuts
- 当前版本：2.4.0（revision 1aef85578fdd4f9eaeeb8d53b7b4fc31bf08fe27）
- 集成方式：Swift Package Manager（Picser.xcodeproj → Package.resolved）
- 许可证：MIT License

### 合规提示

1. 在发布的应用包中保留下方 MIT License 原文，推荐位置：`Picser.app/Contents/Resources/Legal/` 或法务规定位置。
2. 在应用内的“关于”页或帮助菜单中列出 KeyboardShortcuts 及其许可证类型。
3. 若对该依赖进行了源码修改，需在许可证文本中追加修改说明（当前版本未修改）。
4. 每次升级依赖版本后，同步更新本清单中的版本号、revision 以及许可证内容。

### License Text（原文）
```
MIT License

Copyright (c) Sindre Sorhus

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
---

后续新增第三方组件时，建议同步执行以下动作：
- 在 `legal/THIRD_PARTY_LICENSES.md` 增加新的条目和许可证全文。
- 在 `Package.resolved` 或对应依赖管理文件确认版本号与来源链接。
- 在应用内“关于”页或官网致谢清单中同步展示。
- 将变更通知 QA 与法务，确保测试包、正式包均携带最新许可证。
