-- Two columns, closing the two visible gaps in the portal. Run after 03, re-import.
--
-- has_prompt
--   The 27 builders have an index.html but no .txt prompt file. The grid showed a
--   "Copy prompt" button for anything with a source, so for those it offered a
--   button that could only fail. Presence of code and presence of a prompt are
--   separate facts and now each has its own flag.
--
-- thumb
--   The 716 motion cards render "No preview" because only the 226 DB components
--   have a hand-drawn sketch. This holds the storage path of a generated
--   screenshot instead.
--
--   Why a screenshot and not an iframe of the snippet: an iframe needs the code,
--   and shipping the code to draw a thumbnail would hand over all 716 components
--   to anyone who opened the grid -- which is the whole thing the gate exists to
--   prevent. A picture of a component is not the component.

alter table public.components add column if not exists has_prompt boolean not null default false;
alter table public.components add column if not exists thumb      text;

-- The builders stop being an outbound link. Their index.html becomes their source,
-- served through get_source() like every other component, so the dead
-- "Open builder" href goes away rather than being pointed somewhere else.
update public.components set open_url = null where library = 'builders';

-- ---------------------------------------------------------------------------
-- thumbnail storage
-- ---------------------------------------------------------------------------
-- PRIVATE bucket, deliberately. A public bucket would serve every thumbnail to
-- anyone holding the URL, and 716 of these are screenshots of BrewedOps' work --
-- their licence covers using the cards, not republishing their visuals openly.
-- The portal mints short-lived signed URLs for a signed-in session instead.

insert into storage.buckets (id, name, public)
values ('thumbs', 'thumbs', false)
on conflict (id) do update set public = false;

drop policy if exists thumbs_read  on storage.objects;
drop policy if exists thumbs_write on storage.objects;

create policy thumbs_read on storage.objects
  for select to authenticated using (bucket_id = 'thumbs');

-- Only the service key writes these, and it bypasses RLS, so no insert policy is
-- granted to any signed-in user.
create policy thumbs_write on storage.objects
  for all to authenticated
  using (bucket_id = 'thumbs' and public.is_admin())
  with check (bucket_id = 'thumbs' and public.is_admin());

-- After the re-import:
--   select count(*) from public.components where has_source;    -- 969
--   select count(*) from public.components where has_prompt;    -- 942
--   select count(*) from public.components where open_url is not null; -- 0
