-- #3682: Warner qualified-baseline publication contracts. Synthetic, rollback-only.
--
-- Withdrawal is published only by plm.finalize_wb_capture: the logical header
-- (chunk_number = 0) with the same target, a contiguous chunk set whose row total
-- equals the declared count, a matching digest chain, the shrink bound, and the
-- serialized import lock. Anything short of that must refuse and change no
-- lifecycle state. A separate publish function is deliberately absent: finalize
-- clears chunk payloads, so nothing could re-derive membership afterwards.

-- 1. Exact objects this contract depends on.
do $catalog$
declare
  v_fn regprocedure;
  v_col text;
begin
  foreach v_fn in array array[
    'plm.begin_wb_capture(text,date,text,text,integer,text,text,text)'::regprocedure,
    'plm.load_wb_chunk(uuid,integer,text,text)'::regprocedure,
    'plm.finalize_wb_capture(uuid,text,numeric)'::regprocedure,
    'plm.fail_wb_capture(uuid,text)'::regprocedure,
    'plm.sync_wb_normalized_target(uuid,text,jsonb,text,numeric)'::regprocedure
  ] loop
    if not (select prosecdef from pg_proc where oid = v_fn) then
      raise exception 'Warner capture function is no longer SECURITY DEFINER: %', v_fn;
    end if;
    if (select provolatile from pg_proc where oid = v_fn) <> 'v' then
      raise exception 'Warner capture function is no longer VOLATILE: %', v_fn;
    end if;
    if not exists (select 1 from pg_proc p, unnest(p.proconfig) c
                   where p.oid = v_fn and c like 'search_path=%') then
      raise exception 'Warner capture function lost its pinned search_path: %', v_fn;
    end if;
    if has_function_privilege('anon', v_fn, 'execute')
       or has_function_privilege('authenticated', v_fn, 'execute') then
      raise exception 'Warner capture function is executable by a client role: %', v_fn;
    end if;
  end loop;

  if to_regprocedure('plm.wb_publish_lifecycle(uuid)') is not null then
    raise exception 'a second Warner publication path exists beside finalize';
  end if;

  foreach v_col in array array['source_namespace','source_id','status','withdrawn_at','first_withdrawn_at'] loop
    if not exists (select 1 from pg_attribute
                   where attrelid = 'plm.wb_franchise'::regclass and attname = v_col and not attisdropped) then
      raise exception 'plm.wb_franchise lost lifecycle column %', v_col;
    end if;
  end loop;

  if to_regclass('plm.uq_wb_capture_one_in_flight_per_target') is null then
    raise exception 'one-in-flight-capture-per-target index is missing';
  end if;
end
$catalog$;

-- 2. Runtime locking: begin and finalize both take the shared import lock.
-- Each probe runs in a subtransaction that is deliberately aborted, which
-- releases the transaction-level advisory lock and discards the synthetic rows,
-- so the probe does not depend on how the harness wraps this file.
do $locking$
declare
  c uuid := '99999999-9999-4999-8999-000000003682';
  p text := jsonb_build_array('{"source_namespace":"q3682","source_id":"lock","label":"Synthetic Lock","identity_method":"source_id","source_url":"https://example.invalid"}'::jsonb)::text;
  h text; m text; v_held boolean;
  v_lock_sql constant text := $q$select exists (
    select 1 from pg_locks
    where locktype = 'advisory' and pid = pg_backend_pid() and objsubid = 1 and granted
      and classid::bigint = ((hashtext('plm.wb_capture_import')::bigint >> 32) & 4294967295)
      and objid::bigint = (hashtext('plm.wb_capture_import')::bigint & 4294967295))$q$;
