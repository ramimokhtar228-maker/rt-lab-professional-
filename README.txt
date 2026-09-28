RT LAB LIS — NORMALIZED DATA ENGINE V8

Files:
1) index.html — patched RT LAB LIS with normalized Supabase data engine.
2) RT_LAB_NORMALIZED_ENGINE.sql — run ONCE in the same Supabase project.

IMPORTANT:
The SQL creates rt_patients, rt_orders, rt_tests and rt_appointments and migrates the old rtlab_data JSON document.
After the SQL succeeds, open index.html. The app will read Patients/Orders/Tests by page from PostgreSQL instead of downloading the entire rtlab_data object.

The old rtlab_data table is NOT deleted.

Operational changes:
- 30-row server pagination.
- Server-side patient search by name/phone/code.
- Server-side order filtering and pagination.
- Single-record fetch for patient/order details.
- Normalized write-through for current page entities.
- No bulk JSON cloudPush for normalized mode.
- LocalStorage is only a small local cache, not the cloud database.

Before production:
- Verify the migration row counts in Supabase.
- Test save/edit/delete/refresh with a test patient and order.
- Then tighten RLS policies to match the final staff roles.
