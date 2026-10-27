-- Looking is not taking. Run after 04.
--
-- The grid shows still screenshots, so nothing in it moves -- and half this library
-- is motion, where the movement IS the component. The obvious fix is to iframe the
-- snippet like the local dashboard does, but that needs the code for every visible
-- card, which would hand over the whole library to anyone who signs in once.
--
-- So previews are per-component and on demand, exactly like a copy, but they are
-- NOT a copy and must not be rationed like one:
--
--   get_source(cid, kind)   puts a component on the clipboard. 150/hour.
--   get_preview(cid)        renders one in a frame.           600/hour.
--
-- Both log. Browsing a library properly means opening a few dozen things, and a
-- person who hits the copy ceiling by LOOKING would rightly conclude the tool was
-- broken. Separate ceilings keep the copy limit meaningful: it is the one that
-- bounds extraction, and only copies count against it.
--
-- This is not a security boundary -- a preview hands over the same bytes a copy
-- would, and anyone who wants the code can read it out of the frame. It is an
-- accounting boundary, so the audit trail distinguishes "browsed 200 cards" from
-- "took 200 components", which are very different events to see on an account.

create or replace function public.get_preview(cid text)
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

  if not public.is_admin() then
    -- Counts previews only. A session that has copied 149 components can still
    -- browse, and a session that has previewed 599 can still copy.
    select count(*) into tally
    from public.copy_log
    where user_id = auth.uid()
      and kind = 'preview'
      and at > now() - interval '1 hour';

    if tally >= 600 then
      raise exception 'hourly preview limit reached — try again later'
        using errcode = '53400';
    end if;
  end if;

  select s.code into body
  from public.component_sources s
  where s.component_id = cid;

  if body is null then
    raise exception 'no source for %', cid using errcode = '02000';
  end if;

  insert into public.copy_log (user_id, component_id, kind)
  values (auth.uid(), cid, 'preview');

  return body;
end;
$$;

revoke all on function public.get_preview(text) from public, anon;
grant execute on function public.get_preview(text) to authenticated;

-- The admin screen counts copies, and previews would have inflated that number
-- into meaninglessness. Split them.
create or replace view public.visitors as
  select p.email,
         p.role,
         p.last_seen,
         p.visit_count,
         p.created_at as account_created,
         (select count(*) from public.copy_log l
           where l.user_id = p.id and l.kind in ('code','prompt')) as copies,
         (select count(*) from public.copy_log l
           where l.user_id = p.id and l.kind = 'preview')           as previews
  from public.profiles p
  order by p.last_seen desc nulls last;

alter view public.visitors set (security_invoker = on);
