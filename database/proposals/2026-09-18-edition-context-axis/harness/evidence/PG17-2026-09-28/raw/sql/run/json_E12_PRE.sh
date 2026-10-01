set -u
PSQL_A='psql -X -h 127.0.0.1 -p 5432 -U supabase_admin -d postgres'
PSQL_P='psql -X -h 127.0.0.1 -p 5432 -U postgres -d postgres'
$PSQL_P -q -At -v ON_ERROR_STOP=1 -f /work/sql/2830H_E12P_precheck_section_b.sql -o /work/out/E12_PRE.json 2> /work/out/E12_PRE.err || exit 1
