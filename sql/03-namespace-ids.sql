-- Namespace the primary key by library. Run after 01 and 02, then re-import.
--
-- The bug this fixes: component ids are unique WITHIN a library and not across
-- them. 'pricing-table' is a studio builder slug and also a BrewedOps motion card
-- id, so the upsert treated them as the same row and the second write silently
-- replaced the first. 969 rows went in, 968 came out, and nothing errored -- the
-- only visible symptom was a count that was one short.
--
-- Renaming the one collision would work until the next one. The ids are simply
-- not globally unique, so the key has to say which library it belongs to:
--
--   db:comparison-table--matrix
--   builders:pricing-table
--   motion:pricing-table
--
-- slug keeps the original, for links and for matching back to the files on disk.

alter table public.components add column if not exists slug text;

create index if not exists components_slug_idx on public.components (slug);

-- Clear the half-merged load. Safe: component_sources cascades, and copy_log has
-- no rows yet, so nothing references these. The import that follows is the real
-- source of truth.
delete from public.components;

-- After re-importing, both of these should hold:
--   select count(*) from public.components;                  -- 969
--   select library, count(*) from public.components
--     group by library;                                      -- db 226, builders 27, motion 716
--   select count(*) from public.components where slug is null;-- 0
