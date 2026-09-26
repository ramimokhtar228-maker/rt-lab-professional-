-- RT LAB Clinical Engine V2 - Supabase migration
-- Run in Supabase SQL Editor. Review existing table names before production use.
create extension if not exists pgcrypto;

create table if not exists public.test_reference_ranges (
  id uuid primary key default gen_random_uuid(),
  test_code text not null,
  sex text,
  age_min numeric,
  age_max numeric,
  low numeric,
  high numeric,
  unit text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.test_critical_limits (
  id uuid primary key default gen_random_uuid(),
  test_code text not null unique,
  critical_low numeric,
  critical_high numeric,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.test_calculations (
  id uuid primary key default gen_random_uuid(),
  test_code text not null unique,
  formula_key text not null,
  dependencies jsonb not null default '[]'::jsonb,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.test_validation_rules (
  id uuid primary key default gen_random_uuid(),
  test_code text not null unique,
  rules jsonb not null default '{}'::jsonb,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.test_delta_rules (
  id uuid primary key default gen_random_uuid(),
  test_code text not null unique,
  delta_percent numeric,
  max_interval_days integer default 365,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.result_calculations (
  id uuid primary key default gen_random_uuid(),
  order_id bigint,
  order_test_id bigint,
  test_code text not null,
  formula_key text not null,
  inputs jsonb not null default '{}'::jsonb,
  calculated_value text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

create table if not exists public.result_validation_events (
  id uuid primary key default gen_random_uuid(),
  order_id bigint,
  order_test_id bigint,
  test_code text not null,
  status text not null check (status in ('valid','warning','error')),
  warnings jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

create table if not exists public.delta_check_events (
  id uuid primary key default gen_random_uuid(),
  order_id bigint,
  order_test_id bigint,
  test_code text not null,
  previous_value numeric,
  current_value numeric,
  delta_percent numeric,
  threshold_percent numeric,
  status text not null check (status in ('ok','warning','not_applicable')),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

create table if not exists public.critical_value_events (
  id uuid primary key default gen_random_uuid(),
  order_id bigint,
  order_test_id bigint,
  test_code text not null,
  result_value text,
  flag text not null check (flag in ('critical_low','critical_high')),
  acknowledged boolean not null default false,
  acknowledged_by uuid references auth.users(id),
  acknowledged_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.result_approvals (
  id uuid primary key default gen_random_uuid(),
  order_id bigint not null,
  status text not null check (status in ('approved','rejected')),
  approved_by uuid references auth.users(id),
  approved_at timestamptz not null default now(),
  note text
);

create table if not exists public.report_versions (
  id uuid primary key default gen_random_uuid(),
  order_id bigint not null,
  version_no integer not null,
  status text not null check (status in ('draft','approved','released','superseded')),
  snapshot jsonb not null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(order_id, version_no)
);

create table if not exists public.lis_audit_logs (
  id uuid primary key default gen_random_uuid(),
  order_id bigint,
  entity_type text not null,
  entity_id text,
  action text not null,
  old_data jsonb,
  new_data jsonb,
  reason text,
  actor uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_ref_test on public.test_reference_ranges(test_code);
create index if not exists idx_calc_test on public.test_calculations(test_code);
create index if not exists idx_validation_order on public.result_validation_events(order_id);
create index if not exists idx_delta_order on public.delta_check_events(order_id);
create index if not exists idx_critical_order on public.critical_value_events(order_id);
create index if not exists idx_audit_order on public.lis_audit_logs(order_id);

-- Role helper. Adjust role names to the existing RT LAB profile schema if necessary.
create or replace function public.rtlab_can_approve()
returns boolean language sql stable security definer set search_path=public
as $$
  select exists (
    select 1 from public.rt2_profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.role,'')) in ('admin','manager','lab_doctor','doctor','ceo','gm')
  );
$$;

create or replace function public.rtlab_can_release()
returns boolean language sql stable security definer set search_path=public
as $$
  select exists (
    select 1 from public.rt2_profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.role,'')) in ('admin','manager','ceo','gm')
  );
$$;

alter table public.test_reference_ranges enable row level security;
alter table public.test_critical_limits enable row level security;
alter table public.test_calculations enable row level security;
alter table public.test_validation_rules enable row level security;
alter table public.test_delta_rules enable row level security;
alter table public.result_calculations enable row level security;
alter table public.result_validation_events enable row level security;
alter table public.delta_check_events enable row level security;
alter table public.critical_value_events enable row level security;
alter table public.result_approvals enable row level security;
alter table public.report_versions enable row level security;
alter table public.lis_audit_logs enable row level security;

-- Authenticated staff can read engine configuration.
create policy "staff read engine config" on public.test_reference_ranges for select to authenticated using (true);
create policy "staff read critical limits" on public.test_critical_limits for select to authenticated using (true);
create policy "staff read calculations" on public.test_calculations for select to authenticated using (true);
create policy "staff read validation rules" on public.test_validation_rules for select to authenticated using (true);
create policy "staff read delta rules" on public.test_delta_rules for select to authenticated using (true);

-- Event tables: authenticated staff may insert/read. Production deployments should further scope reads by branch/role.
create policy "staff insert calculation events" on public.result_calculations for insert to authenticated with check (true);
create policy "staff read calculation events" on public.result_calculations for select to authenticated using (true);
create policy "staff insert validation events" on public.result_validation_events for insert to authenticated with check (true);
create policy "staff read validation events" on public.result_validation_events for select to authenticated using (true);
create policy "staff insert delta events" on public.delta_check_events for insert to authenticated with check (true);
create policy "staff read delta events" on public.delta_check_events for select to authenticated using (true);
create policy "staff insert critical events" on public.critical_value_events for insert to authenticated with check (true);
create policy "staff read critical events" on public.critical_value_events for select to authenticated using (true);

create policy "authorized approval insert" on public.result_approvals for insert to authenticated with check (public.rtlab_can_approve());
create policy "staff read approvals" on public.result_approvals for select to authenticated using (true);
create policy "authorized report versions" on public.report_versions for insert to authenticated with check (public.rtlab_can_release() or public.rtlab_can_approve());
create policy "staff read report versions" on public.report_versions for select to authenticated using (true);
create policy "staff insert audit logs" on public.lis_audit_logs for insert to authenticated with check (true);
create policy "staff read audit logs" on public.lis_audit_logs for select to authenticated using (true);

-- Seed core calculation rules.
insert into public.test_calculations(test_code,formula_key,dependencies) values
('LDL','friedewald_ldl','["TC","HDL","TG"]'),
('VLDL','tg_div_5','["TG"]'),
('NON_HDL','tc_minus_hdl','["TC","HDL"]'),
('HOMA_IR','homa_ir','["FBS","FASTING_INSULIN"]'),
('MCV','cbc_mcv','["HCT","RBC"]'),
('MCH','cbc_mch','["HB","RBC"]'),
('MCHC','cbc_mchc','["HB","HCT"]'),
('EGFR','ckd_epi_2021','["CREAT","AGE","SEX"]')
on conflict(test_code) do nothing;

insert into public.test_delta_rules(test_code,delta_percent,max_interval_days) values
('HB',20,90),('WBC',50,30),('PLT',30,90),('CREAT',20,90),('FBS',30,90),('ALT',50,180),('AST',50,180)
on conflict(test_code) do nothing;

-- Critical values are deliberately examples and must be reviewed/approved by the laboratory medical director before clinical production use.
insert into public.test_critical_limits(test_code,critical_low,critical_high) values
('HB',7,20),('WBC',2,30),('PLT',50,1000),('FBS',50,400),('K',2.5,6.5),('NA',120,160)
on conflict(test_code) do nothing;
