-- ============================================================
-- 下班倒计时 · 公共留言墙（Supabase 云共享版）
--
-- 站长登录邮箱已预填在下面的 owner_email() 中。
-- 如果你换 Supabase 账号，只改这一处即可。
-- 站长公开 ID 固定为“站长”，前端也使用同一个值。
-- 在 Supabase 的 SQL Editor 里整段执行一次即可。
-- ============================================================

-- 站长邮箱已经预填在下面的 owner_email() 里；换账号时只改这一处。
create schema if not exists offwork_private;

create or replace function offwork_private.owner_email()
returns text
language sql
immutable
as $$ select '17337027885@163.com'::text $$;

create or replace function offwork_private.owner_public_id()
returns text
language sql
immutable
as $$ select '站长'::text $$;

-- ------------------------------------------------------------
-- 表
-- ------------------------------------------------------------

create table if not exists public.messages (
  id bigint generated always as identity primary key,
  author_id text not null,
  content text not null,
  created_at timestamptz not null default now(),
  pinned boolean not null default false,
  constraint messages_author_len check (char_length(author_id) between 2 and 16),
  constraint messages_content_len check (char_length(content) between 1 and 500)
);

-- 单独添加 / 更新，方便已经跑过旧版 SQL 的项目也补上这个约束。
alter table public.messages drop constraint if exists messages_author_clean;
alter table public.messages
add constraint messages_author_clean check (
  author_id = btrim(author_id)
  and author_id !~ '[[:space:]]'
  and author_id !~ '[[:cntrl:]]'
  and position('　' in author_id) = 0
  and position(chr(8203) in author_id) = 0
  and position(chr(160) in author_id) = 0
);

create table if not exists public.profiles (
  id text primary key,
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  last_post_at timestamptz not null default now(),
  message_count integer not null default 0
);

alter table public.profiles add column if not exists last_seen timestamptz;
update public.profiles
set last_seen = coalesce(last_seen, first_seen, now())
where last_seen is null;
alter table public.profiles alter column last_seen set default now();
alter table public.profiles alter column last_seen set not null;

create table if not exists public.banned_ids (
  id text primary key,
  created_at timestamptz not null default now()
);

create table if not exists public.settings (
  key text primary key,
  value text not null default ''
);

insert into public.settings(key, value)
values ('announcement', '')
on conflict (key) do nothing;

insert into public.settings(key, value)
values (
  'countdown',
  '{"startTime":"09:00","endTime":"18:00","lunchEnabled":true,"lunchStart":"12:00","lunchEnd":"13:00","dailySalary":300,"payday":10,"adjustPayday":true,"workdays":[1,2,3,4,5],"musicEnabled":false,"musicUrl":""}'
)
on conflict (key) do nothing;

create table if not exists public.message_reactions (
  message_id bigint not null references public.messages(id) on delete cascade,
  author_id text not null,
  emoji text not null,
  created_at timestamptz not null default now(),
  primary key (message_id, author_id, emoji),
  constraint reaction_author_len check (char_length(author_id) between 2 and 16),
  constraint reaction_emoji_ok check (emoji in ('👍', '😂', '☕', '🔥', '🎉'))
);

create index if not exists message_reactions_message_id_idx
  on public.message_reactions (message_id);

-- 统计走 security_invoker=false：以视图所有者权限计数，
-- 访客也能看到按 ID 汇总的人数，而读不到 profiles 明细。
drop view if exists public.wall_stats;
create view public.wall_stats
with (security_invoker = false) as
select
  (select count(*)::int from public.profiles) as users,
  (select count(*)::int from public.messages) as messages,
  (
    select count(*)::int
    from public.messages
    where created_at >= ((timezone('Asia/Shanghai', now()))::date::timestamp at time zone 'Asia/Shanghai')
  ) as messages_today,
  (
    select count(*)::int
    from public.profiles
    where last_seen >= ((timezone('Asia/Shanghai', now()))::date::timestamp at time zone 'Asia/Shanghai')
  ) as users_today;

