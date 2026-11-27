-- popdam3#1430: vision_ai tags are kept but never enter the keyword tag cache.
begin;
do $t$
declare
  v_file uuid;
  v_tag_ai uuid;
  v_tag_path uuid;
  v_names text[];
  v_search text;
begin
  insert into public.style_guide_files
    (root_label, relative_path, directory_path, filename, basename_no_ext,
     file_extension, normalized_name, property_folder, style_guide_folder,
     size_bytes, modified_at, is_active)
    values ('ZZ1430', 'Contract/Vision/one.pdf', 'Contract/Vision', 'one.pdf', 'one',
            'pdf', 'one', 'Contract', 'Vision', 100, now(), true)
    returning id into v_file;
  insert into public.style_guide_tags (tag, normalized_tag, display_name, facet)
    values ('zz example hero', 'zz example hero', 'zz example hero', 'other') returning id into v_tag_ai;
  insert into public.style_guide_tags (tag, normalized_tag, display_name, facet)
    values ('zz example folder', 'zz example folder', 'zz example folder', 'other') returning id into v_tag_path;
  insert into public.style_guide_file_tags (style_guide_file_id, tag_id, source, facet, confidence, status, rule_version)
    values (v_file, v_tag_ai, 'vision_ai', 'other', 0.9, 'accepted', 'contract'),
           (v_file, v_tag_path, 'path', 'other', 1, 'accepted', 'contract');
  select tag_names, tag_search_text into strict v_names, v_search
    from public.style_guide_files where id = v_file;
  if v_names is distinct from array['zz example folder'] then
    raise exception 'unexpected cached tag names: %', v_names;
  end if;
  if v_search is distinct from 'zz example folder' then
    raise exception 'unexpected cached search text: %', v_search;
  end if;
  if not exists (select 1 from public.style_guide_file_tags where style_guide_file_id = v_file and tag_id = v_tag_ai) then
    raise exception 'vision_ai tag row was not kept';
  end if;
end
$t$;
rollback;
