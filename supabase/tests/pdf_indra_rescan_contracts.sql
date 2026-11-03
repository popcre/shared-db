-- #5540: isolated fixtures; all changes and function writes roll back.
BEGIN;
ALTER TABLE public.assets RENAME TO indra_contract_original_assets;
ALTER TABLE public.pdf_text_samples RENAME TO indra_contract_original_samples;
ALTER TABLE public.pdf_text_samples_backup RENAME TO indra_contract_original_backup;
ALTER TABLE public.sku_files_used RENAME TO indra_contract_original_files;
CREATE TABLE public.assets (
  id uuid PRIMARY KEY, filename text, relative_path text,
  file_type public.file_type, is_deleted boolean DEFAULT false,
  thumbnail_url text, sku text, designer_name text, technical_designer_name text
);
CREATE TABLE public.pdf_text_samples (
  asset_id uuid PRIMARY KEY, filename text NOT NULL, relative_path text NOT NULL,
  extraction_method text, extracted_text text, page_count integer, char_count integer,
  extraction_error text, thumbnail_url text, sampled_at timestamptz,
  ocr_engine text, extracted_fields jsonb, indra_rescan_at timestamptz,
  indra_rescan_outcome text, indra_rescan_error text
);
CREATE TABLE public.pdf_text_samples_backup (
  asset_id uuid PRIMARY KEY, filename text, relative_path text,
  extraction_method text, extracted_text text, page_count integer, char_count integer,
  extraction_error text, thumbnail_url text, sampled_at timestamptz
);
CREATE TABLE public.sku_files_used (
  sku text, file_name text, source text, UNIQUE (sku, file_name)
);
INSERT INTO public.assets (id, filename, relative_path, file_type, sku,
                          designer_name, technical_designer_name)
SELECT ('55400000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
       CASE WHEN n = 1 THEN 'catalog.pdf' ELSE 'tech_pack.pdf' END,
       '/stored.pdf', 'pdf'::public.file_type, 'indra-contract-' || n,
       CASE WHEN n = 3 THEN 'Original creative' ELSE ' ' END,
       CASE WHEN n = 3 THEN 'Original technical' ELSE NULL END
FROM generate_series(1, 3) n;
INSERT INTO public.pdf_text_samples
  (asset_id, filename, relative_path, extracted_text, page_count, char_count)
SELECT id, filename, relative_path, repeat('x', CASE WHEN sku = 'indra-contract-1'
       THEN 8000 ELSE 200 END), 4, CASE WHEN sku = 'indra-contract-1' THEN 8000 ELSE 200 END
FROM public.assets;
DO $contract$
DECLARE
  result jsonb;
  id1 uuid := '55400000-0000-0000-0000-000000000001';
  id2 uuid := '55400000-0000-0000-0000-000000000002';
  id3 uuid := '55400000-0000-0000-0000-000000000003';
BEGIN
  IF public.count_pdf_rescan_remaining() <> 3
     OR (SELECT count(*) FROM public.claim_pdf_rescan_batch(10)) <> 2
     OR EXISTS (SELECT 1 FROM public.claim_pdf_rescan_batch(10) WHERE id = id1) THEN
    RAISE EXCEPTION 'Claim must prefer style-guide PDFs; count must include all PDFs';
  END IF;
  result := public.commit_pdf_rescan_batch(jsonb_build_array(
    jsonb_build_object('asset_id', id2, 'extracted_text', repeat('y', 200),
      'page_count', '', 'fields', jsonb_build_object('creative_designer', 'New creative',
      'technical_designer', 'New technical', 'files_used', jsonb_build_array('Hero.psd'))),
    jsonb_build_object('asset_id', 'bad-uuid', 'extracted_text', 'bad'),
    jsonb_build_object('asset_id', id3, 'page_count', 'not-an-integer'),
    jsonb_build_object('asset_id', id3, 'page_count', '999999999999999999999'),
    jsonb_build_object('asset_id', '', 'page_count', ''),
    jsonb_build_object('asset_id', id1, 'extracted_text', repeat('z', 150)),
    jsonb_build_object('asset_id', id3, 'extracted_text', repeat('y', 200),
      'fields', jsonb_build_object('creative_designer', 'Overwrite creative',
      'technical_designer', 'Overwrite technical'))));
  IF result->>'replaced' <> '2' OR result->>'kept_existing' <> '1'
     OR result->>'failed' <> '4' THEN
    RAISE EXCEPTION 'Malformed elements must not abort valid rows: %', result;
  END IF;
  IF (SELECT count(*) FROM public.pdf_text_samples_backup) <> 3
     OR EXISTS (SELECT 1 FROM public.pdf_text_samples_backup WHERE extracted_text !~ '^x+$') THEN
    RAISE EXCEPTION 'Every original text must be backed up before replacement';
  END IF;
  IF (SELECT extracted_text FROM public.pdf_text_samples WHERE asset_id = id1) <> repeat('x', 8000)
     OR (SELECT indra_rescan_outcome FROM public.pdf_text_samples WHERE asset_id = id1) <> 'kept_existing' THEN
    RAISE EXCEPTION 'Proportionally short OCR must preserve stored text';
  END IF;
  IF EXISTS (SELECT 1 FROM public.pdf_text_samples WHERE relative_path <> '/stored.pdf'
             OR page_count <> 4 OR filename IS NULL) THEN
    RAISE EXCEPTION 'Slim payloads must preserve filename, path and page count';
  END IF;
  IF (SELECT designer_name FROM public.assets WHERE id = id2) <> 'New creative'
     OR (SELECT technical_designer_name FROM public.assets WHERE id = id2) <> 'New technical'
     OR (SELECT designer_name FROM public.assets WHERE id = id3) <> 'Original creative'
     OR (SELECT technical_designer_name FROM public.assets WHERE id = id3) <> 'Original technical'
     OR NOT EXISTS (SELECT 1 FROM public.sku_files_used WHERE sku = 'indra-contract-2'
                    AND file_name = 'Hero.psd' AND source = 'pdf_text') THEN
    RAISE EXCEPTION 'Fill only blank designers and record extracted source files';
  END IF;
  PERFORM public.commit_pdf_rescan_batch(jsonb_build_array(
    jsonb_build_object('asset_id', id2, 'extracted_text', repeat('q', 200))));
  IF (SELECT extracted_text FROM public.pdf_text_samples_backup WHERE asset_id = id2) <> repeat('x', 200)
     OR public.count_pdf_rescan_remaining() <> 0
     OR EXISTS (SELECT 1 FROM public.claim_pdf_rescan_batch(10)) THEN
    RAISE EXCEPTION 'First backup must survive retries; completed PDFs must leave queue';
  END IF;
END;
$contract$;
ROLLBACK;
