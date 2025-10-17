# 内购流程与命名约定

本文档用于描述 Picser 内购体系在「免费版 + 订阅（含 7 天试用）+ 一次性买断」模式下的状态机、流程入口与命名规则，为后续协作与扩展提供依据。

## 状态机概览

用户在内购体系中的状态以 `PurchaseState` 表达，状态描述如下：

- `onboarding`：尚未触发试用，首次启动或未记录任何权益信息。
- `trial(active)`：正在进行 7 天试用，可访问所有高级功能。
- `trial(expired)`：试用已结束，等待用户选择订阅或买断。
- `subscriber(active)`：订阅有效期内，按周期续订；包含首期试用转正。
- `subscriber(lapsed)`：订阅过期但未取消，等待恢复或续费。
- `lifetime`：一次性买断（永久授权）。
- `revoked`：订单被退款、共享密钥验证失败或检测到异常，需要限制功能并提示用户处理。

任何状态变化都以时间、 StoreKit 事务或收据校验结果为触发条件，最终同步到本地缓存与 UI。
## 流程入口

| 入口 | 触发场景 | 对应交互 |
| --- | --- | --- |
| ContentView | 裁剪、变换等高级操作 | 弹出 `PurchaseInfoView`，展示订阅与买断方案 |
| GeneralSettingsView | 设置面板中的“购买与订阅”卡片 | 弹出 `PurchaseInfoView`，展示权益状态与升级入口 |
| AppCommands | 菜单栏操作 | 通过 `performIfEntitled` 检查权限 |
| 后台任务 | 应用启动、进入前台、交易更新 | 自动同步 StoreKit 事务与收据 |

流程要点：

1. **首次启动**：`PurchaseEntitlementStore` 检测不到记录 → 进入 `onboarding` → 自动开启试用并写入本地。
2. **试用期内**：每次拉起界面显示剩余时间横幅；用户可主动购买订阅或买断，成功后转入 `subscriber(active)` 或 `lifetime`。
3. **订阅用户**：监听 `Transaction.updates` 与 `AppStore.sync`，及时处理续订、退款、跨设备恢复。
4. **买断用户**：记录交易 ID，避免重复收费；可与订阅并存，取更高权限。
5. **过期与撤销**：试用结束或订阅到期进入 `trial(expired)` / `subscriber(lapsed)`，显示升级横幅；如检测到撤销则进入 `revoked` 并提示重新验证。

## 命名与目录约定

- `Features/Purchase/Domain`：纯领域模型与用例，统一使用 `Purchase` 前缀（如 `PurchaseState`, `PurchaseEntitlement`, `PurchaseCoordinator`）。
- `Features/Purchase/Infrastructure`：与系统或网络交互的适配层，例如 `PurchaseReceiptValidator`, `PurchaseLocalStore`, `PurchaseSecretsProvider` 包装。
- `Features/Purchase/UI`：所有 UI 组件、视图扩展、提示横幅均放在此处，命名格式 `PurchaseXXXView` 或 `Purchase+Context.swift`。
- 跨层依赖方向为 `UI → Domain → Infrastructure`；禁止反向依赖。
## 面向多 SKU 的扩展

- 在 `Domain` 中新增 `PurchaseProduct` 枚举，区分订阅、买断及未来附加包，以 `ProductFamily + Identifier` 形式存储。
- `PurchaseConfiguration`（放在 `Infrastructure`）负责读取 Info.plist、远端配置或 A/B 控制，返回有效产品集合。
- `PricingPresenter`（放在 `UI`）统一格式化价格、公示试用说明，避免视图重复处理多种组合。
- 订阅与买断并存时，`PurchaseCoordinator` 需按照优先级合并权益：`lifetime` > `subscriber(active)` > `trial(active)`。
- 收据验证需同时处理订阅收据与非消耗型商品；引入 `PurchaseReceiptValidator` 的策略模式按产品类型分派解析逻辑。

通过上述约定，可在不破坏现有代码的前提下，将未来新品类纳入同一目录结构，保持“一站式”浏览体验。
