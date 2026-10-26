-- Issue #4832. Catalogue assertions and a rolled-back runtime save matching
-- services/role.service.js updateRole. No business name or membership persists.
BEGIN;
DO $contract$
DECLARE col text; actual text[];
BEGIN
  SELECT array_agg(a.attname::text ORDER BY a.attname) INTO actual
    FROM pg_attribute a CROSS JOIN LATERAL aclexplode(a.attacl) acl
   WHERE a.attrelid = 'dflow_prod."Roles"'::regclass
     AND acl.grantee = 'designflow_prod_backend_grants'::regrole
     AND acl.privilege_type = 'UPDATE' AND NOT acl.is_grantable;
  IF actual IS DISTINCT FROM ARRAY['Name','is_active','parent_id'] THEN
    RAISE EXCEPTION 'Unexpected backend column UPDATE grant: %', actual;
  END IF;
  FOREACH col IN ARRAY ARRAY['Name','parent_id','is_active'] LOOP
    IF NOT has_column_privilege('designflow_prod_backend_runtime', 'dflow_prod."Roles"', col, 'UPDATE') THEN
      RAISE EXCEPTION 'Backend runtime cannot update %', col;
    END IF;
  END LOOP;
  IF has_table_privilege('designflow_prod_backend_runtime', 'dflow_prod."Roles"', 'UPDATE')
     OR has_table_privilege('designflow_prod_backend_runtime', 'dflow_prod."Roles"', 'INSERT')
     OR has_table_privilege('designflow_prod_backend_runtime', 'dflow_prod."Roles"', 'DELETE') THEN
    RAISE EXCEPTION 'Backend has broader role write privileges than this contract';
  END IF;
  FOREACH col IN ARRAY ARRAY['Id','kind','app_role_id'] LOOP
    IF has_column_privilege('designflow_prod_backend_runtime', 'dflow_prod."Roles"', col, 'UPDATE') THEN
      RAISE EXCEPTION 'Backend must not update protected column %', col;
    END IF;
  END LOOP;
END
$contract$;
DO $behavior$
DECLARE target_id integer; affected integer; renamed text;
BEGIN
  SELECT "Id" INTO STRICT target_id FROM dflow_prod."Roles" WHERE kind='leaf' ORDER BY "Id" LIMIT 1;
  SET LOCAL ROLE designflow_prod_backend_runtime;
  renamed := 'contract-4832-' || target_id;
  UPDATE dflow_prod."Roles" SET "Name"=renamed, parent_id=parent_id, is_active=is_active
    WHERE "Id"=target_id;
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 1 THEN RAISE EXCEPTION 'Runtime save did not update one role'; END IF;
  IF NOT EXISTS (SELECT 1 FROM dflow_prod."Roles" WHERE "Id"=target_id AND "Name"=renamed) THEN
    RAISE EXCEPTION 'Renamed value did not persist within the transaction';
  END IF;
  BEGIN
    UPDATE dflow_prod."Roles" SET kind=kind WHERE "Id"=target_id;
    RAISE EXCEPTION 'Runtime changed protected kind';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    DELETE FROM dflow_prod."Roles" WHERE "Id"=-1;
    RAISE EXCEPTION 'Runtime acquired DELETE';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RESET ROLE;
END
$behavior$;
ROLLBACK;
