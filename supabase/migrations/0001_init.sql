-- 0001_init.sql
-- 临期宝 LastCall 初始 schema
-- 对齐 docs/DATABASE.md 与 docs/DEVELOPMENT_CONSTITUTION.md §1 产品不变量
--
-- 约定：
--   * 一行 inventory_items = 一件实体商品，不是 SKU 数量
--   * barcode 以 text 保存，允许同码多件，不是唯一键
--   * rows × columns = 正视图格数；depth_capacity = 每格纵深容量
--   * 状态（normal / near / expired）不落库，按门店时区与 near_expiry_days 动态派生
--   * 库存写入只经由 security definer RPC；客户端直写被 RLS 拒绝

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- 枚举
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.store_role as enum ('owner', 'manager', 'staff');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.container_kind as enum ('fridge', 'shelf');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.inventory_movement_type as enum ('added', 'removed');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 工具函数：以 auth.uid() 关联 store_members，RLS 不信任客户端传入的 store_id
-- ---------------------------------------------------------------------------

create or replace function public.user_store_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select sm.store_id
  from public.store_members sm
  where sm.user_id = auth.uid();
$$;

create or replace function public.user_role_for(p_store_id uuid)
returns public.store_role
language sql
stable
security definer
set search_path = public
as $$
  select sm.role
  from public.store_members sm
  where sm.user_id = auth.uid()
    and sm.store_id = p_store_id
  limit 1;
$$;

-- 可上架 / 下架：所有门店成员
create or replace function public.can_operate_inventory(p_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.store_members sm
    where sm.user_id = auth.uid()
      and sm.store_id = p_store_id
  );
$$;

-- 可改门店设置与成员：manager / owner
create or replace function public.can_manage_store(p_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.store_members sm
    where sm.user_id = auth.uid()
      and sm.store_id = p_store_id
      and sm.role in ('owner', 'manager')
  );
$$;

-- Excel 风格格子编码：0 -> A, 25 -> Z, 26 -> AA, 27 -> AB
create or replace function public.cell_code_for(p_order integer)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  n integer := p_order;
  s text := '';
begin
  if p_order is null or p_order < 0 then
    return null;
  end if;
  loop
    s := chr(ascii('A') + (n % 26)) || s;
    n := n / 26 - 1;
    exit when n < 0;
  end loop;
  return s;
end;
$$;

-- ---------------------------------------------------------------------------
-- 表
-- ---------------------------------------------------------------------------

create table if not exists public.stores (
  id               uuid primary key default extensions.gen_random_uuid(),
  name             text not null,
  timezone         text not null,
  near_expiry_days smallint not null default 2 check (near_expiry_days between 1 and 30),
  created_at       timestamptz not null default now()
);

