"""Adversarial mocked HTTP and observation-preservation checks; no hosted calls."""
import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.error
import urllib.request

SPEC = importlib.util.spec_from_file_location('stage',Path(__file__).with_name('stage_pgss_capacity.py'))
m = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(m)


def catalog(effective='5000'):
    plan = m.load_plan()
    return {'execution_role':'supabase_read_only_user','session_role':'supabase_read_only_user',
      'database':'postgres','read_only':'on','role_super':False,'role_bypassrls':True,
      'context':'postmaster','effective':effective,'pending_restart':False,
      'postmaster':'2026-11-06 16:20:19+00','database_reset':None,
      'statement_reset':'2026-11-06 16:20:19+00',
      'indexes':[dict(x,valid=True,ready=True) for x in plan['production_candidates']]}


class Response(io.BytesIO):
    status = 200


class Transport:
    """Check the actual wire requests, not just program helper call arguments."""
    def __init__(self, config=None, state=None):
        self.config = {m.SETTING:5000,'work_mem':'4MB','log_connections':True,
                       'max_connections':100} if config is None else config
        self.state = catalog() if state is None else state
        self.requests = []
        self.config_reads = 0
        self.change_second = False
        self.target = 'a'*20
        self.identity_override = None
        self.identity_hook = None
        self.after_hook = None
        self.put_error = False
        self.redirect = False
        self.malformed = None

    def open(self, request, timeout):
        self.requests.append(request)
        if self.redirect:
            raise urllib.error.HTTPError(request.full_url,302,'secret redirect',{},None)
        if self.malformed is not None:
            return Response(self.malformed)
        payload = None if request.data is None else json.loads(request.data)
        if request.method == 'GET' and request.full_url.endswith('/postgres'):
            self.config_reads += 1
            result = copy.deepcopy(self.config)
            if self.config_reads == 2 and self.change_second:
                result['work_mem'] = '8MB'
        elif request.method == 'GET':
            if self.identity_hook:
                self.identity_hook(self)
            result = {'id':self.target if self.identity_override is None else self.identity_override}
        elif request.method == 'POST':
            if payload != {'query':m.SQL,'read_only':True}:
                raise AssertionError('non-exact catalog query')
            result = [copy.deepcopy(self.state)]
        elif request.method == 'PUT':
            if self.put_error:
                raise urllib.error.URLError('secret_token_and_vendor_detail')
            if payload.get('restart_database') is not False:
                raise AssertionError('no staging instruction')
            self.config = {k:v for k,v in payload.items() if k!='restart_database'}
            self.state['pending_restart'] = True
            if self.after_hook:
                self.after_hook(self)
            result = copy.deepcopy(self.config)
        else:
            raise AssertionError('unexpected method')
        return Response(json.dumps(result).encode())


