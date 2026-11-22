-- Behavioural contract tests for migration 20261225090102 (#278, #6938):
-- luna_ruling_verified promotion_basis, provenance check, and per-determination idempotency.
-- Runs inside a rolled-back transaction in Database Contract Tests.

do $contract$
declare
  v_det_id uuid := gen_random_uuid();
  v_hash text := repeat('a', 64);
  v_hash_b text := repeat('b', 64);
  v_failed boolean;
begin
  -- 1. Valid luna_ruling_verified row inserts cleanly into hts_rag.hts_rag_precedents.
  insert into hts_rag.hts_rag_precedents (
    product_family, fixture_version, prompt_version, classifier_model, verifier_model,
    extraction_version, fixture_hash, input_hash, raw_result_hash,
    proposed_hts, classification_state, operative_eligible, review_state,
    promotion_basis, promotion_policy_version, promotion_source_determination_id,
    promotion_debate_run_id, promotion_gate_result, source_environment
  ) values (
    'synthetic ceramic mug', 'luna-runtime-v1', 'legacy-hts-classifier-v1',
    'openai/gpt-6-luna-20260922', 'cbp_stored_ruling+official_hts',
    'luna-ruling-acceptance-v1', v_hash, v_hash, v_hash,
    '6912.00.44.00', 'provisional_complete', false, 'accepted',
    'luna_ruling_verified', 'luna-ruling-acceptance-v1', v_det_id,
    null, '{"passed": true, "policy_version": "luna-ruling-acceptance-v1"}'::jsonb, 'alsand'
  );

  -- 2. Duplicate luna_ruling_verified for the same source determination is rejected.
  v_failed := false;
  begin
    insert into hts_rag.hts_rag_precedents (
      product_family, fixture_version, prompt_version, classifier_model, verifier_model,
      extraction_version, fixture_hash, input_hash, raw_result_hash,
      proposed_hts, classification_state, operative_eligible, review_state,
      promotion_basis, promotion_policy_version, promotion_source_determination_id,
      promotion_debate_run_id, promotion_gate_result, source_environment
    ) values (
      'synthetic ceramic mug', 'luna-runtime-v1', 'legacy-hts-classifier-v1',
      'openai/gpt-6-luna-20260922', 'cbp_stored_ruling+official_hts',
      'luna-ruling-acceptance-v1', v_hash_b, v_hash_b, v_hash_b,
      '6912.00.44.00', 'provisional_complete', false, 'accepted',
      'luna_ruling_verified', 'luna-ruling-acceptance-v1', v_det_id,
      null, '{"passed": true, "policy_version": "luna-ruling-acceptance-v1"}'::jsonb, 'alsand'
    );
  exception when unique_violation then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'expected unique_violation for duplicate luna_ruling_verified determination';
  end if;

  -- 3. luna_ruling_verified without promotion_gate_result is rejected.
  v_failed := false;
  begin
    insert into hts_rag.hts_rag_precedents (
      product_family, fixture_version, prompt_version, classifier_model, verifier_model,
      extraction_version, fixture_hash, input_hash, raw_result_hash,
      proposed_hts, classification_state, operative_eligible, review_state,
      promotion_basis, promotion_policy_version, promotion_source_determination_id,
      promotion_debate_run_id, promotion_gate_result, source_environment
    ) values (
      'synthetic ceramic mug', 'luna-runtime-v1', 'legacy-hts-classifier-v1',
      'openai/gpt-6-luna-20260922', 'cbp_stored_ruling+official_hts',
      'luna-ruling-acceptance-v1', v_hash_b, v_hash_b, v_hash_b,
      '6912.00.44.00', 'provisional_complete', false, 'accepted',
      'luna_ruling_verified', 'luna-ruling-acceptance-v1', gen_random_uuid(),
      null, null, 'alsand'
    );
  exception when check_violation then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'expected check_violation when promotion_gate_result is null';
  end if;

  -- 4. luna_ruling_verified with non-null promotion_debate_run_id is rejected.
  v_failed := false;
  begin
    insert into hts_rag.hts_rag_precedents (
      product_family, fixture_version, prompt_version, classifier_model, verifier_model,
      extraction_version, fixture_hash, input_hash, raw_result_hash,
      proposed_hts, classification_state, operative_eligible, review_state,
      promotion_basis, promotion_policy_version, promotion_source_determination_id,
      promotion_debate_run_id, promotion_gate_result, source_environment
    ) values (
      'synthetic ceramic mug', 'luna-runtime-v1', 'legacy-hts-classifier-v1',
      'openai/gpt-6-luna-20260922', 'cbp_stored_ruling+official_hts',
      'luna-ruling-acceptance-v1', v_hash_b, v_hash_b, v_hash_b,
      '6912.00.44.00', 'provisional_complete', false, 'accepted',
      'luna_ruling_verified', 'luna-ruling-acceptance-v1', gen_random_uuid(),
      gen_random_uuid(), '{"passed": true}'::jsonb, 'alsand'
    );
  exception when check_violation then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'expected check_violation when promotion_debate_run_id is set on luna_ruling_verified';
  end if;
end
$contract$;
