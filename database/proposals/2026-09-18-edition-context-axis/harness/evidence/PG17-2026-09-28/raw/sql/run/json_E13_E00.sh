set -u
PSQL_A='psql -X -h 127.0.0.1 -p 5432 -U supabase_admin -d postgres'
PSQL_P='psql -X -h 127.0.0.1 -p 5432 -U postgres -d postgres'
$PSQL_P -q -At -v ON_ERROR_STOP=1 -f /work/sql/L_E00_precheck_inventory.sql -o /work/out/E13_E00.json 2> /work/out/E13_E00.err || exit 1
