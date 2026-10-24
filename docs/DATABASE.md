# Database 设计

**数据库：** PostgreSQL（Supabase）  
**权威数据：** 云端 PostgreSQL；本地 SQLite 只作缓存/队列，不是共享事实来源。

## 1. 建模原则

- 一行 `inventory_items` 代表一件实体商品，不代表一种 SKU 的数量。
- `barcode` 使用 `text` 保存，不能转整数或丢失前导零；条码不唯一。
- 位置由容器正视图格子和格内深度序号组成。容器 3×2×5 生成 6 个 cell，最多 30 件。
- 当前库存表只用于当前在库状态；新增/下架行为写入不可变的 `inventory_movements` 审计记录。
- 状态不作为永久列保存，避免午夜后过期状态过时；按日期动态计算。
- 每次 schema 改动都通过 migration，并同步更新生成的 TypeScript DB types。

## 2. 实体关系

```text
auth.users ──< store_members >── stores ──< containers ──< container_cells ──< inventory_items
                                                  stores ──< inventory_movements >── inventory_items (nullable historical ref)
```

## 3. 表结构

### `stores`

| 列 | 类型 | 规则 |
|---|---|---|
| `id` | uuid | PK，默认生成 |
| `name` | text | NOT NULL |
| `timezone` | text | NOT NULL，IANA 时区名；创建门店时要求设置 |
| `near_expiry_days` | smallint | NOT NULL，默认 2，建议 CHECK 1–30 |
| `created_at` | timestamptz | NOT NULL |

### `store_members`

| 列 | 类型 | 规则 |
|---|---|---|
| `store_id` | uuid | FK → stores，级联策略需谨慎 |
| `user_id` | uuid | FK → auth.users |
| `role` | enum/text | `owner`、`manager`、`staff` |
| `created_at` | timestamptz | NOT NULL |

主键为 `(store_id, user_id)`。授权策略通过该表判断。MVP 角色：所有成员可读本门店库存；staff 可上架/下架；manager/owner 可修改门店设置和成员。

### `containers`

| 列 | 类型 | 规则 |
|---|---|---|
| `id` | uuid | PK |
| `store_id` | uuid | FK → stores，NOT NULL |
| `name` | text | NOT NULL，建议同门店唯一 |
| `kind` | enum/text | `fridge` 或 `shelf` |
| `rows` | smallint | 正整数，限制合理上限 |
| `columns` | smallint | 正整数，限制合理上限 |
| `depth_capacity` | smallint | 每格最大商品数，正整数 |
| `is_active` | boolean | 软停用容器 |
| `created_at`, `created_by` | timestamptz, uuid | 审计字段 |

禁止在有在库商品时物理删除容器或缩小尺寸。改尺寸需验证已有格位不被截断。

### `container_cells`

| 列 | 类型 | 规则 |
|---|---|---|
| `id` | uuid | PK |
| `container_id` | uuid | FK → containers，NOT NULL |
| `row_no`, `column_no` | smallint | 从 1 开始 |
| `cell_order` | integer | 正视图行优先顺序，唯一于容器 |
| `cell_code` | text | A…Z、AA…；由稳定算法产生 |

唯一约束 `(container_id,row_no,column_no)`、`(container_id,cell_order)`、`(container_id,cell_code)`。创建容器时在同一事务中生成 `rows × columns` 行。`cell_code` 映射由服务端/domain 层共享规则生成并由数据库函数校验。

### `inventory_items`

| 列 | 类型 | 规则 |
|---|---|---|
| `id` | uuid | PK |
| `store_id` | uuid | FK → stores，冗余用于 RLS 与索引；写入时校验与容器一致 |
| `container_id` | uuid | FK → containers |
| `cell_id` | uuid | FK → container_cells |
| `depth_index` | smallint | 从 1 开始，1 为格内最前端 |
| `barcode` | text | NOT NULL，完整条码；不唯一 |
| `product_name` | text | nullable |
| `production_date` | date | NOT NULL |
| `expected_storage_days` | integer | NOT NULL，正整数 |
| `expiry_date` | date | 生成列或数据库写入列，等于 `production_date + expected_storage_days` |
| `added_at`, `added_by` | timestamptz, uuid | NOT NULL |
| `removed_at`, `removed_by` | timestamptz, uuid | 移除后保留审计引用；NULL 表示当前在库 |

