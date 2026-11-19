-- ============================================================
-- 创业领导力 · 核心自检  ——  Supabase 数据库初始化
-- 在 Supabase 控制台 → SQL Editor → New query → 整段粘贴运行
-- ============================================================

-- ---------- 1. 自检记录表 ----------
create table if not exists public.runs (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  run_id     text not null,                 -- 前端生成的轮次 id（幂等键）
  taken_at   timestamptz not null,          -- 完成时间
  avg        numeric(3,2),                  -- 平均分 0.00-5.00
  grade      text,                          -- S/A/B/C/D
  total      integer,                       -- 总分（满分 190）
  payload    jsonb not null,                -- 整轮全量数据，与导出的 JSON 同构
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, run_id)
);

create index if not exists runs_user_time_idx
  on public.runs (user_id, taken_at desc);

-- ---------- 2. 未完成草稿表（跨设备续做） ----------
create table if not exists public.drafts (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  payload    jsonb not null,                -- 当前作答进度 a / n / k
  updated_at timestamptz not null default now()
);

-- ---------- 3. 行级安全：谁也别想看别人的 ----------
alter table public.runs   enable row level security;
alter table public.drafts enable row level security;

drop policy if exists "runs_select_own" on public.runs;
drop policy if exists "runs_insert_own" on public.runs;
drop policy if exists "runs_update_own" on public.runs;
drop policy if exists "runs_delete_own" on public.runs;

create policy "runs_select_own" on public.runs
  for select using (auth.uid() = user_id);
create policy "runs_insert_own" on public.runs
  for insert with check (auth.uid() = user_id);
create policy "runs_update_own" on public.runs
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "runs_delete_own" on public.runs
  for delete using (auth.uid() = user_id);

drop policy if exists "drafts_all_own" on public.drafts;
create policy "drafts_all_own" on public.drafts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------- 4. 权限收紧：匿名用户彻底摸不到这两张表 ----------
revoke all on public.runs   from anon;
revoke all on public.drafts from anon;
grant select, insert, update, delete on public.runs   to authenticated;
grant select, insert, update, delete on public.drafts to authenticated;

-- ---------- 5. updated_at 自动维护 ----------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists runs_touch on public.runs;
create trigger runs_touch before update on public.runs
  for each row execute function public.touch_updated_at();

drop trigger if exists drafts_touch on public.drafts;
create trigger drafts_touch before update on public.drafts
  for each row execute function public.touch_updated_at();

-- ============================================================
-- 验证（可选）：跑完应该看到 2 张表、RLS 都为 true
-- ============================================================
-- select tablename, rowsecurity from pg_tables where schemaname='public';
