-- supabase/seed.sql
-- 本地开发种子数据：全部为虚构商品、虚构门店、虚构员工
-- 禁止把真实门店库存或真实员工信息写入本文件
--
-- 说明：
--   * stores / containers / container_cells 无条件写入
--   * inventory_items 依赖 auth.users（added_by 非空），本地若还没有注册用户则跳过并提示
--   * 日期按 current_date 偏移生成，保证每次 reset 后都能看到 正常 / 临期 / 过期 三种状态

do $$
declare
  v_store uuid := '11111111-1111-4111-8111-111111111111';
  v_user  uuid;
  spec    record;
  v_container uuid;
  v_cell  uuid;
  r int;
  c int;
  ord int;
begin
  -- 门店：青禾便利 · 城南店
  insert into public.stores (id, name, timezone, near_expiry_days)
  values (v_store, '青禾便利 · 城南店', 'Asia/Shanghai', 2)
  on conflict (id) do nothing;

  -- 容器与格位（与 PRD 验收标准一致：3 × 2 × 5 冰柜 → 六格 A–F，每格最多 5 件）
  for spec in
    select * from (values
      ('牛奶冰柜', 'fridge'::public.container_kind, 3, 2, 5),
      ('面包货架', 'shelf'::public.container_kind,  2, 3, 4),
      ('饮料冷柜', 'fridge'::public.container_kind, 2, 2, 6)
    ) as t(name, kind, rows, cols, cap)
  loop
    insert into public.containers (store_id, name, kind, rows, columns, depth_capacity)
    values (v_store, spec.name, spec.kind, spec.rows, spec.cols, spec.cap)
    returning id into v_container;

    ord := 0;
    for r in 1..spec.rows loop
      for c in 1..spec.cols loop
        insert into public.container_cells (container_id, row_no, column_no, cell_order, cell_code)
        values (v_container, r, c, ord, public.cell_code_for(ord))
        on conflict (container_id, cell_order) do nothing;
        ord := ord + 1;
      end loop;
    end loop;
  end loop;

  -- 商品：需要至少一个本地用户作为 added_by
  select id into v_user from auth.users order by created_at limit 1;

  if v_user is null then
    raise notice 'seed: 未找到本地 auth 用户，已跳过 inventory_items 种子数据。'
      '在 Studio 注册一个用户后再执行 supabase db reset 即可补上。';
    return;
  end if;

  -- 把第一个本地用户挂成 owner，方便本地验证 RLS
  insert into public.store_members (store_id, user_id, role)
  values (v_store, v_user, 'owner')
  on conflict (store_id, user_id) do nothing;

  -- 牛奶冰柜 · A 格：一件过期、一件临期、一件正常
  select cc.id into v_cell
  from public.container_cells cc
  join public.containers c on c.id = cc.container_id
  where c.store_id = v_store and c.name = '牛奶冰柜' and cc.cell_code = 'A';

  insert into public.inventory_items
    (store_id, container_id, cell_id, depth_index, barcode, product_name, production_date, expected_storage_days, added_by)
  select v_store, c.id, v_cell, 1, '880012340001', '鲜牛奶',
         current_date - 12, 10, v_user
  from public.containers c where c.store_id = v_store and c.name = '牛奶冰柜';

  insert into public.inventory_items
    (store_id, container_id, cell_id, depth_index, barcode, product_name, production_date, expected_storage_days, added_by)
  select v_store, c.id, v_cell, 2, '880012340002', '鲜牛奶',
         current_date - 8, 10, v_user
  from public.containers c where c.store_id = v_store and c.name = '牛奶冰柜';

  insert into public.inventory_items
    (store_id, container_id, cell_id, depth_index, barcode, product_name, production_date, expected_storage_days, added_by)
  select v_store, c.id, v_cell, 3, '880012340014', '鲜牛奶',
         current_date - 1, 10, v_user
  from public.containers c where c.store_id = v_store and c.name = '牛奶冰柜';

  -- 牛奶冰柜 · B 格：两件同条码，日期不同（验证一物一行）
  select cc.id into v_cell
  from public.container_cells cc
  join public.containers c on c.id = cc.container_id
  where c.store_id = v_store and c.name = '牛奶冰柜' and cc.cell_code = 'B';

  insert into public.inventory_items
    (store_id, container_id, cell_id, depth_index, barcode, product_name, production_date, expected_storage_days, added_by)
  select v_store, c.id, v_cell, 1, '880055660019', '酸奶',
         current_date - 9, 14, v_user
  from public.containers c where c.store_id = v_store and c.name = '牛奶冰柜';

  insert into public.inventory_items
    (store_id, container_id, cell_id, depth_index, barcode, product_name, production_date, expected_storage_days, added_by)
  select v_store, c.id, v_cell, 2, '880055660019', '酸奶',
         current_date - 2, 14, v_user
  from public.containers c where c.store_id = v_store and c.name = '牛奶冰柜';

  -- 面包货架 · A 格
  select cc.id into v_cell
  from public.container_cells cc
  join public.containers c on c.id = cc.container_id
  where c.store_id = v_store and c.name = '面包货架' and cc.cell_code = 'A';

  insert into public.inventory_items
    (store_id, container_id, cell_id, depth_index, barcode, product_name, production_date, expected_storage_days, added_by)
  select v_store, c.id, v_cell, 1, '690001220078', '全麦吐司',
         current_date - 5, 7, v_user
  from public.containers c where c.store_id = v_store and c.name = '面包货架';

  insert into public.inventory_items
    (store_id, container_id, cell_id, depth_index, barcode, product_name, production_date, expected_storage_days, added_by)
  select v_store, c.id, v_cell, 2, '690002220003', '牛角包',
         current_date - 1, 5, v_user
  from public.containers c where c.store_id = v_store and c.name = '面包货架';

  raise notice 'seed: 已写入门店、3 个容器与示例商品。';
end $$;