索引与约束：

- 条码必须是文本，允许同码多件；常用查询索引 `(store_id, barcode)`。
- 在库位置部分唯一索引：`UNIQUE(cell_id, depth_index) WHERE removed_at IS NULL`。
- 在库查询索引 `(store_id, expiry_date) WHERE removed_at IS NULL`。
- `depth_index >= 1`、`expected_storage_days > 0`。
- 深度上限依赖关联容器的 `depth_capacity`，由数据库 RPC 校验，不能只靠客户端。
- DB 写入时验证 `store_id`、container、cell 属于同一门店/容器。

### `inventory_movements`

| 列 | 类型 | 规则 |
|---|---|---|
| `id` | uuid | PK |
| `store_id` | uuid | FK → stores，NOT NULL |
| `item_id` | uuid | 可空 FK；保留历史事件 |
| `event_type` | text | `added`、`removed`、未来扩展需 ADR |
| `barcode` | text | 当时完整条码快照 |
| `container_name`, `cell_code`, `depth_index` | text/text/smallint | 事件发生时位置快照 |
| `occurred_at`, `actor_id` | timestamptz, uuid | NOT NULL |
| `operation_id` | uuid | 客户端幂等 ID，门店范围内唯一 |

只允许通过受控 RPC 插入；普通客户端不能更新或删除历史事件。

## 4. 关键数据库操作

### `create_container(...)`

验证成员权限、尺寸和同店命名；事务内插入 container 与所有 cells；返回容器和 cell 清单。重复 operation ID 不重复创建。

### `add_inventory_item(...)`

输入容器、cell、barcode、可选名称、生产日期和预计存储天数。数据库校验门店归属、格位可用容量和输入范围，取当前最大深度 + 1，插入商品与 `added` movement。并发写同一格时锁定 cell 行或使用等效事务锁，防止超容量/重复深度。

### `remove_inventory_item(item_id, scanned_barcode, operation_id)`

数据库先锁定选中的在库商品及所在 cell，比较完整 `scanned_barcode`；不匹配立即失败且不写状态。成功时记录商品原位置快照和 movement，设置 `removed_at/removed_by`，并将深度大于目标位置的在库商品向前移动。为避免唯一索引冲突，重排可在事务内先将后续深度临时加上 `depth_capacity`，再减去 `depth_capacity + 1`。最终重新验证连续顺序并提交。所有步骤原子完成。

### `near_expiry_items` 查询 / RPC

用 `store.timezone` 得到门店本地日期，再依据 `near_expiry_days` 派生 `normal/near/expired`。不要用客户端手机时区决定门店状态。输出商品全码只供已授权客户端扫码核对；首页 UI 默认仅显示末四位。

## 5. RLS / 权限

- `stores`、`containers`、`container_cells`、`inventory_items`、`inventory_movements` 开启 RLS。
- 读策略：用户在 `store_members` 中属于对应 `store_id`。
- 写策略：直接客户端写入库存表默认关闭；通过 RPC 校验当前用户、门店成员角色与业务不变量。
- RLS 检查不能依赖客户端传入的 `store_id`；需以 `auth.uid()` 关联成员表。
- `service_role` 不进入移动 App；管理员后台/迁移才使用受控服务凭据。

## 6. 数据迁移和种子

- `supabase/migrations/` 是 schema 唯一源文件；本地运行、CI 和部署使用相同迁移。
- 开发 seed 只含虚构商品、虚构员工和固定日期；禁止复制真实门店库存到仓库。
- 每个 migration 需包含表、索引、约束、RPC、RLS 和必要 grant；PR 描述注明向前/回滚策略。
- 生产数据修复先备份并审查 SQL；不在 App 运行时自动执行任意 schema SQL。
