# DAML Supabase-Only Backend Cleanup

This patch removes the remaining Flutter-side Render / Node / MongoDB fallback traffic from the latest `lib(20).zip`.

## Apply from the Flutter project root

```bash
cd ~/Desktop/daml_clean
unzip -o ~/Downloads/daml-supabase-only-cleanup-fix.zip -d .
flutter clean
flutter pub get
flutter run
```

No new Supabase SQL is required for this patch.

## What changed

- `ApiService` is now a Supabase-only compatibility facade.
- Daily reports, monthly reports, Zanaco data, branch comments, client dashboard data,
  loan search, notifications and admin client directory all go directly to Supabase.
- Old generic HTTP methods and old API routes were removed.
- Old Render URL and Node/Mongo endpoint code were removed.
- `ApiClient` was retired and now contains no network client code.
- Auth login/signup now use Supabase Auth only.
- Old remote auth health-check/login/register fallbacks were removed.
- Existing Hive offline report queue/cache remains.
- Existing Firebase Messaging remains; it is unrelated to the retired database backend.

## Important behavior

### Online
Flutter -> Supabase

### Offline reports
Flutter -> Hive local queue -> Supabase when connectivity returns

There is no secondary web API fallback.

## Verify after applying

From the project root:

```bash
grep -RniE "onrender|directaccessapi|mongodb|/api/|package:http/http.dart|Uri\.parse\(|http\." lib
```

Expected result: no old backend/network-client matches.

Then test:

1. Client login.
2. Client dashboard.
3. Application PDF submission.
4. Admin applications and notifications.
5. Branch daily report submission.
6. Branch monthly report submission.
7. Zanaco distribution.
8. Offline report save, then reconnect and sync.

## Files changed

- `lib/screens/branch/monthly_report_detail_screen.dart`
- `lib/screens/branch/widgets/branch_summery.dart`
- `lib/services/api_client.dart`
- `lib/services/api_service.dart`
- `lib/services/auth_service.dart`
- `lib/services/remote_storage.dart`
- `lib/services/supabase_daml_service.dart`
- `lib/services/sync_service.dart`
