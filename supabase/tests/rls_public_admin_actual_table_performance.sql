-- #4890 technical qualification only; all live/historical acceptance stays #4427.
-- Existing native ephemeral CI only. The driver rejects all shared/live targets.
\! python3 scripts/qualify_rls4427_actual_tables.py
\if :SHELL_ERROR
  \echo '4427 actual-table qualification failed; no acceptance may be claimed'
  do $failure$ begin raise exception '4427 driver failure'; end $failure$;
\endif
