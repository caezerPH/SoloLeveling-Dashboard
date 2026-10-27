-- Who signed in, and when. Run after 01-schema.sql.
--
-- copy_log answers "who took something". It does not answer "who has been in",
-- because a person can browse all 969 components and copy none, and that session
-- leaves no trace at all. For a library issued under named credentials, the second
-- question is the one that gets asked first.
--
-- Supabase does keep auth.audit_log_entries internally, but it is not exposed
-- through the API and it is pruned, so it cannot be the record you rely on.

create table if not exists public.visit_log (
  id      bigserial primary key,
  user_id uuid references auth.users on delete set null,
  at      timestamptz not null default now(),
  agent   text                                   -- user agent, trimmed. Enough to
                                                 -- tell one device from another
);

create index if not exists visit_log_user_at_idx on public.visit_log (user_id, at desc);

-- Denormalised so the admin screen does not aggregate the whole log to answer
-- "when was this person last here".
alter table public.profiles add column if not exists last_seen   timestamptz;
alter table public.profiles add column if not exists visit_count int not null default 0;

alter table public.visit_log enable row level security;

drop policy if exists visitlog_self_read  on public.visit_log;
drop policy if exists visitlog_admin_read on public.visit_log;

create policy visitlog_self_read on public.visit_log
  for select to authenticated using (user_id = auth.uid());
create policy visitlog_admin_read on public.visit_log
  for select to authenticated using (public.is_admin());

-- No insert policy, deliberately. Rows arrive only through this function, so a
-- client cannot forge a visit for somebody else or backdate one.
create or replace function public.record_visit(agent text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  recent timestamptz;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  -- One row per session, not one per page load. A reload inside half an hour is
  -- the same visit; without this the log fills with noise and stops being read,
  -- which is the usual way an audit trail dies.
  select max(at) into recent
  from public.visit_log
  where user_id = auth.uid();

  if recent is null or recent < now() - interval '30 minutes' then
    insert into public.visit_log (user_id, agent)
    values (auth.uid(), left(coalesce(agent, ''), 300));

    update public.profiles
    set visit_count = visit_count + 1
    where id = auth.uid();
  end if;

  update public.profiles set last_seen = now() where id = auth.uid();
end;
$$;

revoke all on function public.record_visit(text) from public, anon;
grant execute on function public.record_visit(text) to authenticated;

-- ---------------------------------------------------------------------------
-- what the admin screen reads
-- ---------------------------------------------------------------------------

-- Both views run as the CALLER, so the policies above apply rather than being
-- bypassed. Without security_invoker a viewer could read every account's email
-- and whole history straight out of these.

create or replace view public.visitors as
  select p.email,
         p.role,
         p.last_seen,
         p.visit_count,
         p.created_at as account_created,
         (select count(*) from public.copy_log l where l.user_id = p.id) as copies
  from public.profiles p
  order by p.last_seen desc nulls last;

alter view public.visitors set (security_invoker = on);

create or replace view public.visit_activity as
  select v.at, p.email, p.role, v.agent
  from public.visit_log v
  left join public.profiles p on p.id = v.user_id
  order by v.at desc;

alter view public.visit_activity set (security_invoker = on);
