-- RT LAB LIS Production V7
-- Adds production workflow persistence around the existing V6 engine.
-- Review all clinical limits/reference intervals before clinical use.

create table if not exists public.rt_lab_specimens (
  id text primary key,
  order_id text not null,
  barcode text,
  status text not null default 'COLLECTED',
  condition text default 'ACCEPTED',
  collector text,
  collected_at timestamptz,
  received_at timestamptz,
  rejection_reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_rt_lab_specimens_order on public.rt_lab_specimens(order_id);
create index if not exists idx_rt_lab_specimens_barcode on public.rt_lab_specimens(barcode);

create table if not exists public.rt_lab_result_versions (
  id text primary key,
  order_id text not null,
  version_no integer not null,
  status text not null default 'DRAFT',
  report_html text,
  report_json jsonb not null default '{}'::jsonb,
  approved_by text,
  approved_at timestamptz,
  released_by text,
  released_at timestamptz,
  created_by text,
  created_at timestamptz not null default now(),
  unique(order_id, version_no)
);
create index if not exists idx_rt_lab_result_versions_order on public.rt_lab_result_versions(order_id);

create table if not exists public.rt_lab_analyzer_queue (
  id bigserial primary key,
  order_id text,
  specimen_id text,
  analyzer text,
  message_id text,
  test_code text,
  raw_result text,
  unit text,
  status text not null default 'QUEUED',
  mapped_result jsonb not null default '{}'::jsonb,
  error_message text,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  processed_by text
);
create index if not exists idx_rt_lab_analyzer_queue_status on public.rt_lab_analyzer_queue(status);
create index if not exists idx_rt_lab_analyzer_queue_order on public.rt_lab_analyzer_queue(order_id);

create table if not exists public.rt_lab_reflex_rules (
  id bigserial primary key,
  test_code text not null,
  trigger_type text not null,
  trigger_json jsonb not null default '{}'::jsonb,
  reflex_test_code text not null,
  priority integer not null default 100,
  active boolean not null default true,
  approved boolean not null default false,
  created_by text,
  approved_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_rt_lab_reflex_rules_test on public.rt_lab_reflex_rules(test_code);

create table if not exists public.rt_lab_result_events (
  id bigserial primary key,
  order_id text,
  test_code text,
  event_type text not null,
  old_value text,
  new_value text,
  metadata jsonb not null default '{}'::jsonb,
  actor text,
  created_at timestamptz not null default now()
);
create index if not exists idx_rt_lab_result_events_order on public.rt_lab_result_events(order_id);

-- RLS: authenticated staff can read production records.
alter table public.rt_lab_specimens enable row level security;
alter table public.rt_lab_result_versions enable row level security;
alter table public.rt_lab_analyzer_queue enable row level security;
alter table public.rt_lab_reflex_rules enable row level security;
alter table public.rt_lab_result_events enable row level security;

do $$ begin
  create policy rt_lab_specimens_select on public.rt_lab_specimens for select to authenticated using (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy rt_lab_specimens_write on public.rt_lab_specimens for all to authenticated using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy rt_lab_result_versions_select on public.rt_lab_result_versions for select to authenticated using (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy rt_lab_result_versions_write on public.rt_lab_result_versions for all to authenticated using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy rt_lab_analyzer_queue_select on public.rt_lab_analyzer_queue for select to authenticated using (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy rt_lab_analyzer_queue_write on public.rt_lab_analyzer_queue for all to authenticated using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy rt_lab_reflex_rules_select on public.rt_lab_reflex_rules for select to authenticated using (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy rt_lab_reflex_rules_write on public.rt_lab_reflex_rules for all to authenticated using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy rt_lab_result_events_select on public.rt_lab_result_events for select to authenticated using (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy rt_lab_result_events_write on public.rt_lab_result_events for all to authenticated using (true) with check (true);
exception when duplicate_object then null; end $$;

-- RT LAB Test Master (required by the V7 UI)
create table if not exists public.rt_lab_test_master (
  test_code text primary key, test_name_en text not null, department text,
  test_type text not null default 'Single', specimen text, unit text, method text, analyzer text,
  result_type text not null default 'numeric', decimal_places integer not null default 0,
  price numeric(12,2) not null default 0, tat_min integer not null default 0, loinc text,
  fasting_required boolean not null default false, active boolean not null default true,
  approved boolean not null default false, version integer not null default 1,
  reference_ranges jsonb not null default '[]'::jsonb, critical_rules jsonb not null default '[]'::jsonb,
  delta_rules jsonb not null default '[]'::jsonb, calculations jsonb not null default '[]'::jsonb,
  validation_rules jsonb not null default '[]'::jsonb, created_by text, updated_by text,
  approved_by text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), approved_at timestamptz
);
create index if not exists idx_rt_lab_test_master_department on public.rt_lab_test_master(department);
create index if not exists idx_rt_lab_test_master_active on public.rt_lab_test_master(active, approved);
create table if not exists public.rt_lab_test_audit (
  id bigserial primary key, test_code text not null, action text not null, old_data jsonb, new_data jsonb,
  actor text, created_at timestamptz not null default now()
);
create index if not exists idx_rt_lab_test_audit_code on public.rt_lab_test_audit(test_code, created_at desc);
alter table public.rt_lab_test_master enable row level security;
alter table public.rt_lab_test_audit enable row level security;
drop policy if exists rt_lab_test_master_read on public.rt_lab_test_master;
create policy rt_lab_test_master_read on public.rt_lab_test_master for select to authenticated using (true);
drop policy if exists rt_lab_test_master_write on public.rt_lab_test_master;
create policy rt_lab_test_master_write on public.rt_lab_test_master for all to authenticated using (exists (select 1 from public.rt2_profiles p where p.id=auth.uid() and lower(coalesce(p.role,'')) in ('ceo','admin','lab_doctor'))) with check (exists (select 1 from public.rt2_profiles p where p.id=auth.uid() and lower(coalesce(p.role,'')) in ('ceo','admin','lab_doctor')));
drop policy if exists rt_lab_test_audit_read on public.rt_lab_test_audit;
create policy rt_lab_test_audit_read on public.rt_lab_test_audit for select to authenticated using (true);
drop policy if exists rt_lab_test_audit_insert on public.rt_lab_test_audit;
create policy rt_lab_test_audit_insert on public.rt_lab_test_audit for insert to authenticated with check (exists (select 1 from public.rt2_profiles p where p.id=auth.uid() and lower(coalesce(p.role,'')) in ('ceo','admin','lab_doctor')));