create table if not exists public.store_members (
  store_id   uuid not null references public.stores (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  role       public.store_role not null default 'staff',
  created_at timestamptz not null default now(),
  primary key (store_id, user_id)
);

create table if not exists public.containers (
  id             uuid primary key default extensions.gen_random_uuid(),
  store_id       uuid not null references public.stores (id) on delete cascade,
  name           text not null,
  kind           public.container_kind not null,
  rows           smallint not null check (rows between 1 and 26),
  columns        smallint not null check (columns between 1 and 26),
  depth_capacity smallint not null check (depth_capacity between 1 and 200),
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  created_by     uuid references auth.users (id),
  -- rows × columns 上限 26 × 26，保证 cell_code 生成稳定
  constraint containers_grid_limit check (rows * columns <= 676)
);

create table if not exists public.container_cells (
  id           uuid primary key default extensions.gen_random_uuid(),
  container_id uuid not null references public.containers (id) on delete cascade,
  row_no       smallint not null check (row_no >= 1),
  column_no    smallint not null check (column_no >= 1),
  cell_order   integer not null check (cell_order >= 0),
  cell_code    text not null,
  constraint container_cells_unique_position unique (container_id, row_no, column_no),
  constraint container_cells_unique_order unique (container_id, cell_order),
  constraint container_cells_unique_code unique (container_id, cell_code)
);

create index if not exists container_cells_container_idx
  on public.container_cells (container_id);

create table if not exists public.inventory_items (
  id                    uuid primary key default extensions.gen_random_uuid(),
  store_id              uuid not null references public.stores (id) on delete cascade,
  container_id          uuid not null references public.containers (id) on delete cascade,
  cell_id               uuid not null references public.container_cells (id) on delete cascade,
  depth_index           smallint not null check (depth_index >= 1),
  barcode               text not null,
  product_name          text,
  production_date       date not null,
  expected_storage_days integer not null check (expected_storage_days > 0),
  expiry_date           date not null,
  added_at              timestamptz not null default now(),
  added_by              uuid not null references auth.users (id),
  removed_at            timestamptz,
  removed_by            uuid references auth.users (id)
);

-- 在库位置唯一：一格内同一深度只能有一件在库商品
create unique index if not exists inventory_items_slot_unique
  on public.inventory_items (cell_id, depth_index)
  where removed_at is null;

create index if not exists inventory_items_store_expiry_idx
  on public.inventory_items (store_id, expiry_date)
  where removed_at is null;

create index if not exists inventory_items_store_barcode_idx
  on public.inventory_items (store_id, barcode);

create index if not exists inventory_items_cell_idx
  on public.inventory_items (cell_id)
  where removed_at is null;

-- 过期日 = 生产日 + 预计存储天数（生产当天为第 0 天）
create or replace function public.set_expiry_date()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.expiry_date := new.production_date + new.expected_storage_days;
  return new;
end;
$$;

drop trigger if exists inventory_items_set_expiry on public.inventory_items;
create trigger inventory_items_set_expiry
  before insert or update of production_date, expected_storage_days
  on public.inventory_items
  for each row execute function public.set_expiry_date();

create table if not exists public.inventory_movements (
  id             uuid primary key default extensions.gen_random_uuid(),
  store_id       uuid not null references public.stores (id) on delete cascade,
  item_id        uuid references public.inventory_items (id) on delete set null,
  event_type     public.inventory_movement_type not null,
  barcode        text not null,
  container_name text not null,
  cell_code      text not null,
  depth_index    smallint not null check (depth_index >= 1),
  occurred_at    timestamptz not null default now(),
  actor_id       uuid not null references auth.users (id),
  operation_id   uuid not null,
  -- 客户端幂等 ID：同一门店内不可重复
  constraint inventory_movements_operation_unique unique (store_id, operation_id)
);

create index if not exists inventory_movements_store_time_idx
  on public.inventory_movements (store_id, occurred_at desc);

create index if not exists inventory_movements_item_idx
  on public.inventory_movements (item_id);

-- ---------------------------------------------------------------------------
-- 业务不变量：门店 / 容器 / 格位 / 商品必须同属一条链
-- ---------------------------------------------------------------------------

create or replace function public.assert_container_belongs_to_store(
  p_container_id uuid,
  p_store_id uuid
) returns void
language plpgsql
stable
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.containers c
    where c.id = p_container_id and c.store_id = p_store_id
  ) then
    raise exception 'container % does not belong to store %', p_container_id, p_store_id
      using errcode = '42501';
  end if;
end;
$$;

create or replace function public.assert_cell_belongs_to_container(
  p_cell_id uuid,
  p_container_id uuid
) returns void
language plpgsql
stable
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.container_cells cc
    where cc.id = p_cell_id and cc.container_id = p_container_id
  ) then
    raise exception 'cell % does not belong to container %', p_cell_id, p_container_id
      using errcode = '42501';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC：create_container
-- ---------------------------------------------------------------------------