begin
  h := encode(extensions.digest(convert_to(p,'UTF8'),'sha256'),'hex');
  m := encode(extensions.digest(convert_to(h,'UTF8'),'sha256'),'hex');

  execute v_lock_sql into v_held;
  if v_held then raise exception 'import lock already held before the begin probe'; end if;
  begin
    perform plm.begin_wb_capture('wb_franchise',date '2099-03-10','q3682-lock-begin',m,1,'synthetic','https://example.invalid',null);
    execute v_lock_sql into v_held;
    if not v_held then raise exception 'begin_wb_capture did not take the import lock'; end if;
    raise exception using errcode = 'QA682', message = 'q3682 probe rollback';
  exception when sqlstate 'QA682' then null;
  end;

  execute v_lock_sql into v_held;
  if v_held then raise exception 'import lock still held before the finalize probe'; end if;
  begin
    insert into plm.wb_capture(capture_id,chunk_number,target,status,captured_at,private_source_commit,snapshot_sha256,expected_row_count,captured_by,source_url,started_at)
    values (c,0,'wb_franchise','loading',date '2099-03-11','q3682-lock-finalize',m,1,'synthetic','https://example.invalid',now());
    insert into plm.wb_capture(capture_id,chunk_number,payload,payload_row_count,chunk_sha256)
    values (c,1,p::jsonb,1,h);
    execute v_lock_sql into v_held;
    if v_held then raise exception 'direct header insert unexpectedly holds the import lock'; end if;
    perform plm.finalize_wb_capture(c,m,1);
    execute v_lock_sql into v_held;
    if not v_held then raise exception 'finalize_wb_capture did not take the import lock'; end if;
    raise exception using errcode = 'QA682', message = 'q3682 probe rollback';
  exception when sqlstate 'QA682' then null;
  end;
end
$locking$;

-- 3. Publication behavior.
begin;
do $publication$
declare
  r1 jsonb := '{"source_namespace":"q3682","source_id":"one","label":"Synthetic One","identity_method":"source_id","source_url":"https://example.invalid"}';
  r2 jsonb := '{"source_namespace":"q3682","source_id":"two","label":"Synthetic Two","identity_method":"source_id","source_url":"https://example.invalid"}';
  rp jsonb := '{"source_namespace":"warner_product_catalogue","source_id":"q3682-property","label":"Synthetic Property","identity_method":"source_id","source_url":"https://example.invalid"}';
  p_both text; p_one text; p_prop text; h_both text; h_one text; h_prop text; m_both text; m_one text; m_prop text;
  c uuid; rejected boolean; v_state text;
