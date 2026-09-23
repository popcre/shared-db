"""Independent full-catalog evaluation. Gold assignments never depend on reader output.

Descriptions and per-description assignments belong in the private source repository.
Public reports contain aggregate counts only. SHA keys distinguish NULL from empty text.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import inspect
from pathlib import Path
from datetime import datetime

FIELDS = ('product_type', 'product_construction', 'product_material',
          'product_treatment', 'product_type_status')
STATUSES = {'accepted', 'unreadable', 'placeholder'}


def canonical_fields(values):
    """Compare explicit multi-value facts as sets; never supply missing facts."""
    result = {}
    for field in FIELDS:
        value = values[field]
        if value is not None and not isinstance(value, str):
            raise ValueError('Semantic values must be text or blank')
        result[field] = value if value != '' else None
    for field in ('product_construction', 'product_material', 'product_treatment'):
        if result[field] is not None:
            if not isinstance(result[field], str):
                raise ValueError('Semantic values must be text or blank')
            result[field] = '; '.join(sorted(set(part.strip() for part in result[field].split(';') if part.strip()))) or None
    return result


def description_sha256(description):
    return hashlib.sha256(json.dumps(description, ensure_ascii=False,
                                     separators=(',', ':')).encode('utf-8')).hexdigest()


def csv_rows(path):
    with Path(path).open(encoding='utf-8-sig', newline='') as stream:
        reader = csv.DictReader(stream)
        headers = reader.fieldnames
        if not headers or any(not field or not field.strip() for field in headers) or len(headers) != len(set(headers)):
            raise ValueError('CSV requires unique nonempty headers')
        rows = list(reader)
        if any(None in row or any(value is None for value in row.values()) for row in rows):
            raise ValueError('CSV row has extra or missing cells')
        return rows


def load_corpus(path):
    path = Path(path)
    rows = json.loads(path.read_text(encoding='utf-8-sig')) if path.suffix == '.json' else csv_rows(path)
    if not isinstance(rows, list) or not rows:
        raise ValueError('Corpus must be a nonempty list')
    result = []
    seen = set()
    for row in rows:
        if 'description' not in row or 'item_count' not in row:
            raise ValueError('Corpus requires description and item_count')
        description = row['description']
        if row.get('description_is_null') == 'true':
            if description not in ('', None):
                raise ValueError('NULL marker contradicts description')
            description = None
        if description is not None and not isinstance(description, str):
            raise ValueError('Description must be text or NULL')
        count = row['item_count']
        if isinstance(count, bool) or not str(count).isdigit() or int(count) <= 0:
            raise ValueError('item_count must be a positive integer')
        key = description_sha256(description)
        if key in seen:
            raise ValueError('Duplicate corpus description')
        seen.add(key)
        result.append((key, description, int(count)))
    return result


def load_gold(labels_path, assignments_path):
    labels = {}
    for row in csv_rows(labels_path):
        key = row.get('label_id', '')
        if not key or key in labels:
            raise ValueError('Missing or duplicate gold label_id')
        if any(field not in row for field in FIELDS):
            raise ValueError('Gold label missing expected field')
        if row.get('review_status') != 'reviewed' or not row.get('reviewed_by', '').strip() or not row.get('review_note', '').strip():
            raise ValueError('Gold labels require independent review metadata')
        expected = canonical_fields(row)
        status = expected['product_type_status']
        if status not in STATUSES:
            raise ValueError('Invalid gold status')
        if status == 'accepted' and not (expected['product_type'] or '').strip():
            raise ValueError('Accepted gold label requires product type')
        if status != 'accepted' and any(expected[field] for field in FIELDS[:-1]):
            raise ValueError('Unreadable and placeholder labels must have empty semantic fields')
        labels[key] = expected
    assignments = {}
    for row in csv_rows(assignments_path):
        key, label = row.get('description_sha256', ''), row.get('label_id', '')
        if len(key) != 64 or any(c not in '0123456789abcdef' for c in key) or key in assignments:
            raise ValueError('Invalid or duplicate assignment hash')
        if label not in labels:
            raise ValueError('Assignment references unknown label')
        assignments[key] = label
    if not labels or not assignments:
        raise ValueError('Gold labels and assignments must not be empty')
    return labels, assignments


def evaluate(corpus_path, manifest_path, labels_path, assignments_path, reader):
    corpus = load_corpus(corpus_path)
    manifest = json.loads(Path(manifest_path).read_text(encoding='utf-8-sig'))
    digest = hashlib.sha256(Path(corpus_path).read_bytes()).hexdigest()
    total = sum(row[2] for row in corpus)
    if manifest.get('sha256') != digest or type(manifest.get('source_row_count')) is not int or manifest['source_row_count'] != total:
        raise ValueError('Corpus SHA or source row count does not match manifest')
    if manifest.get('source') != 'coldlion.item_header':
        raise ValueError('Manifest source must be coldlion.item_header')
    try:
        captured = datetime.fromisoformat(manifest['captured_at'].replace('Z', '+00:00'))
        if captured.tzinfo is None:
            raise ValueError('timezone required')
    except (KeyError, TypeError, ValueError, AttributeError) as error:
        raise ValueError('Manifest requires captured_at with timezone') from error
    labels, assignments = load_gold(labels_path, assignments_path)
    review_reasons = {row['description_sha256']: row.get('review_reason', '') for row in csv_rows(assignments_path)}
    corpus_keys = {row[0] for row in corpus}
    if set(assignments) - corpus_keys:
        raise ValueError('Assignments contain descriptions outside the corpus')
    counts = dict(source_rows=total, distinct_descriptions=len(corpus), null_rows=0,
                  correct=0, wrong=0, unreadable=0, placeholder=0, uncovered=0, errors=0,
                  reviewed_rows=0)
    census = dict(accepted=0, unreadable=0, placeholder=0, invalid=0, errors=0)
    versions = set()
    details = []
    for key, description, count in corpus:
        if description is None:
            counts['null_rows'] += count
        label = assignments.get(key)
        if label is None:
            counts['uncovered'] += count
            details.append(dict(description=description, item_count=count, result='uncovered'))
        else:
            counts['reviewed_rows'] += count
        try:
            actual = reader(description)
            if not isinstance(actual, dict) or any(field not in actual for field in FIELDS):
                raise ValueError('Reader result missing semantic fields')
            observed = canonical_fields(actual)
            status = observed['product_type_status']
            if status not in STATUSES:
                raise ValueError('Invalid reader status')
            if status == 'accepted' and not (observed['product_type'] or '').strip():
                raise ValueError('Accepted reader result requires product type')
            if status != 'accepted' and any(observed[field] for field in FIELDS[:-1]):
                raise ValueError('Unreadable reader result has semantic fields')
            census[status] += count
            version = actual.get('product_type_rules_version')
            if isinstance(version, str) and version:
                versions.add(version)
            if label is None:
                if status == 'unreadable':
                    details.append(dict(description=description, item_count=count,
                                        result='unreviewed_unreadable', actual=observed))
                continue
            expected = labels[label]
            equal = canonical_fields(observed) == expected
            counts['correct' if equal else 'wrong'] += count
            if observed['product_type_status'] in ('unreadable', 'placeholder'):
                counts[observed['product_type_status']] += count
            if not equal or observed['product_type_status'] == 'unreadable':
                details.append(dict(description=description, item_count=count, label_id=label,
                                    result='correct' if equal else 'wrong', expected=expected, actual=observed,
                                    review_reason=review_reasons.get(key, '')))
        except Exception as error:
            counts['errors'] += count
            census['errors'] += count
            # Exception messages can contain private source descriptions.
            details.append(dict(description=description, item_count=count, result='error', error_type=type(error).__name__))
    counts['passed'] = not any(counts[k] for k in ('wrong', 'uncovered', 'errors'))
    module_path = inspect.getsourcefile(reader)
    reader_digest = hashlib.sha256(Path(module_path).read_bytes()).hexdigest() if module_path else None
    return dict(counts=counts, prediction_census=census, rules_versions=sorted(versions),
                reader_module_sha256=reader_digest,
                metric_note='correct/wrong/unreadable/placeholder count independently reviewed rows only; prediction_census includes all rows and is not verified accuracy',
                corpus_sha256=digest, captured_at=manifest['captured_at'],
                labels_sha256=hashlib.sha256(Path(labels_path).read_bytes()).hexdigest(),
                assignments_sha256=hashlib.sha256(Path(assignments_path).read_bytes()).hexdigest()), details


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('corpus', 'manifest', 'labels', 'assignments'):
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--private-details', type=Path)
    parser.add_argument('--strict', action='store_true')
    parser.add_argument('--reader', choices=('current', 'legacy'), default='current')
    args = parser.parse_args(argv)
    try:
        protected = {path.resolve() for path in (args.corpus, args.manifest, args.labels, args.assignments)}
        outputs = [path.resolve() for path in (args.report, args.private_details) if path]
        if any(path in protected for path in outputs) or len(outputs) != len(set(outputs)):
            raise ValueError('Output paths must be distinct from inputs and each other')
        if args.private_details:
            repo = Path(__file__).resolve().parents[2]
            if args.private_details.resolve().is_relative_to(repo):
                raise ValueError('Private details must be written outside the public repository')
            # Fail closed: any git checkout (another worktree, the canonical
            # checkout, or a repository whose remote cannot be judged) may be
            # published, so private details go only to a plain directory.
            target = args.private_details.resolve()
            for ancestor in (target, *target.parents):
                if (ancestor / '.git').exists():
                    raise ValueError('Private details must be written outside every git checkout')
        try:
            from . import read_product_type
        except ImportError:
            import sys
            sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
            from tools.product_type_reader import read_product_type
        if args.reader == 'legacy':
            from tools.product_type_reader.baseline import read_legacy_product_type
            read_product_type = read_legacy_product_type
        result, details = evaluate(args.corpus, args.manifest, args.labels, args.assignments, read_product_type)
        result['reader'] = args.reader
        result['implementation_sha256'] = {
            name: hashlib.sha256((Path(__file__).parent / name).read_bytes()).hexdigest()
            for name in (
                '__init__.py', 'reader.py', 'construction_rules.py',
                'material_rules.py', 'treatment_rules.py', 'legacy.py',
                'baseline.py', 'evaluate.py',
            )
        }
        print(json.dumps(result, sort_keys=True))
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text('# Product-type reader evaluation\n\n' + '\n'.join(
                f'- {key}: {value}' for key, value in result['counts'].items()) + '\n\n' + '\n'.join(
                f'- {key}: {value}' for key, value in result.items() if key != 'counts') + '\n', encoding='utf-8')
        if args.private_details:
            args.private_details.parent.mkdir(parents=True, exist_ok=True)
            args.private_details.write_text(json.dumps(details, ensure_ascii=False, indent=2), encoding='utf-8')
        return 1 if args.strict and not result['counts']['passed'] else 0
    except (ValueError, OSError, csv.Error) as error:
        print('Evaluation failed: ' + type(error).__name__)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
