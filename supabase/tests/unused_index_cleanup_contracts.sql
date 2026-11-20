begin;
select plan(7);

select ok(to_regclass('public.idx_assets_full_text_search') is null, 'idx_assets_full_text_search removed');
select ok(to_regclass('public.idx_sgf_directory_path_trgm') is null, 'idx_sgf_directory_path_trgm removed');
select ok(to_regclass('public.idx_style_guide_files_tag_search_trgm') is null, 'idx_style_guide_files_tag_search_trgm removed');
select ok(to_regclass('public.idx_assets_tags') is not null, 'assets tag index retained');
select ok(to_regclass('public.idx_style_guide_file_tags_tag_status') is not null, 'style guide tag-status index retained');
select ok(to_regclass('public.idx_assets_ai_tag_untagged_candidates') is not null, 'AI tag candidate index retained');
select ok(to_regclass('public.dam_search_embedding_claim_idx') is not null, 'DAM claim index retained');

select * from finish();
rollback;
