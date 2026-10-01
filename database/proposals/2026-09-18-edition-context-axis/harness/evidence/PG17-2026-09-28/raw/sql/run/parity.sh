set -u
PSQL_A='psql -X -h 127.0.0.1 -p 5432 -U supabase_admin -d postgres'
PSQL_P='psql -X -h 127.0.0.1 -p 5432 -U postgres -d postgres'
$PSQL_P -q -At -v ON_ERROR_STOP=1 -c "SET search_path = ''" -c 'SET TimeZone = $$UTC$$' -f /work/sql/parity_fingerprint.sql -o /work/out/fp_local.json 2> /work/out/fp_local.err || exit 1
$PSQL_P -q -At -v ON_ERROR_STOP=1 -f /work/sql/2830H_E12P_precheck_section_b.sql -o /work/out/parity_E12P.json 2> /work/out/parity_E12P.err || exit 2
$PSQL_P -q -At -v ON_ERROR_STOP=1 -f /work/sql/2830H_E13P_precheck_section_m.sql -o /work/out/parity_E13P.json 2> /work/out/parity_E13P.err || exit 3
$PSQL_P -q -At -v ON_ERROR_STOP=1 -f /work/sql/L_E00_precheck_inventory.sql -o /work/out/parity_E00.json 2> /work/out/parity_E00.err || exit 4
