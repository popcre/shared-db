select
  to_regclass('plm.customs_benchmark_dataset') is not null
  and to_regclass('plm.customs_benchmark_artifact') is not null
  and to_regclass('plm.customs_benchmark_observation') is not null
  and not has_table_privilege('anon','plm.customs_benchmark_artifact','SELECT')
  and not has_table_privilege('authenticated','plm.customs_benchmark_artifact','SELECT')
  as passed;
