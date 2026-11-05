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


def python_tools(syntax):
    """Resolve complete static tool paths; reject directory-prefix aliases.

    Rejecting a prefix at its definition is conservative dataflow: an alias
    cannot later hide the namespace from this walk. Never infer variable values
    or authorize a whole unknown tools directory.
    """
    dependencies=set()
    parents={child:node for node in ast.walk(syntax) for child in ast.iter_child_nodes(node)}
    def literal(node):return node.value if isinstance(node,ast.Constant) and isinstance(node.value,str) else None
    def namespace(value):
        return isinstance(value,str) and re.search(r'(?:^|/)tools(?:/|$)',value) is not None
    # A formatted namespace can escape through any alias or Path constructor.
    # Reject it at its definition, including a terminal /tools component.
    for node in ast.walk(syntax):
        if isinstance(node,(ast.JoinedStr,ast.BinOp)) and any(isinstance(v,ast.Constant) and namespace(v.value) and v.value.rstrip('/').endswith('/tools') for v in ast.walk(node)):
            raise RiskGateError('unresolved maintenance tools-directory formatted prefix')
    def parts(node):
        if isinstance(node,ast.BinOp) and isinstance(node.op,ast.Div):return parts(node.left)+[node.right]
        return [node]
    def suffix(values):
        for i,value in enumerate(values):
            if literal(value) is None and any(isinstance(v,ast.Constant) and isinstance(v.value,str) and v.value.rstrip('/').split('/')[-1]=='tools' for v in ast.walk(value)):
                raise RiskGateError('unresolved maintenance tools-directory expression')
            if literal(value) is not None and literal(value).rstrip('/').split('/')[-1]=='tools':
                tail=values[i+1:]
                if not tail or any(literal(v) is None for v in tail):
                    raise RiskGateError('unresolved maintenance tools-directory prefix')
                dependencies.add('/'.join(['tools',*(literal(v).strip('/') for v in tail)]))
    for node in ast.walk(syntax):
        if isinstance(node,ast.BinOp) and isinstance(node.op,ast.Div):
            parent=parents.get(node)
            if not (isinstance(parent,ast.BinOp) and isinstance(parent.op,ast.Div) and parent.left is node):suffix(parts(node))
        if isinstance(node,ast.Call):
            name=getattr(node.func,'id',None) or getattr(node.func,'attr',None)
            if name in {'Path','PurePath','PurePosixPath','join','joinpath'} and not (name=='join' and isinstance(getattr(node.func,'value',None),ast.Constant)):suffix(node.args)
        if isinstance(node,(ast.Assign,ast.AnnAssign)) and literal(node.value) is not None and literal(node.value).rstrip('/').split('/')[-1]=='tools':
            raise RiskGateError('unresolved maintenance tools-directory alias')
    return dependencies


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
        executed=set(dependencies)
        # Reads may execute their contents; traverse them conservatively.
        for expression in re.finditer(r'''(?:\b[A-Za-z_$][\w$]*\.)?(?:join|resolve)\([^()\n]*?["']tools["']((?:\s*,\s*["'][A-Za-z0-9_.@/-]+["'])+)\s*\)''',body):
            dep='/'.join(['tools',*re.findall(r'''["']([^"']+)["']''',expression.group(1))])
            dependencies.add(dep)
            executed.add(dep)
        # Python pathlib's / 'tools' / 'name.py' is also a runtime input.
        for expression in re.findall(r'''["']tools["'](?:\s*/\s*["'][A-Za-z0-9_.@/-]+["'])+''',body):
            dependencies.add('/'.join(re.findall(r'''["']([^"']+)["']''',expression)))
        if path.endswith('.py'):
            syntax=ast.parse(body)
            python_dependencies=python_tools(syntax)
            dependencies.update(python_dependencies);executed.update(python_dependencies)
            for node in ast.walk(syntax):
                if isinstance(node,ast.JoinedStr) and any(isinstance(v,ast.Constant) and isinstance(v.value,str) and 'tools/' in v.value for v in node.values):
                    raise RiskGateError('unbounded dynamic maintenance tool dependency')
                if isinstance(node,ast.BinOp) and isinstance(node.op,ast.Add) and isinstance(node.left,ast.Constant) and isinstance(node.left.value,str) and 'tools/' in node.left.value and not isinstance(node.right,ast.Constant):
                    raise RiskGateError('unbounded dynamic maintenance tool dependency')
        elif re.search(r'''tools/(?:\$|\{|["'])''',body):
            raise RiskGateError('unbounded dynamic maintenance tool dependency')
        elif re.search(r'''["']tools/?["']\s*(?:\)|,\s*(?!["'])[^\s])''',body):
            raise RiskGateError('unresolved constructed maintenance tools-directory prefix')
        elif re.search(r'''(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*=\s*["']tools/?["']''',body):
            raise RiskGateError('unresolved maintenance tools-directory alias')
        if path.endswith(('.mjs','.js','.sh')) and re.search(r"""/tools(?=["'`\s;]|$)""",body):
            # A terminal namespace component has no proven static filename.
            # Refuse at definition, before templates/shell aliases hide it.
            raise RiskGateError('unresolved maintenance tools-directory terminal component')
        # Both import/export-from and dynamic literal imports; nested ../ works.
        for rel in re.findall(r'(?:from\s*|import\s*\()\s*[\'\"](\.{1,2}/[^\'\"]+)[\'\"]',body):
            parts=[]
            for bit in (str(PurePosixPath(path).parent)+'/'+rel).split('/'):
                if bit=='..':
                    if not parts:raise RiskGateError('maintenance import escapes repository')
                    parts.pop()
                elif bit not in ('','.'):parts.append(bit)
            resolved='/'.join(parts)
            if resolved in blobs:dependencies.add(resolved);executed.add(resolved)
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
