-- Invented objects ONLY in the separately reviewed, owned no-network PG17.6 source.
-- Native roles, schema ownership, grants, extensions, cron and worker settings stay intact.
DO $$
BEGIN
  IF current_user <> 'supabase_admin' OR NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) THEN
    RAISE EXCEPTION '4427 local fixture requires existing native Supabase administrator';
  END IF;
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname IN ('rls4427_owner','rls4427_reader','rls4427_writer'))
     OR to_regnamespace('rls4427_fixture') IS NOT NULL THEN
    RAISE EXCEPTION '4427 local fixture name already occupied';
  END IF;
END $$;
CREATE ROLE rls4427_owner NOLOGIN;
CREATE ROLE rls4427_reader NOLOGIN;
CREATE ROLE rls4427_writer NOLOGIN;
CREATE SCHEMA rls4427_fixture AUTHORIZATION rls4427_owner;
GRANT USAGE ON SCHEMA rls4427_fixture TO rls4427_reader,rls4427_writer;
SET ROLE rls4427_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA rls4427_fixture GRANT SELECT ON TABLES TO rls4427_reader;
CREATE TABLE rls4427_fixture.authority_fixture(id integer PRIMARY KEY,label text NOT NULL);
INSERT INTO rls4427_fixture.authority_fixture VALUES(1,'invented-owner');
CREATE TABLE rls4427_fixture.restore_fixture(id serial PRIMARY KEY,label text NOT NULL CHECK(length(label)>0));
INSERT INTO rls4427_fixture.restore_fixture VALUES(1,'synthetic-public');
GRANT USAGE,SELECT ON SEQUENCE rls4427_fixture.restore_fixture_id_seq TO rls4427_writer;
CREATE TABLE rls4427_fixture.objects(id integer PRIMARY KEY,owner text NOT NULL,label text NOT NULL);
CREATE INDEX restore_label_idx ON rls4427_fixture.objects(label);
INSERT INTO rls4427_fixture.objects VALUES(1,'synthetic','one'),(2,'synthetic','two');
CREATE FUNCTION rls4427_fixture.fixture_normalize() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.label=trim(NEW.label); RETURN NEW; END $$;
CREATE TRIGGER fixture_normalize BEFORE INSERT OR UPDATE ON rls4427_fixture.objects
  FOR EACH ROW EXECUTE FUNCTION rls4427_fixture.fixture_normalize();
CREATE FUNCTION rls4427_fixture.request_allowed() RETURNS boolean LANGUAGE plpgsql STABLE AS $$
BEGIN RETURN current_setting('request.jwt.claim.role',true)='fixture_writer'; END $$;
ALTER TABLE rls4427_fixture.objects ENABLE ROW LEVEL SECURITY;
CREATE POLICY fixture_read ON rls4427_fixture.objects FOR SELECT TO rls4427_reader,rls4427_writer USING(owner='synthetic');
CREATE POLICY fixture_write ON rls4427_fixture.objects FOR UPDATE TO rls4427_writer
  USING(owner='synthetic' AND rls4427_fixture.request_allowed())
  WITH CHECK(owner='synthetic' AND rls4427_fixture.request_allowed());
GRANT SELECT ON rls4427_fixture.objects TO rls4427_reader,rls4427_writer;
GRANT UPDATE(label) ON rls4427_fixture.objects TO rls4427_writer;
-- The reader's permission on this table must come from the actual default ACL.
CREATE TABLE rls4427_fixture.default_acl_probe(id integer);
RESET ROLE;
