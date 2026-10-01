set -u
PSQL_A='psql -X -h 127.0.0.1 -p 5432 -U supabase_admin -d postgres'
PSQL_P='psql -X -h 127.0.0.1 -p 5432 -U postgres -d postgres'
$PSQL_P -v ON_ERROR_STOP=1 -c '\timing on' -f /work/sql/P9B_M1_M3.sql > /work/out/p9b.txt 2>&1
