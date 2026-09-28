-- RT LAB NORMALIZED DATA ENGINE V1
-- Run once in the same Supabase project used by RT LAB.
-- Legacy source remains in rtlab_data until migration is verified.

create table if not exists public.rt_patients (
  id text primary key,
  code text,
  name text not null,
  phone text,
  age text,
  gender text,
  dob date,
  address text,
  notes text,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists rt_patients_name_idx on public.rt_patients using gin (to_tsvector('simple', coalesce(name,'')));
create index if not exists rt_patients_phone_idx on public.rt_patients(phone);
create index if not exists rt_patients_code_idx on public.rt_patients(code);
create index if not exists rt_patients_updated_idx on public.rt_patients(updated_at desc);

create table if not exists public.rt_orders (
  id text primary key,
  number text,
  patient_id text,
  status text,
  pay_status text,
  total numeric,
  order_date date,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists rt_orders_patient_idx on public.rt_orders(patient_id);
create index if not exists rt_orders_status_idx on public.rt_orders(status);
create index if not exists rt_orders_number_idx on public.rt_orders(number);
create index if not exists rt_orders_date_idx on public.rt_orders(order_date desc);
create index if not exists rt_orders_updated_idx on public.rt_orders(updated_at desc);

create table if not exists public.rt_tests (
  id text primary key,
  code text,
  name text,
  department text,
  price numeric,
  unit text,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists rt_tests_code_idx on public.rt_tests(code);
create index if not exists rt_tests_name_idx on public.rt_tests using gin (to_tsvector('simple', coalesce(name,'')));
create index if not exists rt_tests_department_idx on public.rt_tests(department);

create table if not exists public.rt_appointments (
  id text primary key,
  status text,
  appointment_date date,
  patient_id text,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists rt_appt_status_idx on public.rt_appointments(status);
create index if not exists rt_appt_date_idx on public.rt_appointments(appointment_date desc);

-- Generic updated_at trigger.
create or replace function public.rt_touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end $$;

drop trigger if exists rt_patients_touch on public.rt_patients;
create trigger rt_patients_touch before update on public.rt_patients for each row execute function public.rt_touch_updated_at();
drop trigger if exists rt_orders_touch on public.rt_orders;
create trigger rt_orders_touch before update on public.rt_orders for each row execute function public.rt_touch_updated_at();
drop trigger if exists rt_tests_touch on public.rt_tests;
create trigger rt_tests_touch before update on public.rt_tests for each row execute function public.rt_touch_updated_at();
drop trigger if exists rt_appt_touch on public.rt_appointments;
create trigger rt_appt_touch before update on public.rt_appointments for each row execute function public.rt_touch_updated_at();

-- Initial migration from the old single JSON document.
-- Safe to run repeatedly because all writes use upsert.
insert into public.rt_patients(id,code,name,phone,age,gender,dob,address,notes,data)
select
  coalesce(x->>'id', x->>'code', md5(x::text)),
  x->>'code', coalesce(x->>'name',''), x->>'phone', x->>'age', x->>'gender',
  nullif(x->>'dob','')::date, x->>'address', x->>'notes', x
from public.rtlab_data r
cross join lateral jsonb_array_elements(coalesce(r.data->'patients','[]'::jsonb)) x
where r.id='main'
on conflict(id) do update set data=excluded.data, code=excluded.code, name=excluded.name, phone=excluded.phone,
 age=excluded.age, gender=excluded.gender, dob=excluded.dob, address=excluded.address, notes=excluded.notes;

insert into public.rt_orders(id,number,patient_id,status,pay_status,total,order_date,data)
select
  coalesce(x->>'id', x->>'number', md5(x::text)),
  x->>'number', x->>'patientId', x->>'status', x->>'payStatus',
  nullif(x->>'total','')::numeric,
  coalesce(nullif(x->>'date','')::date, nullif(x->>'created','')::timestamptz::date), x
from public.rtlab_data r
cross join lateral jsonb_array_elements(coalesce(r.data->'orders','[]'::jsonb)) x
where r.id='main'
on conflict(id) do update set data=excluded.data, number=excluded.number, patient_id=excluded.patient_id,
 status=excluded.status, pay_status=excluded.pay_status, total=excluded.total, order_date=excluded.order_date;

insert into public.rt_tests(id,code,name,department,price,unit,data)
select
  coalesce(x->>'id', x->>'code', md5(x::text)), x->>'code',
  coalesce(x->>'name',x->>'test_name',''), x->>'department',
  nullif(x->>'price','')::numeric, x->>'unit', x
from public.rtlab_data r
cross join lateral jsonb_array_elements(coalesce(r.data->'tests', r.data->'testCatalog','[]'::jsonb)) x
where r.id='main'
on conflict(id) do update set data=excluded.data, code=excluded.code, name=excluded.name,
 department=excluded.department, price=excluded.price, unit=excluded.unit;

insert into public.rt_appointments(id,status,appointment_date,patient_id,data)
select
  coalesce(x->>'id', md5(x::text)), x->>'status',
  nullif(coalesce(x->>'date',x->>'appointmentDate'),'')::date,
  x->>'patientId', x
from public.rtlab_data r
cross join lateral jsonb_array_elements(coalesce(r.data->'appointments','[]'::jsonb)) x
where r.id='main'
on conflict(id) do update set data=excluded.data, status=excluded.status,
 appointment_date=excluded.appointment_date, patient_id=excluded.patient_id;

-- RLS: enable and allow the same anon/publishable client used by the current app.
-- Tighten these policies later when staff auth is fully enforced.
alter table public.rt_patients enable row level security;
alter table public.rt_orders enable row level security;
alter table public.rt_tests enable row level security;
alter table public.rt_appointments enable row level security;

drop policy if exists rt_patients_client on public.rt_patients;
create policy rt_patients_client on public.rt_patients for all to anon, authenticated using (true) with check (true);
drop policy if exists rt_orders_client on public.rt_orders;
create policy rt_orders_client on public.rt_orders for all to anon, authenticated using (true) with check (true);
drop policy if exists rt_tests_client on public.rt_tests;
create policy rt_tests_client on public.rt_tests for all to anon, authenticated using (true) with check (true);
drop policy if exists rt_appointments_client on public.rt_appointments;
create policy rt_appointments_client on public.rt_appointments for all to anon, authenticated using (true) with check (true);
