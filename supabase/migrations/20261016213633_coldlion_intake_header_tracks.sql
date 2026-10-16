-- ColdLion /orderHistory gained createdFrom/createdTo and modifiedFrom/modifiedTo
-- (sales order header timestamps, ColdLion 2026-10-16). The order-intake poll adds two
-- tracks that use them: 'created' and 'modified'. Each keeps one bookkeeping row
-- (from_date = the fixed wide start-window floor), upserted every run.

alter table coldlion.intake_window_state
  drop constraint coldlion_intake_window_state_track_domain;

alter table coldlion.intake_window_state
  add constraint coldlion_intake_window_state_track_domain
  check (track in ('trailing', 'forward', 'created', 'modified'));