class StageTests(unittest.TestCase):
    def api(self, transport):
        return m.API('a'*20,'private-test-token',transport)

    def execute(self, transport, target='production', fence=lambda:None):
        return m.stage(self.api(transport),m.load_plan(),target,fence)

    def puts(self, transport):
        return [r for r in transport.requests if r.method=='PUT']

    def test_wire_body_preserves_all_overrides_and_forces_false(self):
        transport = Transport()
        before = copy.deepcopy(transport.config)
        fences=[]
        result = self.execute(transport,fence=lambda:fences.append(True))
        self.assertEqual(fences,[True])
        self.assertEqual(json.loads(self.puts(transport)[0].data),
                         dict(before,**{m.SETTING:40000,'restart_database':False}))
        self.assertEqual([r.method for r in transport.requests],['GET','POST','GET','GET','PUT','GET','POST'])
        self.assertEqual(transport.requests[2].full_url,'https://api.supabase.com/v1/projects/'+'a'*20)
        self.assertTrue(transport.requests[3].full_url.endswith('/config/database/postgres'))
        self.assertTrue(result['changed'])
        self.assertEqual(result['effective_capacity'],5000)
        self.assertTrue(result['pending_restart'])
        self.assertNotIn('private-test-token',json.dumps(result))
        self.assertNotIn('a'*20,json.dumps(result))
        self.assertEqual(transport.state['effective'],'5000')

    def test_idempotent_stored_or_effective_desired_never_writes(self):
        for effective in ('5000','40000'):
            transport=Transport(config={m.SETTING:40000},state=catalog(effective))
            self.assertFalse(self.execute(transport)['changed'])
            self.assertEqual(self.puts(transport),[])

    def test_missing_default_override_is_safe_increase(self):
        transport=Transport(config={'work_mem':'4MB'})
        self.assertTrue(self.execute(transport)['changed'])
        self.assertEqual(transport.config,{'work_mem':'4MB',m.SETTING:40000})

    def test_unknown_before_values_or_decrease_refused_before_put(self):
        for config in ({m.SETTING:45000},{m.SETTING:20000},{m.SETTING:True},
                       {m.SETTING:'5000'},{m.SETTING:5000.0},{'unrecognized':'value'},
                       {'log_connections':'on'},{'max_connections':True}):
            with self.subTest(config=config):
                transport=Transport(config=config)
                with self.assertRaises(m.Refused):self.execute(transport)
                self.assertFalse(self.puts(transport))
        transport=Transport(config={m.SETTING:5000},state=catalog('40000'))
        with self.assertRaises(m.Refused):self.execute(transport)
        self.assertFalse(self.puts(transport))

    def test_concurrent_second_get_aborts_without_put(self):
        transport=Transport();transport.change_second=True
        with self.assertRaisesRegex(m.Refused,'concurrent'):self.execute(transport)
        self.assertFalse(self.puts(transport))

    def test_identity_get_mutation_aborts_without_put_or_restoration(self):
        transport=Transport()
        transport.identity_hook=lambda t:t.config.update(work_mem='8MB')
        with self.assertRaisesRegex(m.Refused,'concurrent'):self.execute(transport)
        self.assertFalse(self.puts(transport))
        self.assertEqual(transport.config['work_mem'],'8MB')

    def test_fence_time_mutation_aborts_without_put_or_restoration(self):
        transport=Transport()
        def fence():transport.config['work_mem']='8MB'
        with self.assertRaisesRegex(m.Refused,'concurrent'):self.execute(transport,fence=fence)
        self.assertFalse(self.puts(transport))
        self.assertEqual(transport.config['work_mem'],'8MB')

    def test_target_mismatch_and_fence_loss_abort_without_put(self):
        transport=Transport();transport.identity_override='b'*20
        with self.assertRaisesRegex(m.Refused,'target'):self.execute(transport)
        self.assertFalse(self.puts(transport))
        transport=Transport()
        def lost():raise m.Refused('native fence lost')
        with self.assertRaisesRegex(m.Refused,'fence'):self.execute(transport,fence=lost)
        self.assertFalse(self.puts(transport))

    def test_wrong_role_context_source_index_or_extra_catalog_key_refused(self):
        for key,value in [('execution_role','postgres'),('session_role','postgres'),
                          ('role_super',True),('role_bypassrls',False),('read_only','off'),
                          ('database','other'),('context','sighup'),('effective','50000'),
                          ('pending_restart','true'),('unknown',False)]:
            with self.subTest(key=key):
                state=catalog();state[key]=value;transport=Transport(state=state)
                with self.assertRaises(m.Refused):self.execute(transport)
                self.assertFalse(self.puts(transport))
        state=catalog();state['indexes'][0]['index_oid']='999';transport=Transport(state=state)
        with self.assertRaises(m.Refused):self.execute(transport)
        self.assertFalse(self.puts(transport))

    def test_restart_reset_index_or_effective_change_after_put_is_failure(self):
        for key,value in [('postmaster','changed'),('statement_reset','changed'),
                          ('database_reset','changed'),('effective','40000')]:
            with self.subTest(key=key):
                transport=Transport();transport.after_hook=lambda t,k=key,v=value:t.state.update({k:v})
                with self.assertRaises(m.Refused):self.execute(transport)
        transport=Transport();transport.after_hook=lambda t:t.state['indexes'][0].update(index_oid='999')
        with self.assertRaises(m.Refused):self.execute(transport)
        transport=Transport();transport.after_hook=lambda t:t.config.update(work_mem='99MB')
        with self.assertRaises(m.Refused):self.execute(transport)

    def test_pending_restart_false_is_valid(self):
        transport=Transport();transport.after_hook=lambda t:t.state.update(pending_restart=False)
        self.assertFalse(self.execute(transport)['pending_restart'])

    def test_unknown_put_outcome_is_not_retried_or_restored(self):
        transport=Transport();transport.put_error=True
        with self.assertRaises(m.Refused) as error:self.execute(transport)
        self.assertNotIn('secret',str(error.exception))
        self.assertEqual(len(self.puts(transport)),1)
        self.assertEqual(transport.config_reads,2)

    def test_transport_cannot_target_other_hosts_endpoints_or_redirect(self):
        transport=Transport();api=self.api(transport)
        for method,kind in [('POST','restart'),('DELETE','config'),('PUT','https://evil')]:
            with self.assertRaises(m.Refused):api.call(method,kind)
        for body in ({m.SETTING:40000},{m.SETTING:40000,'restart_database':True},
                     {m.SETTING:5000,'restart_database':False}):
            with self.assertRaises(m.Refused):api.call('PUT','config',body)
        transport.redirect=True
        with self.assertRaises(m.Refused):api.call('GET','config')
        self.assertEqual(len(transport.requests),1)
        with self.assertRaises(m.Refused):m.NoRedirect().redirect_request(None,None,302,'',{},'https://evil')
        with self.assertRaises(m.Refused):m.API('https://evil','token')
        with patch.dict('os.environ',{'HTTPS_PROXY':'https://evil'}):
            opener=m.API('a'*20,'token').transport
            self.assertFalse(any(isinstance(h,urllib.request.ProxyHandler) and h.proxies for h in opener.handlers))

    def test_duplicate_json_float_and_oversize_redacted(self):
        for payload in (b'{"pg_stat_statements.max":5000,"pg_stat_statements.max":40000}',
                        b'{"pg_stat_statements.max":5000.0}',b'{"value":NaN}',b'bad secret',b' '*1048577):
            transport=Transport();transport.malformed=payload
            with self.assertRaises(m.Refused) as error:self.api(transport).call('GET','config')
            self.assertNotIn('secret',str(error.exception))

    def test_production_reference_is_ast_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'scripts').mkdir()
            (root/m.REF_MODULE).write_text("raise RuntimeError('must never execute')\nPROJECT_REF='"+'b'*20+"'\n")
            self.assertEqual(m.production_ref(root),'b'*20)
            (root/m.REF_MODULE).write_text("PROJECT_REF='"+'b'*20+"'\nPROJECT_REF='"+'c'*20+"'\n")
            with self.assertRaises(m.Refused):m.production_ref(root)

    def binding(self):
        return {'source_sha':'c'*40,'run_id':'123','run_attempt':'1','workflow':m.WORKFLOW,
                'plan_sha256':'d'*64,'files_sha256':{'file':'e'*64}}

    def test_preview_receipt_binds_source_run_attempt_plan_and_target(self):
        binding=self.binding()
        receipt=dict(binding,schema_version=1,operation=m.OPERATION,work_issue=5609,
          target='preview',target_sha256=m.digest('a'*20),stage_only=True,succeeded=True,
          changed=True,stored_capacity=40000,effective_capacity=5000,pending_restart=True,
          **{k:'f'*64 for k in ('before_sha256','after_sha256','postmaster_sha256','reset_sha256','indexes_sha256')})
        m.validate_preview(receipt,binding,'a'*20)
        for key,value in [('source_sha','b'*40),('run_id','124'),('run_attempt','2'),
                          ('plan_sha256','b'*64),('files_sha256',{}),('target','production'),
                          ('target_sha256','b'*64),('succeeded',False),('stage_only',False),
                          ('stored_capacity',5000),('extra','value')]:
            changed=dict(receipt);changed[key]=value
            with self.subTest(key=key),self.assertRaises(m.Refused):m.validate_preview(changed,binding,'a'*20)

    def environment(self):
        return {'GITHUB_REPOSITORY':'popcre/shared-db','GITHUB_EVENT_NAME':'workflow_dispatch',
          'GITHUB_REF':'refs/heads/main','GITHUB_SHA':'c'*40,'EXPECTED_HEAD':'c'*40,
          'WORK_ISSUE':'5609','GITHUB_RUN_ID':'123','GITHUB_RUN_ATTEMPT':'1',
          'GITHUB_WORKFLOW_REF':'popcre/shared-db/'+m.WORKFLOW+'@refs/heads/main',
          'PREVIEW_PROJECT_REF':'a'*20,'SUPABASE_ACCESS_TOKEN':'private-test-token'}

    def test_full_preview_receipt_then_production_and_missing_preview_no_http(self):
        with tempfile.TemporaryDirectory() as directory:
            preview=Path(directory)/'preview.json';prod=Path(directory)/'production.json'
            transports=[]
            def factory(ref,token):
                transport=Transport();transport.target=ref;transports.append(transport)
                return m.API(ref,token,transport)
            env=self.environment()
            with self.assertRaises(m.Refused):
                m.run('production',prod,env=env,api_factory=factory,fence=lambda:None)
            self.assertEqual(transports,[])
            first=m.run('preview',preview,env=env,api_factory=factory,fence=lambda:None)
            m.run('production',prod,preview,env=env,api_factory=factory,fence=lambda:None)
            self.assertTrue(prod.exists());self.assertTrue(first['succeeded'])
            for bad in ({'EXPECTED_HEAD':'b'*40},{'GITHUB_EVENT_NAME':'push'},
                        {'GITHUB_REF':'refs/heads/other'},{'WORK_ISSUE':'5610'},
                        {'GITHUB_RUN_ATTEMPT':'2'},{'PREVIEW_PROJECT_REF':m.production_ref()}):
                count=len(transports)
                with self.subTest(bad=bad),self.assertRaises(m.Refused):
                    m.run('production',prod,preview,env=dict(env,**bad),api_factory=factory,fence=lambda:None)
                self.assertEqual(len(transports),count)

    def test_failed_postcondition_never_writes_success_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)/'receipt.json'
            transport=Transport();transport.after_hook=lambda t:t.state.update(effective='40000')
            with self.assertRaises(m.Refused):
                m.run('preview',output,env=self.environment(),
                      api_factory=lambda ref,token:m.API(ref,token,transport),fence=lambda:None)
            self.assertFalse(output.exists())

    def test_workflow_source_and_token_scope_contract(self):
        source=(m.ROOT/m.WORKFLOW).read_text()
        self.assertEqual(source.count('SUPABASE_ACCESS_TOKEN:'),2)
        self.assertEqual(source.count('ref: ${{ github.sha }}'),2)
        self.assertEqual(source.count('node scripts/gh-read.mjs --out'),2)
        self.assertIn('needs: preview',source)
        self.assertIn("needs.preview.result == 'success'",source)
        self.assertIn('cancel-in-progress: false',source)
        self.assertNotIn('workflow_call:',source)
        self.assertNotIn('schedule:',source)
        for block in source.split('      - name: ')[1:]:
            if block.startswith('Verify exact current main'):
                self.assertNotIn('SUPABASE_ACCESS_TOKEN',block)
            if 'SUPABASE_ACCESS_TOKEN:' in block:
                self.assertNotIn('gh-read.mjs',block)

    def test_native_fence_subprocess_never_inherits_supabase_credential(self):
        with patch.dict('os.environ',{'SUPABASE_ACCESS_TOKEN':'secret','GH_TOKEN':'github-token'}):
            with patch.object(m.subprocess,'run') as execute:
                execute.return_value.returncode=0
                m.native_fence('preview')
                args,options=execute.call_args
                self.assertNotIn('SUPABASE_ACCESS_TOKEN',options['env'])
                self.assertEqual(options['env']['GH_TOKEN'],'github-token')
                self.assertEqual(args[0][-2:],['verify','preview'])


if __name__=='__main__':unittest.main()
