-- #4800: corpus-verified compound-word variants in expand_dam_search_queries.
-- Synthetic fixtures; the CI harness wraps the file in begin/rollback.

reset role;

insert into public.dam_search_keys (document_type, entity_id, title, path, title_key, title_tsv, search_tsv)
select 'style_group', gen_random_uuid(), t, p, lower(t), to_tsvector('simple', t), to_tsvector('simple', t || ' ' || p)
from (values
  ('Spider-Man Floor Mat', '/fixtures/4800/spider-man-mat'),
  ('Coir Doormat', '/fixtures/4800/coir-doormat'),
  ('Spider Manual', '/fixtures/4800/manual')) f(t, p);

do $$
declare
  v text[];
begin
  select array_agg(query_text) into v from public.expand_dam_search_queries('spiderman floor mat');
  if not ('spider man floor mat' = any(v)) then
    raise exception 'split variant missing: %', v;
  end if;

  select array_agg(query_text) into v from public.expand_dam_search_queries('door mat');
  if not ('doormat' = any(v)) then
    raise exception 'join variant missing: %', v;
  end if;

  select array_agg(query_text) into v from public.expand_dam_search_queries('covering');
  if 'cove ring' = any(v) or 'cover ing' = any(v) then
    raise exception 'unverified split emitted: %', v;
  end if;

  -- "Spider Manual" alone must not justify "spider man" (whole-word boundary).
  delete from public.dam_search_keys where path = '/fixtures/4800/spider-man-mat';
  select array_agg(query_text) into v from public.expand_dam_search_queries('spiderman');
  if exists (select 1 from public.dam_search_keys k where k.title ~* 'spider[^[:alnum:]]+man([^[:alnum:]]|$)')
     then return; -- corpus genuinely has the split form; nothing to assert
  end if;
  if 'spider man' = any(v) and not exists (
       select 1 from public.dam_search_synonyms where search_term = 'spiderman' and is_active) then
    raise exception 'prefix-only match emitted split: %', v;
  end if;
end $$;

-- anon may not execute the function.
do $$
begin
  if has_function_privilege('anon', 'public.expand_dam_search_queries(text)', 'execute') then
    raise exception 'anon can execute expand_dam_search_queries';
  end if;
  if not has_function_privilege('authenticated', 'public.expand_dam_search_queries(text)', 'execute') then
    raise exception 'authenticated lost execute on expand_dam_search_queries';
  end if;
end $$;