begin
  p_both := jsonb_build_array(r1, r2)::text;
  p_one := jsonb_build_array(r1)::text;
  p_prop := jsonb_build_array(rp)::text;
  h_both := encode(extensions.digest(convert_to(p_both,'UTF8'),'sha256'),'hex');
  h_one := encode(extensions.digest(convert_to(p_one,'UTF8'),'sha256'),'hex');
  h_prop := encode(extensions.digest(convert_to(p_prop,'UTF8'),'sha256'),'hex');
  m_both := encode(extensions.digest(convert_to(h_both,'UTF8'),'sha256'),'hex');
  m_one := encode(extensions.digest(convert_to(h_one,'UTF8'),'sha256'),'hex');
  m_prop := encode(extensions.digest(convert_to(h_prop,'UTF8'),'sha256'),'hex');

  -- Baseline: both identities active; payload cleared once published.
  c := plm.begin_wb_capture('wb_franchise',date '2099-03-01','q3682-base',m_both,2,'synthetic','https://example.invalid',null);
  perform plm.load_wb_chunk(c,1,p_both,h_both);
  perform plm.finalize_wb_capture(c,m_both,1);
  if (select count(*) from plm.wb_franchise where source_namespace='q3682' and status='active') <> 2 then
    raise exception 'baseline did not publish both identities';
  end if;
  if exists (select 1 from plm.wb_capture where capture_id=c and chunk_number>=1 and (payload is not null or payload_cleared_at is null)) then
    raise exception 'published capture kept its chunk payload';
  end if;

  -- Partial run: declared two rows, streamed one.
  c := plm.begin_wb_capture('wb_franchise',date '2099-03-02','q3682-partial',m_one,2,'synthetic','https://example.invalid',null);
  perform plm.load_wb_chunk(c,1,p_one,h_one);
  rejected := false;
  begin perform plm.finalize_wb_capture(c,m_one,1);
  exception when sqlstate 'P0001' then rejected := position('incomplete chunk set' in sqlerrm) > 0; end;
  if not rejected then raise exception 'partial chunk set was published'; end if;
  perform plm.fail_wb_capture(c,'synthetic partial run');

  -- Digest mismatch: the manifest does not authenticate the stream.
  c := plm.begin_wb_capture('wb_franchise',date '2099-03-03','q3682-digest',m_both,1,'synthetic','https://example.invalid',null);
  perform plm.load_wb_chunk(c,1,p_one,h_one);
  rejected := false;
  begin perform plm.finalize_wb_capture(c,m_both,1);
  exception when sqlstate 'P0001' then rejected := position('manifest digest mismatch' in sqlerrm) > 0; end;
  if not rejected then raise exception 'mismatched manifest was published'; end if;
  perform plm.fail_wb_capture(c,'synthetic digest mismatch');

  -- Shrink bound enforced through finalize, not only on the direct loader.
  c := plm.begin_wb_capture('wb_franchise',date '2099-03-04','q3682-shrink',m_one,1,'synthetic','https://example.invalid',null);
  perform plm.load_wb_chunk(c,1,p_one,h_one);
  rejected := false;
  begin perform plm.finalize_wb_capture(c,m_one,0);
  exception when sqlstate 'P0001' then rejected := position('approved shrink bound' in sqlerrm) > 0; end;
  if not rejected then raise exception 'shrink bound was not enforced by finalize'; end if;
  perform plm.fail_wb_capture(c,'synthetic shrink refusal');

  -- Unauthenticated callers cannot publish.
  c := plm.begin_wb_capture('wb_franchise',date '2099-03-05','q3682-auth',m_one,1,'synthetic','https://example.invalid',null);
  perform plm.load_wb_chunk(c,1,p_one,h_one);
  foreach v_state in array array['anon','authenticated'] loop
    rejected := false;
    begin
      execute format('set local role %I', v_state);
      perform plm.finalize_wb_capture(c,m_one,1);
    exception when insufficient_privilege then rejected := true; end;
    reset role;
    if not rejected then raise exception '% published a Warner capture', v_state; end if;
  end loop;

  -- A failed capture can never be published afterwards.
  rejected := false;
  perform plm.fail_wb_capture(c,'synthetic failure');
  begin perform plm.finalize_wb_capture(c,m_one,1);
  exception when sqlstate 'P0001' then rejected := position('invalid capture state or retired target' in sqlerrm) > 0; end;
  if not rejected then raise exception 'failed capture was published'; end if;
  if (select status from plm.wb_capture where capture_id=c and chunk_number=0) <> 'failed' then
    raise exception 'failed capture changed state';
  end if;

  -- Every refusal above left lifecycle untouched.
  if exists(select 1 from plm.wb_franchise where source_namespace='q3682' and status<>'active')
     or (select count(*) from plm.wb_franchise where source_namespace='q3682') <> 2 then
    raise exception 'a refused run changed Warner lifecycle state';
  end if;

  -- Incompatible run: a qualified property capture does not touch franchise lifecycle.
  c := plm.begin_wb_capture('wb_property',date '2099-03-06','q3682-property',m_prop,1,'synthetic','https://example.invalid',null);
  perform plm.load_wb_chunk(c,1,p_prop,h_prop);
  perform plm.finalize_wb_capture(c,m_prop,1);
  if exists(select 1 from plm.wb_franchise where source_namespace='q3682' and status<>'active') then
    raise exception 'a property capture changed franchise lifecycle';
  end if;

  -- Qualified full baseline without "two": marked withdrawn, never deleted.
  c := plm.begin_wb_capture('wb_franchise',date '2099-03-07','q3682-withdraw',m_one,1,'synthetic','https://example.invalid',null);
  perform plm.load_wb_chunk(c,1,p_one,h_one);
  perform plm.finalize_wb_capture(c,m_one,1);
  if not exists(select 1 from plm.wb_franchise where source_namespace='q3682' and source_id='two'
                and status='withdrawn' and withdrawn_at is not null and first_withdrawn_at is not null)
     or not exists(select 1 from plm.wb_franchise where source_namespace='q3682' and source_id='one' and status='active') then
    raise exception 'qualified baseline did not mark exactly the absent identity withdrawn';
  end if;

  -- A completed capture cannot be published a second time.
  rejected := false;
  begin perform plm.finalize_wb_capture(c,m_one,1);
  exception when sqlstate 'P0001' then rejected := position('invalid capture state or retired target' in sqlerrm) > 0; end;
  if not rejected then raise exception 'completed capture was republished'; end if;

  -- Reappearance in a later qualified baseline reactivates and keeps first withdrawal.
  c := plm.begin_wb_capture('wb_franchise',date '2099-03-08','q3682-reappear',m_both,2,'synthetic','https://example.invalid',null);
  perform plm.load_wb_chunk(c,1,p_both,h_both);
  perform plm.finalize_wb_capture(c,m_both,1);
  if not exists(select 1 from plm.wb_franchise where source_namespace='q3682' and source_id='two'
                and status='active' and withdrawn_at is null and first_withdrawn_at is not null) then
    raise exception 'reappearance lost lifecycle history';
  end if;
end
$publication$;
rollback;
