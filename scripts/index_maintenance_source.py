"""Maintenance-only trusted-source parity; never executes database statements.

Reuse canonical complete-tree/blob readers. Conservatively pin EVERY tracked
non-tools blob (including all guards/imports/runtime data), plus the literal
repository tool dependencies of executed safety code. Unknown tool paths refuse.
No migration/normal-production freshness policy is changed.
"""
from __future__ import annotations
import ast
import base64
import json
import hashlib
import subprocess
from pathlib import PurePosixPath
import re
from production_business_risk_gate import tracked_tree_at, blob_sha_from_tree, RiskGateError

REPO='popcre/shared-db'
SHA=re.compile(r'^[a-f0-9]{40}$')
TOOL=re.compile(r'tools/[A-Za-z0-9_.@/-]+')


def pin_paths(tree, read):
    """Conservative coverage walk: all non-tools input, actual tool import closure.

    Unlike the preview-job-only walker, nested ../ JS imports and Python sibling
    modules cannot escape: ALL tracked non-tools files are pinned, not just the
    imports a regex recognized. Tool literals in all safety scripts and the
    executed workflow are resolved positively from the complete tracked tree.
    New/removed dependencies change the pin set and fail comparison.
    """
    if any(e.get('type') not in ('tree','blob') for e in tree.values()):
        raise RiskGateError('unreadable maintenance submodule/dependency type')
    blobs={p for p,e in tree.items() if e.get('type')=='blob'}
    pinned={p for p in blobs if not p.startswith('tools/')}
    roots={p for p in pinned if p.startswith('scripts/') and p.endswith(('.py','.mjs','.js','.sh'))}
    roots.add('.github/workflows/shared-supabase-migrations.yml')
    pending=list(roots);seen=set()
    while pending:
        path=pending.pop()
        if path in seen:continue
        seen.add(path)
        if path not in blobs:raise RiskGateError('maintenance dependency absent: '+path)
        body=read(path)
        # All explicit tool paths, including subprocess commands/runtime reads.
        dependencies=set(TOOL.findall(body))
        # Python pathlib's / 'tools' / 'name.py' is also a runtime input.
        for expression in re.findall(r'''["']tools["'](?:\s*/\s*["'][A-Za-z0-9_.@/-]+["'])+''',body):
            dependencies.add('/'.join(re.findall(r'''["']([^"']+)["']''',expression)))
        if path.endswith('.py'):
            syntax=ast.parse(body)
            for node in ast.walk(syntax):
                if isinstance(node,ast.JoinedStr) and any(isinstance(v,ast.Constant) and isinstance(v.value,str) and 'tools/' in v.value for v in node.values):
                    raise RiskGateError('unbounded dynamic maintenance tool dependency')
                if isinstance(node,ast.BinOp) and isinstance(node.op,ast.Add) and isinstance(node.left,ast.Constant) and isinstance(node.left.value,str) and 'tools/' in node.left.value and not isinstance(node.right,ast.Constant):
                    raise RiskGateError('unbounded dynamic maintenance tool dependency')
        elif re.search(r'''tools/(?:\$|\{|["'])''',body):
            raise RiskGateError('unbounded dynamic maintenance tool dependency')
        # Both import/export-from and dynamic literal imports; nested ../ works.
        for rel in re.findall(r'(?:from\s*|import\s*\()\s*[\'\"](\.{1,2}/[^\'\"]+)[\'\"]',body):
            parts=[]
            for bit in (str(PurePosixPath(path).parent)+'/'+rel).split('/'):
                if bit=='..':
                    if not parts:raise RiskGateError('maintenance import escapes repository')
                    parts.pop()
                elif bit not in ('','.'):parts.append(bit)
            resolved='/'.join(parts)
            if resolved in blobs:dependencies.add(resolved)
        if path.endswith('.py'):
            for node in ast.walk(ast.parse(body)):
                mods=[node.module] if isinstance(node,ast.ImportFrom) else [a.name for a in node.names] if isinstance(node,ast.Import) else []
                for mod in mods:
                    sibling='scripts/'+str(mod).replace('.','/')+'.py'
                    if sibling in blobs:dependencies.add(sibling)
        for dep in dependencies:
            if dep in blobs:matches={dep}
            else:matches={p for p in blobs if p.startswith(dep.rstrip('/')+'/')}
            # Positive complete-tree absence covers fixture/external path literals.
            # A path added/deleted on either side changes the resolved pin set.
            if not matches:continue
            for resolved in matches:
                pinned.add(resolved)
                if resolved.endswith(('.py','.mjs','.js','.sh')):pending.append(resolved)
    if not roots<=seen or not pinned:raise RiskGateError('maintenance coverage proved nothing')
    return pinned


def prove(source,entry,operation,api):
    if not SHA.fullmatch(source):raise RiskGateError('maintenance source SHA refused')
    main=api(f'repos/{REPO}/commits/main').get('sha')
    if not isinstance(main,str) or not SHA.fullmatch(main):raise RiskGateError('maintenance current main unreadable')
    ancestry=api(f'repos/{REPO}/compare/{source}...{main}')
    if ancestry.get('status') not in ('ahead','identical') or ancestry.get('behind_by')!=0:
        raise RiskGateError('maintenance source is not a trusted main ancestor')
    trees={ref:tracked_tree_at(ref,api) for ref in set((source,main))}
    cache={}
    def read(ref,path):
        sha=blob_sha_from_tree(path,ref,trees[ref])
        if not SHA.fullmatch(sha):raise RiskGateError('maintenance blob SHA malformed')
        key=sha
        if key not in cache:
            local=subprocess.run(['git','cat-file','blob',sha],capture_output=True)
            if local.returncode==0:raw=local.stdout
            else:
                blob=api(f'repos/{REPO}/git/blobs/{sha}')
                if blob.get('encoding')!='base64' or blob.get('sha')!=sha:raise RiskGateError('maintenance blob identity unreadable')
                try:raw=base64.b64decode(blob['content'],validate=False)
                except Exception as exc:raise RiskGateError('maintenance dependency content unreadable') from exc
            if hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()!=sha:
                raise RiskGateError('maintenance blob content hash mismatch')
            try:cache[key]=raw.decode('utf-8')
            except Exception as exc:raise RiskGateError('maintenance dependency content unreadable') from exc
        return cache[key]
    paths={ref:pin_paths(trees[ref],lambda p,ref=ref:read(ref,p)) for ref in trees}
    if paths[source]!=paths[main]:raise RiskGateError('maintenance dependency added or removed')
    compared=0
    for path in paths[source]:
        if (trees[source][path].get('mode')!=trees[main][path].get('mode')
            or trees[source][path].get('mode')=='120000'
            or blob_sha_from_tree(path,source,trees[source])!=blob_sha_from_tree(path,main,trees[main])):
            raise RiskGateError('maintenance producer/current policy changed: '+path)
        compared+=1
    if compared==0:raise RiskGateError('maintenance producer comparison proved nothing')
    policy=json.loads(read(main,'config/nontransactional-index-maintenance.json'))
    if policy.get('schema_version')!=1 or policy.get('operations',{}).get(operation)!=entry:
        raise RiskGateError('maintenance current operation disabled/deleted/changed')
    # Read the live main again: a change during the proof requires a new proof.
    if api(f'repos/{REPO}/commits/main').get('sha')!=main:
        raise RiskGateError('maintenance main advanced during producer proof')
    return {'source_sha':source,'current_main_sha':main,'compared':compared}