create or replace function public.create_container(
  p_store_id uuid,
  p_name text,
  p_kind public.container_kind,
  p_rows smallint,
  p_columns smallint,
  p_depth_capacity smallint,
  p_operation_id uuid default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_container_id uuid;
  r smallint;
  c smallint;
  v_order integer := 0;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if not public.can_operate_inventory(p_store_id) then
    raise exception 'not a member of store %', p_store_id using errcode = '42501';
  end if;

  if p_name is null or btrim(p_name) = '' then
    raise exception 'container name is required' using errcode = '22023';
  end if;
  if p_rows < 1 or p_columns < 1 or p_depth_capacity < 1 then
    raise exception 'invalid container dimensions' using errcode = '22023';
  end if;
  if p_rows * p_columns > 676 then
    raise exception 'container grid too large' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.containers c
    where c.store_id = p_store_id and c.name = btrim(p_name) and c.is_active
  ) then
    raise exception 'container name already used in this store' using errcode = '23505';
  end if;

  insert into public.containers (store_id, name, kind, rows, columns, depth_capacity, created_by)
  values (p_store_id, btrim(p_name), p_kind, p_rows, p_columns, p_depth_capacity, auth.uid())
  returning id into v_container_id;

  -- 行优先生成正视图格位；cell_code 由共享规则生成
  for r in 1..p_rows loop
    for c in 1..p_columns loop
      insert into public.container_cells (container_id, row_no, column_no, cell_order, cell_code)
      values (v_container_id, r, c, v_order, public.cell_code_for(v_order));
      v_order := v_order + 1;
    end loop;
  end loop;

  return v_container_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC：add_inventory_item
-- ---------------------------------------------------------------------------

