#!/usr/bin/env python3
"""Native bridge: re-derive maintenance authority, never accept proof booleans."""
import argparse
import json
import os
from pathlib import Path
import sys
import nontransactional_index_maintenance as m

def verify(request):
    if request.get('target') not in ('preview','production'):raise m.Refusal('native maintenance target class refused')
    if request.get('run_id')!=int(os.environ.get('GITHUB_RUN_ID','0')):
        raise m.Refusal('native maintenance run identity mismatch')
    operation=m.operation_from_dispatch_ref(request.get('dispatch_ref',''))
    entry=m.operation(json.loads(m.POLICY.read_text()),operation)
    if request.get('source_pr')!=entry['source_pr']:
        raise m.Refusal('native maintenance source PR mismatch')
    if entry.get('kind')=='health-initial/v1':
        from health_initial_index_maintenance import claim_request
        claim=claim_request(entry,operation)
    else:
        claim={'claim_issue':entry['claim_issue'],'work_issue':entry['work_issue'],
               'objects':['table '+m.TABLE,*['index public.'+x for x in m.names(operation)]]}
    if request.get('claim')!=claim:raise m.Refusal('native maintenance claim does not match actual policy')
    options=argparse.Namespace(operation=operation,target=request.get('target'),source_sha=request.get('head_sha'),
        dispatch_ref=request['dispatch_ref'],expected_project_ref=os.environ.get('EXPECTED_PROJECT_REF',''),linked_dir=m.ROOT)
    environment=m.workflow_gate(options,entry)
    return {'source_sha':options.source_sha,'current_main_sha':environment['_CURRENT_MAIN_SHA'],
            'source_pr':entry['source_pr'],'run_id':request['run_id']}

if __name__=='__main__':
    try:print(json.dumps(verify(json.load(sys.stdin))))
    except Exception as exc:
        print('native maintenance source proof refused: '+type(exc).__name__,file=sys.stderr);sys.exit(2)