-- ------------------------------------------------------------
-- 站长判断
-- ------------------------------------------------------------

create or replace function public.is_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select lower(coalesce(auth.jwt() ->> 'email', '')) = lower(offwork_private.owner_email())
$$;

-- 站长 ID 是公开的，但站长邮箱不通过数据库函数暴露给普通客户端。
grant usage on schema offwork_private to anon, authenticated;
grant execute on function offwork_private.owner_public_id() to anon, authenticated;
revoke execute on function offwork_private.owner_email() from public;
revoke execute on function offwork_private.owner_email() from anon, authenticated;
grant execute on function public.is_owner() to anon, authenticated;

-- 只让数据库策略判断某个 ID 是否被禁言，不公开整个禁言名单。
create or replace function public.is_banned(public_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.banned_ids b
    where lower(b.id) = lower(btrim(public_id))
  )
$$;

grant execute on function public.is_banned(text) to anon, authenticated;

-- 访客输入 ID 时登记到 profiles，这样“多少个 ID”包含还没留言的人。
create or replace function public.claim_identity(public_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cleaned text := btrim(public_id);
begin
  if char_length(cleaned) < 2 or char_length(cleaned) > 16 then
    raise exception 'ID 需要 2–16 个字符。' using errcode = 'P0001';
  end if;
  if cleaned ~ '[[:space:]]' or cleaned ~ '[[:cntrl:]]'
     or position('　' in cleaned) > 0 then
    raise exception 'ID 不能包含空白字符。' using errcode = 'P0001';
  end if;
  if lower(cleaned) = lower(offwork_private.owner_public_id()) and not public.is_owner() then
    raise exception '站长 ID 已保留，请使用站长入口登录。' using errcode = 'P0001';
  end if;
  if public.is_banned(cleaned) then
    raise exception '这个 ID 已被站长禁言。' using errcode = 'P0001';
  end if;

  insert into public.profiles(id, first_seen, last_seen, last_post_at, message_count)
  values (cleaned, now(), now(), 'epoch'::timestamptz, 0)
  on conflict (id) do update
    set last_seen = now();

  return jsonb_build_object('ok', true, 'id', cleaned);
end;
$$;

grant execute on function public.claim_identity(text) to anon, authenticated;

-- ------------------------------------------------------------
-- 发帖触发器
-- ------------------------------------------------------------

-- 同 ID 5 秒冷却，并用 advisory lock 串行化同一 ID 的并发写入。
create or replace function public.check_message_cooldown()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  previous timestamptz;
begin
  perform pg_advisory_xact_lock(hashtext(new.author_id)::bigint);
  select last_post_at into previous
  from public.profiles
  where id = new.author_id;

  if previous is not null and previous > now() - interval '5 seconds' then
    raise exception '留言太快了，请 5 秒后再试。' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists messages_cooldown on public.messages;
create trigger messages_cooldown
before insert on public.messages
for each row execute function public.check_message_cooldown();

-- 每条留言自动登记 / 更新 ID 的资料。
create or replace function public.touch_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles(id, first_seen, last_seen, last_post_at, message_count)
  values (new.author_id, now(), now(), now(), 1)
  on conflict (id) do update
    set last_seen = excluded.last_seen,
        last_post_at = excluded.last_post_at,
        message_count = profiles.message_count + 1;
  return new;
end;
$$;

drop trigger if exists messages_touch_profile on public.messages;
create trigger messages_touch_profile
after insert on public.messages
for each row execute function public.touch_profile();

-- 删除留言时同步减少该 ID 的留言数。
create or replace function public.untouch_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
  set message_count = greatest(message_count - 1, 0)
  where id = old.author_id;
  return old;
end;
$$;

drop trigger if exists messages_untouch_profile on public.messages;
create trigger messages_untouch_profile
after delete on public.messages
for each row execute function public.untouch_profile();

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------

alter table public.messages enable row level security;
alter table public.profiles enable row level security;
alter table public.banned_ids enable row level security;
alter table public.settings enable row level security;
alter table public.message_reactions enable row level security;

-- 消息：所有人可读、可发；只有站长可改/删。
drop policy if exists messages_public_read on public.messages;
create policy messages_public_read
on public.messages for select
using (true);

drop policy if exists messages_public_insert on public.messages;
create policy messages_public_insert
on public.messages for insert
with check (
  char_length(author_id) between 2 and 16
  and char_length(content) between 1 and 500
  and (
    lower(btrim(author_id)) <> lower(offwork_private.owner_public_id())
    or public.is_owner()
  )
  and not public.is_banned(author_id)
);

drop policy if exists messages_owner_update on public.messages;
create policy messages_owner_update
on public.messages for update
using (public.is_owner())
with check (public.is_owner());

drop policy if exists messages_owner_delete on public.messages;
create policy messages_owner_delete
on public.messages for delete
using (public.is_owner());

-- 用户资料：只有站长能看完整列表；统计数据走 wall_stats。
drop policy if exists profiles_owner_read on public.profiles;
create policy profiles_owner_read
on public.profiles for select
using (public.is_owner());

-- 禁言名单：只有站长可读/写。普通访客通过 is_banned() 判断单个 ID。
drop policy if exists banned_public_read on public.banned_ids;

drop policy if exists banned_owner_write on public.banned_ids;
create policy banned_owner_write
on public.banned_ids for all
using (public.is_owner())
with check (public.is_owner());

-- 公告：所有人可读，只有站长可写。
drop policy if exists settings_public_read on public.settings;
create policy settings_public_read
on public.settings for select
using (true);

drop policy if exists settings_owner_write on public.settings;
create policy settings_owner_write
on public.settings for all
using (public.is_owner())
with check (public.is_owner());

drop policy if exists reactions_public_read on public.message_reactions;
create policy reactions_public_read
on public.message_reactions for select
using (true);

drop policy if exists reactions_public_insert on public.message_reactions;
create policy reactions_public_insert
on public.message_reactions for insert
with check (
  char_length(author_id) between 2 and 16
  and emoji in ('👍', '😂', '☕', '🔥', '🎉')
  and (
    lower(btrim(author_id)) <> lower(offwork_private.owner_public_id())
    or public.is_owner()
  )
  and not public.is_banned(author_id)
);

drop policy if exists reactions_public_delete on public.message_reactions;
create policy reactions_public_delete
on public.message_reactions for delete
using (true);

-- ------------------------------------------------------------
-- 权限
-- ------------------------------------------------------------

grant usage on schema public to anon, authenticated;

grant select on public.messages to anon, authenticated;
-- 只允许写入这两个字段；pinned / created_at / id 不能被客户端直接伪造。
grant insert (author_id, content) on public.messages to anon, authenticated;
grant update, delete on public.messages to authenticated;

grant select on public.profiles to authenticated;
grant select on public.banned_ids to authenticated;
revoke select on public.banned_ids from anon;
grant insert, update, delete on public.banned_ids to authenticated;

grant select on public.settings to anon, authenticated;
grant insert, update, delete on public.settings to authenticated;

grant select, insert, delete on public.message_reactions to anon, authenticated;

grant select on public.wall_stats to anon, authenticated;

grant usage, select on all sequences in schema public to anon, authenticated;

-- 建完表后立刻刷新 API 缓存，避免刚执行完还提示 schema cache。
notify pgrst, 'reload schema';

-- ------------------------------------------------------------
-- 完成
-- ------------------------------------------------------------
-- 下一步：
-- 1. Authentication > Users > Add user，创建预填邮箱对应的账号并设为 Auto Confirm。
-- 2. 把 Project URL 和 anon public key 填到 index.html 顶部的 OFFWORK_CLOUD。
-- 3. 打开 index.html，在页脚“站长入口”用站长邮箱密码登录。
-- ============================================================

-- 安装联调时产生的一条测试留言；如果不存在则不会删除任何真实数据。
delete from public.messages
where id = 1
  and author_id = '??'
  and content = 'permission check';

delete from public.profiles
where id = '??'
  and message_count <= 0;
