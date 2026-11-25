-- Read-only production acceptance: invalid rows are rejected before all writes.
select
  public.commit_pdf_rescan_batch('[{"asset_id":"bad-uuid"},{"asset_id":"","page_count":""},{"asset_id":"00000000-0000-0000-0000-000000000000","page_count":"invalid"},{"asset_id":"00000000-0000-0000-0000-000000000000","page_count":"2147483648"}]'::jsonb) =
    '{"replaced":0,"kept_existing":0,"failed":4,"designers_filled":0,"technical_designers_filled":0,"files_used_added":0}'::jsonb
  and pg_get_functiondef('public.commit_pdf_rescan_batch(jsonb)'::regprocedure) like '%public.apply_sheet_designers%'
  and pg_get_functiondef('public.commit_pdf_rescan_batch(jsonb)'::regprocedure) like '%v_old_len / 4%'
  as passed;
