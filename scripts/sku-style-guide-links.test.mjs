import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const schema = readFileSync(new URL('../supabase/migrations/20261030040817_sku_style_guide_links_schema.sql', import.meta.url), 'utf8');
const resolver = readFileSync(new URL('../supabase/migrations/20261030040818_sku_style_guide_links_resolver.sql', import.meta.url), 'utf8');
const sql = schema.replace(/--[^\n]*/g, '');
const view = sql.match(/create or replace view plm\.asset_file_style_guide_index[\s\S]*?;/i)[0];

test('internal invoker index cannot advertise browser access to restricted ASGARD data', () => {
  assert.match(view, /security_invoker = true/);
  assert.match(view, /plm\.marvel_asgard_node_asset_observation/);
  assert.match(sql, /revoke all on plm\.asset_file_style_guide_index from public, anon, authenticated;/);
  assert.match(sql, /grant select on plm\.asset_file_style_guide_index to service_role;/);
  assert.doesNotMatch(sql, /grant[^;]*on plm\.asset_file_style_guide_index to[^;]*authenticated/);
  assert.match(sql, /grant select on public\.sku_style_guide_links to authenticated;/);
});

test('direct-source index retains all eight direct portals and excludes inferred candidates', () => {
  const portals = [...view.matchAll(/'([^']+)'(?:::text)?\s*(?:as source_system)?\s*,/g)]
    .map(m => m[1]).filter(s => !s.includes(' '));
  for (const name of ['disney_dcpvault', 'lucasfilm_dcpvault', 'marvel_dcpvault', 'marvel_asgard', 'nbcu', 'warner_starlabs', 'peanuts_tenovos', 'sesame_netx']) {
    assert.ok(portals.includes(name), `missing direct portal ${name}`);
  }
  assert.doesNotMatch(view, /plm\.(sega_|wildbrain_)/);
  assert.equal((view.match(/union all/gi) || []).length, 7);
});

test('nightly resolver remains service-only and scheduled after file resolution', () => {
  assert.match(resolver, /revoke all on function public\.resolve_sku_style_guide_links\(\) from public, anon, authenticated;/);
  assert.match(resolver, /grant execute on function public\.resolve_sku_style_guide_links\(\) to service_role, postgres;/);
  assert.match(resolver, /'resolve-sku-style-guide-links-nightly',\s*'30 4 \* \* \*',\s*\$\$select public\.resolve_sku_style_guide_links\(\)\$\$/);
});