create or replace function public.add_inventory_item(
  p_store_id uuid,
  p_container_id uuid,
  p_cell_id uuid,
  p_barcode text,
  p_production_date date,
  p_expected_storage_days integer,
  p_product_name text default null,
  p_operation_id uuid default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_id uuid;
  v_capacity smallint;
  v_depth smallint;
  v_cell_code text;
  v_container_name text;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if not public.can_operate_inventory(p_store_id) then
    raise exception 'not a member of store %', p_store_id using errcode = '42501';
  end if;

  if p_barcode is null or btrim(p_barcode) = '' then
    raise exception 'barcode is required' using errcode = '22023';
  end if;
  if p_production_date is null or p_expected_storage_days is null or p_expected_storage_days < 1 then
    raise exception 'invalid production date or storage days' using errcode = '22023';
  end if;

  perform public.assert_container_belongs_to_store(p_container_id, p_store_id);
  perform public.assert_cell_belongs_to_container(p_cell_id, p_container_id);

  select c.depth_capacity, c.name into v_capacity, v_container_name
  from public.containers c
  where c.id = p_container_id;

  select cc.cell_code into v_cell_code
  from public.container_cells cc
  where cc.id = p_cell_id;

  -- 锁定格位，防止并发写入产生重复深度
  perform 1 from public.container_cells cc where cc.id = p_cell_id for update;

  select coalesce(max(ii.depth_index), 0) + 1 into v_depth
  from public.inventory_items ii
  where ii.cell_id = p_cell_id and ii.removed_at is null;

  if v_depth > v_capacity then
    raise exception 'cell % is full (% / %)', v_cell_code, v_depth - 1, v_capacity
      using errcode = '22023';
  end if;

  insert into public.inventory_items (
    store_id, container_id, cell_id, depth_index, barcode, product_name,
    production_date, expected_storage_days, added_by
  ) values (
    p_store_id, p_container_id, p_cell_id, v_depth, btrim(p_barcode),
    nullif(btrim(coalesce(p_product_name, '')), ''),
    p_production_date, p_expected_storage_days, auth.uid()
  )
  returning id into v_item_id;

  insert into public.inventory_movements (
    store_id, item_id, event_type, barcode, container_name, cell_code, depth_index,
    actor_id, operation_id
  ) values (
    p_store_id, v_item_id, 'added', btrim(p_barcode), v_container_name, v_cell_code,
    v_depth, auth.uid(), coalesce(p_operation_id, extensions.gen_random_uuid())
  );

  return v_item_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC：remove_inventory_item
--   先锁定选中的在库商品及所在格位，完整条码必须精确匹配；
--   不匹配立即失败且不写状态。成功后记 movement、置 removed_at，
--   并把同格更深的商品向前紧凑重排（原子完成）。
-- ---------------------------------------------------------------------------

create or replace function public.remove_inventory_item(
  p_item_id uuid,
  p_scanned_barcode text,
  p_operation_id uuid default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
  v_cell_id uuid;
  v_container_id uuid;
  v_depth smallint;
  v_capacity smallint;
  v_barcode text;
  v_cell_code text;
  v_container_name text;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  -- 锁定目标商品行
  select ii.store_id, ii.cell_id, ii.container_id, ii.depth_index, ii.barcode
    into v_store_id, v_cell_id, v_container_id, v_depth, v_barcode
  from public.inventory_items ii
  where ii.id = p_item_id and ii.removed_at is null
  for update;

  if v_store_id is null then
    raise exception 'item % is not in stock', p_item_id using errcode = 'P0002';
  end if;

  if not public.can_operate_inventory(v_store_id) then
    raise exception 'not a member of store %', v_store_id using errcode = '42501';
  end if;

  -- 锁定格位，避免与并发上架交错
  perform 1 from public.container_cells cc where cc.id = v_cell_id for update;

  if p_scanned_barcode is null or btrim(p_scanned_barcode) <> v_barcode then
    raise exception 'barcode mismatch: stock unchanged' using errcode = '22023';
  end if;

  select cc.cell_code into v_cell_code from public.container_cells cc where cc.id = v_cell_id;
  select c.name, c.depth_capacity into v_container_name, v_capacity
  from public.containers c where c.id = v_container_id;

  update public.inventory_items
     set removed_at = now(), removed_by = auth.uid()
   where id = p_item_id and removed_at is null;

  -- 同格更深商品前移：先临时抬到 capacity 之上，再整体减一，绕开部分唯一索引冲突
  update public.inventory_items
     set depth_index = depth_index + v_capacity
   where cell_id = v_cell_id
     and removed_at is null
     and depth_index > v_depth;

  update public.inventory_items
     set depth_index = depth_index - (v_capacity + 1)
   where cell_id = v_cell_id
     and removed_at is null
     and depth_index > v_capacity;

  insert into public.inventory_movements (
    store_id, item_id, event_type, barcode, container_name, cell_code, depth_index,
    actor_id, operation_id
  ) values (
    v_store_id, p_item_id, 'removed', v_barcode, v_container_name, v_cell_code,
    v_depth, auth.uid(), coalesce(p_operation_id, extensions.gen_random_uuid())
  );

  return p_item_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 状态派生：按门店时区和门店统一阈值计算 normal / near / expired
-- ---------------------------------------------------------------------------

create or replace view public.inventory_item_status as
select
  ii.*,
  cc.cell_code,
  c.name as container_name,
  ((now() at time zone s.timezone)::date) as store_local_date,
  case
    when ((now() at time zone s.timezone)::date) >= ii.expiry_date then 'expired'
    when ii.expiry_date - ((now() at time zone s.timezone)::date) <= s.near_expiry_days then 'near'
    else 'normal'
  end as freshness_status,
  (ii.expiry_date - ((now() at time zone s.timezone)::date)) as days_until_expiry
from public.inventory_items ii
join public.stores s on s.id = ii.store_id
join public.container_cells cc on cc.id = ii.cell_id
join public.containers c on c.id = ii.container_id
where ii.removed_at is null;

-- 首页临期 / 过期项；完整条码仅用于已授权客户端扫码核对，UI 默认只显示末四位
create or replace function public.near_expiry_items(p_store_id uuid)
returns table (
  item_id uuid,
  barcode text,
  product_name text,
  expiry_date date,
  freshness_status text,
  days_until_expiry integer,
  container_id uuid,
  container_name text,
  cell_code text,
  depth_index smallint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    v.item_id, v.barcode, v.product_name, v.expiry_date,
    v.freshness_status, v.days_until_expiry,
    v.container_id, v.container_name, v.cell_code, v.depth_index
  from public.inventory_item_status v
  where v.store_id = p_store_id
    and v.freshness_status in ('near', 'expired')
    and public.can_operate_inventory(p_store_id)
  order by v.expiry_date asc, v.cell_code asc, v.depth_index asc;
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.stores             enable row level security;
alter table public.store_members      enable row level security;
alter table public.containers         enable row level security;
alter table public.container_cells    enable row level security;
alter table public.inventory_items    enable row level security;
alter table public.inventory_movements enable row level security;

-- stores：成员可读；仅 manager/owner 可改
drop policy if exists stores_select_member on public.stores;
create policy stores_select_member on public.stores
  for select using (id in (select public.user_store_ids()));

drop policy if exists stores_update_manager on public.stores;
create policy stores_update_manager on public.stores
  for update using (public.can_manage_store(id))
  with check (public.can_manage_store(id));

-- store_members：成员可见；仅 manager/owner 可维护
drop policy if exists store_members_select on public.store_members;
create policy store_members_select on public.store_members
  for select using (store_id in (select public.user_store_ids()));

drop policy if exists store_members_write_manager on public.store_members;
create policy store_members_write_manager on public.store_members
  for all using (public.can_manage_store(store_id))
  with check (public.can_manage_store(store_id));

-- containers：成员可读；写入只走 RPC
drop policy if exists containers_select_member on public.containers;
create policy containers_select_member on public.containers
  for select using (store_id in (select public.user_store_ids()));

drop policy if exists containers_no_direct_write on public.containers;
create policy containers_no_direct_write on public.containers
  for insert with check (false);

drop policy if exists containers_update_manager on public.containers;
create policy containers_update_manager on public.containers
  for update using (public.can_operate_inventory(store_id))
  with check (public.can_operate_inventory(store_id));

-- container_cells：随容器可见；不允许客户端直写
drop policy if exists container_cells_select_member on public.container_cells;
create policy container_cells_select_member on public.container_cells
  for select using (
    exists (
      select 1 from public.containers c
      where c.id = container_cells.container_id
        and c.store_id in (select public.user_store_ids())
    )
  );

-- inventory_items：成员可读在库与历史；写入只经 RPC
drop policy if exists inventory_items_select_member on public.inventory_items;
create policy inventory_items_select_member on public.inventory_items
  for select using (store_id in (select public.user_store_ids()));

drop policy if exists inventory_items_no_direct_insert on public.inventory_items;
create policy inventory_items_no_direct_insert on public.inventory_items
  for insert with check (false);

drop policy if exists inventory_items_no_direct_update on public.inventory_items;
create policy inventory_items_no_direct_update on public.inventory_items
  for update using (false);

drop policy if exists inventory_items_no_direct_delete on public.inventory_items;
create policy inventory_items_no_direct_delete on public.inventory_items
  for delete using (false);

-- inventory_movements：成员可读；历史事件不可改不可删
drop policy if exists inventory_movements_select_member on public.inventory_movements;
create policy inventory_movements_select_member on public.inventory_movements
  for select using (store_id in (select public.user_store_ids()));

drop policy if exists inventory_movements_no_update on public.inventory_movements;
create policy inventory_movements_no_update on public.inventory_movements
  for update using (false);

drop policy if exists inventory_movements_no_delete on public.inventory_movements;
create policy inventory_movements_no_delete on public.inventory_movements
  for delete using (false);

-- ---------------------------------------------------------------------------
-- 授权：RLS 下 authenticated 角色需要表级 grant（策略再做行级过滤）
-- ---------------------------------------------------------------------------

grant usage on schema public to authenticated;
grant select on public.stores, public.store_members, public.containers,
  public.container_cells, public.inventory_items, public.inventory_movements to authenticated;
grant update on public.stores to authenticated;
grant update on public.containers to authenticated;
grant all on public.store_members to authenticated;
grant execute on function public.create_container(uuid, text, public.container_kind, smallint, smallint, smallint, uuid) to authenticated;
grant execute on function public.add_inventory_item(uuid, uuid, uuid, text, date, integer, text, uuid) to authenticated;
grant execute on function public.remove_inventory_item(uuid, text, uuid) to authenticated;
grant execute on function public.near_expiry_items(uuid) to authenticated;
grant execute on function public.cell_code_for(integer) to authenticated;
