-- SoloLeveling Library portal — schema and row-level security
-- Project: xqrmsbfbtvfgfgnbsflh
--
-- Paste the whole file into the Supabase SQL editor and run it once. It is
-- idempotent: re-running drops and recreates the policies rather than erroring.
--
-- The design question this file answers is NOT "can a viewer read the code" —
-- a viewer must read the code, that is what Copy code is for. It is "can a
-- viewer read ALL the code in one request", and the answer here is no.
--
--   components          catalogue only. A signed-in user may select all 969.
--                       Nothing in this table is the deliverable.
--   component_sources   the actual code and prompts. A viewer has NO select
--                       policy on this table at all — not a restricted one, none.
--   get_source()        the only way a viewer reaches a snippet. One component
--                       per call, authenticated, rate limited, and logged before
--                       it returns.
--
-- So bulk extraction is not a single `select *`; it is 942 separate calls under
-- a named account against an hourly ceiling, which is a thing you can see and
-- revoke. That is the whole protection model, and it is server-side — which is
-- why it works where a right-click block does not.

-- ---------------------------------------------------------------------------
-- 1. roles
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.app_role as enum ('admin', 'viewer');
exception when duplicate_object then null;
end $$;

create table if not exists public.profiles (
  id         uuid primary key references auth.users on delete cascade,
  email      text,
  role       public.app_role not null default 'viewer',
  created_at timestamptz not null default now()
);

-- Every new signup lands as 'viewer'. Admin is granted by hand, deliberately:
-- a default that could be self-assigned is not a role, it is a suggestion.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, role)
  values (new.id, new.email, 'viewer')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- security definer so the function reads profiles with RLS bypassed. Without
-- that, a policy ON profiles that queries profiles recurses infinitely — the
-- single most common way a Supabase RLS setup locks itself out.
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- ---------------------------------------------------------------------------
-- 2. the catalogue
-- ---------------------------------------------------------------------------

create table if not exists public.components (
  id           text primary key,              -- 'hero-split-reveal'
  library      text not null,                 -- db | builders | motion
  name         text not null,
  section      text,
  descr        text,
  deps         text[] not null default '{}',  -- ['three','gsap'] — the paste gate
  ship         text not null default 'yes',   -- yes | cond | no
  licence      text,                          -- the line that decides
  origin       text,                          -- provenance, kept even when the
                                              -- display name is ours
  preview_html text,                          -- the CSS sketch. Safe in bulk:
                                              -- it is a drawing of the thing,
                                              -- not the thing
  open_url     text,                          -- for the 27 builders, which are
                                              -- whole tools rather than snippets
  has_source   boolean not null default false,
  code_bytes   int,
  created_at   timestamptz not null default now()
);

create index if not exists components_library_idx on public.components (library);
create index if not exists components_section_idx on public.components (section);

-- ---------------------------------------------------------------------------
-- 3. the part worth gating
-- ---------------------------------------------------------------------------

create table if not exists public.component_sources (
  component_id text primary key references public.components(id) on delete cascade,
  code         text,
  prompt       text
);

-- ---------------------------------------------------------------------------
-- 4. the audit trail
-- ---------------------------------------------------------------------------

create table if not exists public.copy_log (
  id           bigserial primary key,
  user_id      uuid references auth.users on delete set null,
  component_id text,
  kind         text not null,                 -- code | prompt
  at           timestamptz not null default now()
);

create index if not exists copy_log_user_at_idx on public.copy_log (user_id, at desc);

-- ---------------------------------------------------------------------------
-- 5. row-level security
-- ---------------------------------------------------------------------------

alter table public.profiles          enable row level security;
alter table public.components        enable row level security;
alter table public.component_sources enable row level security;
alter table public.copy_log          enable row level security;

-- profiles: you see yourself, an admin sees everyone, nobody self-promotes
drop policy if exists profiles_self_read  on public.profiles;
drop policy if exists profiles_admin_read on public.profiles;
drop policy if exists profiles_admin_all  on public.profiles;

create policy profiles_self_read on public.profiles
  for select to authenticated using (id = auth.uid());
create policy profiles_admin_read on public.profiles
  for select to authenticated using (public.is_admin());
create policy profiles_admin_all on public.profiles
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- components: any signed-in user browses the catalogue; only an admin edits it.
-- No policy for anon, so a logged-out request returns zero rows — not an error
-- page you could screenshot past, just nothing.
drop policy if exists components_read      on public.components;
drop policy if exists components_admin_all on public.components;

create policy components_read on public.components
  for select to authenticated using (true);
create policy components_admin_all on public.components
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- component_sources: ADMIN ONLY, and that is the point. A viewer has no select
-- policy here, so `select * from component_sources` returns zero rows for them
-- no matter how it is called. The only door is get_source() below.
drop policy if exists sources_admin_all on public.component_sources;

create policy sources_admin_all on public.component_sources
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- copy_log: a user may see their own history and nothing else; an admin sees all.
-- Inserts come from get_source(), not from the client, so there is no insert
-- policy for a user to forge a row with.
drop policy if exists copylog_self_read  on public.copy_log;
drop policy if exists copylog_admin_read on public.copy_log;

create policy copylog_self_read on public.copy_log
  for select to authenticated using (user_id = auth.uid());
create policy copylog_admin_read on public.copy_log
  for select to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------------
-- 6. the only way a viewer gets a snippet
-- ---------------------------------------------------------------------------

create or replace function public.get_source(cid text, kind text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  body  text;
  tally int;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if kind not in ('code', 'prompt') then
    raise exception 'kind must be code or prompt' using errcode = '22023';
  end if;

  -- A person choosing components does not need 200 an hour. A scraper does.
  -- Admins are exempt: a bulk export is a thing the owner is allowed to do.
  if not public.is_admin() then
    select count(*) into tally
    from public.copy_log
    where user_id = auth.uid() and at > now() - interval '1 hour';

    if tally >= 150 then
      raise exception 'hourly copy limit reached — try again later'
        using errcode = '53400';
    end if;
  end if;

  select case when kind = 'prompt' then s.prompt else s.code end
    into body
  from public.component_sources s
  where s.component_id = cid;

  if body is null then
    raise exception 'no source for %', cid using errcode = '02000';
  end if;

  -- Logged BEFORE the return, so a client that drops the response still leaves
  -- the fetch on the record. The log is the deterrent, not the limit.
  insert into public.copy_log (user_id, component_id, kind)
  values (auth.uid(), cid, kind);

  return body;
end;
$$;

revoke all on function public.get_source(text, text) from public, anon;
grant execute on function public.get_source(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. what an admin wants to see
-- ---------------------------------------------------------------------------

create or replace view public.copy_activity as
  select l.at, p.email, l.component_id, c.library, c.name, l.kind
  from public.copy_log l
  left join public.profiles   p on p.id = l.user_id
  left join public.components c on c.id = l.component_id
  order by l.at desc;

-- A Postgres view runs as its OWNER unless told otherwise, which means it reads
-- the underlying tables with RLS bypassed -- so without this line a viewer could
-- select straight out of copy_activity and read every account's email and whole
-- copy history, past all four policies above. security_invoker makes the view
-- read as the CALLER instead, so the copy_log and profiles policies apply: a
-- viewer sees their own rows, an admin sees everyone's. No extra policy needed.
alter view public.copy_activity set (security_invoker = on);
