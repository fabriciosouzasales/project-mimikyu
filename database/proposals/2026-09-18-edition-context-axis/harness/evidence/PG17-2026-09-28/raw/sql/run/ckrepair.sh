set -u
PSQL_A='psql -X -h 127.0.0.1 -p 5432 -U supabase_admin -d postgres'
PSQL_P='psql -X -h 127.0.0.1 -p 5432 -U postgres -d postgres'
$PSQL_P -v ON_ERROR_STOP=1 -f /work/sql/run/ckrepair.sql > /work/out/ckrepair.log 2>&1 || exit 1
