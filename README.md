## Picser

Picser [`/ˈpɪksər/`] 是一款 macOS 系统上的看图软件，主打简约、原生、轻量、好用。

### 👨‍💻 技术栈

它使用 Swift/SwiftUI 原生开发。

### 开发
#### 环境变量
- `PICSER_IAP_LIFETIME_ID`：覆盖默认的一次性买断商品 ID。若不配置，代码会使用 PurchaseSecretsProvider.defaultLifetimeIdentifier。
- `PICSER_IAP_SUBSCRIPTION_ID`：覆盖默认的订阅商品 ID。若不配置，代码会使用 PurchaseSecretsProvider.defaultSubscriptionIdentifier。
- `PICSER_IAP_SHARED_SECRET`：用于收据验证的共享密钥。默认可为空。
- `PICSER_ENABLE_RECEIPT_VALIDATION`：是否启用收据校验（1 表示开启，其它或缺省表示关闭）。

> 本地调试如何设置环境变量

在 Xcode 中操作最方便：
1. 选中 Scheme → Edit Scheme → “Run” → “Arguments” → 在 “Environment Variables” 区域新增上述变量。
2. 也可以在终端运行前 `export PICSER_IAP_LIFETIME_ID=com.soyotube.Picser.full`、`export PICSER_IAP_SUBSCRIPTION_ID=com.soyotube.Picser.pro.yearly` 等，然后通过命令行启动 `xcodebuild` 或 `xed`。
3. 若要模拟不同场景，可临时在 Info.plist 中添加对应键值（`PICSER_IAP_LIFETIME_ID` 等），或调用 PurchaseSecretsProvider.storePurchaseSharedSecret 写入钥匙串以便调试。

> 正式发布如何设置

- 商品 ID：通常保持默认值即可，可按需分别覆盖 `PICSER_IAP_LIFETIME_ID` 与 `PICSER_IAP_SUBSCRIPTION_ID`；若需分渠道，可在构建脚本中通过 `xcodebuild` 的 `-scheme/-configuration` 搭配 `ENVVAR=value` 导出。
- 共享密钥：推荐优先写入钥匙串或在 CI/CD 环境的私密变量中设置 `PICSER_IAP_SHARED_SECRET`，避免直接硬编码在工程里。
- 收据验证开关：根据需要在打包脚本里 `export PICSER_ENABLE_RECEIPT_VALIDATION=1`，未准备好共享密钥时保持关闭。

一般做法是在 CI/CD 管线或本地打包脚本中导出这些环境变量，例如：
``` bash
export PICSER_IAP_LIFETIME_ID="com.soyotube.Picser.full"
export PICSER_IAP_SUBSCRIPTION_ID="com.soyotube.Picser.pro.yearly"
export PICSER_IAP_SHARED_SECRET="$APP_SPECIFIC_SECRET"
export PICSER_ENABLE_RECEIPT_VALIDATION=1   # 若暂不启用就省略
xcodebuild -scheme Picser -configuration Release …
```

这样开发调试、测试和正式发布都能按需切换，而本地缺省逻辑也会自动回退到默认值或钥匙串配置，无需频繁改代码。

### 打包
- 在 .env.local 文件中配置环境变量
- 依次执行以下命令：
``` bash
chmod +x scripts/build_release.sh # 给脚本执行权限（只需运行一次）
./scripts/build_release.sh Release Picser
```

### 🕒 计划清单
- [x] 鼠标按住左键移动图片
- [x] 图片缩放大小限制
- [x] 图片移动范围限制
- [x] 图片切换速度优化
- [x] 切换图片的快捷键设置
- [ ] 快捷键绑定设置
- [x] 查看图片的 EXIF 信息
- [x] 图片放大超过区域时，右下角显示缩略图
- [x] 图片翻转、镜像等功能
- [x] 图片裁剪功能，预置常用比例，且支持自定义比例并保存
- [x] 刷新文件夹展示最新图片的功能
- [ ] 图片文字 OCR 功能
- [ ] 图片播放功能
- [x] 删除图片功能，并支持自定义快捷键，支持设置是否删除前确认
- [ ] 增加 HDR 支持
- [ ] 增加格式支持，如 AVIF、JXL、TIFF、ICNS、svg、NEF（尼康）、cr3（佳能）、RAW 等等
- [ ] 区分免费版（JPEG、PNG、WebP、HEIC、GIF）和收费版（AVIF、JXL、TIFF、ICNS）的格式支持
- [ ] 增加设置项：打开单个图片时是否打开当前目录下的所有图片
- [ ] 切换到下一个目录功能
- [ ] 可以自定义图片排序规则，比如按名称、时间、格式等
- [ ] 左侧缩略图位置可自定义，如放在下方
- [ ] 旋转、翻转后的另存为功能
- [x] 支持选择图片的打开方式为当前 App
- [x] 鼠标移动到两侧边缘时，出现“上一张”、“下一张”的箭头形状的按钮，可以切换图片
- [x] 查看 EXIF 信息在 app 右侧弹出侧边栏查看，取代弹窗

### 🐞 待修复 BUG
- [x] 右侧区域没有放大的情况下，如果放大左侧缩略图区域，右侧会出现小地图
- [x] 左侧缩略图区域没有限制宽度，可以无限放大至整个 app 的宽度
- [ ] 切换到英文时，订阅项目名称依然是中文
- [x] 打开 Exif 信息弹窗的状态下，切换图片时，弹窗不会消失或者更新
- [ ] 每次打开软件时，总是弹出是否允许使用钥匙串存储的信息的弹框
- [x] 加载大体积图片时，放大后图片回弹