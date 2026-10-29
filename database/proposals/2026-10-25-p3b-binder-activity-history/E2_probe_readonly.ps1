<#
================================================================
MMKYU - P3-B S1 - Executor E2 (psql) - SONDA SOMENTE LEITURA
Versao 1.1 (2026-10-25, P3-B-S1-E2-PROBE-SECURITY-CORRECTION-01)
       1.0 (P3-B-S1-LIVE-DRYRUN-EXECUTOR-E2-READINESS-02)

O QUE FAZ, sem escrever nada no banco:
  - usa o psql.exe indicado explicitamente (padrao: PostgreSQL 17 do Windows);
  - exige SSL verify-full com o certificado raiz do projeto (sem fallback);
  - roda o psql num PROCESSO FILHO com ambiente proprio: nenhuma variavel
    PG* e criada, alterada ou removida na sessao do PowerShell;
  - descarta do ambiente do filho tudo o que poderia injetar credencial ou
    configuracao herdada (PGPASSWORD, PGPASSFILE, PGSERVICE, PGOPTIONS, PSQLRC,
    certificados de cliente...) e informa quais existiam (so os NOMES);
  - a senha e digitada no prompt do proprio psql (-W): nao passa pelo
    PowerShell, nao vai para variavel de ambiente, arquivo ou log;
  - a sessao do filho e forcada a somente leitura
    (PGOPTIONS = -c default_transaction_read_only=on);
  - envia ao banco APENAS os 3 SELECTs de $Queries;
  - confere: mesmo pg_backend_pid nos 3 comandos, usuario/banco postgres,
    porta 5432, servidor 17.x, client_encoding UTF8, somente leitura ativo,
    SSL ativo, ultimo ledger 5266_..., impressao digital do LIVE = 1.

NAO executa o ensaio. NAO usa o PATH para achar o psql.

Uso (PowerShell, na pasta deste arquivo):
  .\E2_probe_readonly.ps1 -PgHost <host> -PgUser <usuario> -SslRootCert <caminho\prod-ca-2021.crt>
     [-PsqlPath 'C:\Program Files\PostgreSQL\17\bin\psql.exe']
  Host/usuario aceitos (porta sempre 5432; 6543 nunca):
    conexao direta ........ db.<ref>.supabase.co          + postgres
    pooler em modo SESSAO . aws-N-<regiao>.pooler.supabase.com + postgres.<ref>
Saida: E2_probe_<data>.txt na mesma pasta (sem senha).
Codigos de saida: 0 sonda conforme | 10 sonda divergente | 90 parametro/arquivo
                  91 psql invalido | 92 certificado | 93 host/usuario | outro: codigo do psql
================================================================
#>
param(
  [Parameter(Mandatory = $true)] [string] $PgHost,
  [Parameter(Mandatory = $true)] [string] $PgUser,
  [Parameter(Mandatory = $true)] [string] $SslRootCert,
  [string] $PsqlPath = 'C:\Program Files\PostgreSQL\17\bin\psql.exe'
)
Set-StrictMode -Version Latest

function Stop-Probe([int] $Code, [string] $Message) {
  Write-Host "STOP ($Code): $Message"
  exit $Code
}

# Unicas instrucoes enviadas ao banco (todas SELECT; conferido abaixo e no static check)
$Queries = @(
  "select 'S1', pg_backend_pid(), current_user, current_database(), inet_server_port(), current_setting('server_version'), current_setting('client_encoding'), current_setting('default_transaction_read_only')",
  "select 'S2', pg_backend_pid(), coalesce((select ssl::text from pg_stat_ssl where pid = pg_backend_pid()), 'none'), coalesce((select version from pg_stat_ssl where pid = pg_backend_pid()), 'none')",
  "select 'S3', pg_backend_pid(), (select name from supabase_migrations.schema_migrations order by version desc limit 1), (select count(*) from public.collection_layout_catalog_incorporation where layout_id = '3425193a-5c44-4930-8574-22909ffdca21')"
)
foreach ($q in $Queries) {
  if ($q -notmatch '^select\s' -or $q -match '(?i)\b(insert|update|delete|merge|create|alter|drop|truncate|grant|revoke|copy|call|do|set|reset|begin|commit|rollback|vacuum|analyze|lock|listen|notify|execute|prepare)\b' -or $q.Contains('"') -or $q.Contains(';') -or $q.Contains('\')) {
    Stop-Probe 90 'consulta da sonda fora do padrao somente leitura'
  }
}

# 1. Cliente psql explicito (sem PATH)
if (-not (Test-Path -LiteralPath $PsqlPath -PathType Leaf)) { Stop-Probe 91 "psql.exe nao encontrado em: $PsqlPath" }
$PsqlPath = (Resolve-Path -LiteralPath $PsqlPath).ProviderPath
if ([System.IO.Path]::GetFileName($PsqlPath) -ne 'psql.exe') { Stop-Probe 91 "o arquivo indicado nao e psql.exe: $PsqlPath" }
$verText = (& $PsqlPath --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { Stop-Probe 91 "psql --version falhou: $verText" }
$verMatch = [regex]::Match($verText, 'psql \(PostgreSQL\) (\d+)\.')
if (-not $verMatch.Success -or [int]$verMatch.Groups[1].Value -lt 17) { Stop-Probe 91 "psql 17+ exigido. Encontrado: $verText" }

# 2. SSL verify-full obrigatorio
if (-not (Test-Path -LiteralPath $SslRootCert -PathType Leaf)) { Stop-Probe 92 "certificado raiz nao encontrado: $SslRootCert (sem ele a sonda nao conecta)" }
$SslRootCert = (Resolve-Path -LiteralPath $SslRootCert).ProviderPath

# 3. Host e usuario coerentes (direta ou pooler em modo sessao; nunca outro destino)
$isDirect = $PgHost -match '^db\.[a-z0-9]{20}\.supabase\.co$'
$isPooler = $PgHost -match '^aws-\d+-[a-z0-9-]+\.pooler\.supabase\.com$'
if (-not ($isDirect -or $isPooler)) { Stop-Probe 93 "host fora do padrao Supabase aceito: $PgHost" }
if ($isDirect -and $PgUser -ne 'postgres') { Stop-Probe 93 'conexao direta exige usuario postgres' }
if ($isPooler -and $PgUser -notmatch '^postgres\.[a-z0-9]{20}$') { Stop-Probe 93 'pooler em modo sessao exige usuario postgres.<ref>' }
if ($isDirect) {
  $refFromHost = $PgHost.Split('.')[1]
  Write-Host "Projeto (pelo host): $refFromHost"
} else {
  Write-Host "Projeto (pelo usuario): $($PgUser.Split('.')[1])"
}

# 4. Ambiente do PROCESSO FILHO (a sessao do PowerShell nao e tocada)
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $PsqlPath
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.RedirectStandardInput = $false          # o prompt de senha do psql usa o console
$inherited = @()
foreach ($name in @($psi.EnvironmentVariables.Keys)) {
  if ($name -match '^(?i)(PG.*|PSQLRC|PSQL_HISTORY|PSQL_PAGER|PAGER)$') {
    $inherited += $name
    $psi.EnvironmentVariables.Remove($name)
  }
}
if ($inherited.Count -gt 0) { Write-Host ("Variaveis herdadas descartadas (apenas no processo da sonda): " + (($inherited | Sort-Object) -join ', ')) }
$noFile = Join-Path ([System.IO.Path]::GetTempPath()) ('mmkyu_no_such_file_' + [guid]::NewGuid().ToString('N'))
$psi.EnvironmentVariables['PGHOST'] = $PgHost
$psi.EnvironmentVariables['PGPORT'] = '5432'
$psi.EnvironmentVariables['PGDATABASE'] = 'postgres'
$psi.EnvironmentVariables['PGUSER'] = $PgUser
$psi.EnvironmentVariables['PGSSLMODE'] = 'verify-full'
$psi.EnvironmentVariables['PGSSLROOTCERT'] = $SslRootCert
$psi.EnvironmentVariables['PGSSLCERT'] = $noFile           # nenhum certificado de cliente
$psi.EnvironmentVariables['PGSSLKEY'] = $noFile
$psi.EnvironmentVariables['PGPASSFILE'] = $noFile          # nenhum pgpass.conf
$psi.EnvironmentVariables['PGCLIENTENCODING'] = 'UTF8'
$psi.EnvironmentVariables['PGAPPNAME'] = 'mmkyu_e2_probe'
$psi.EnvironmentVariables['PGCONNECT_TIMEOUT'] = '10'
$psi.EnvironmentVariables['PGOPTIONS'] = '-c default_transaction_read_only=on'

$argParts = @('-X', '-W', '-A', '-t', '-F', '|', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose')
foreach ($q in $Queries) { $argParts += @('-c', $q) }
$psi.Arguments = ($argParts | ForEach-Object { '"' + $_ + '"' }) -join ' '

# 5. Execucao unica (sem repeticao)
Write-Host 'O psql vai pedir a senha do banco (digitacao nao aparece na tela).'
$proc = [System.Diagnostics.Process]::Start($psi)
$stdoutTask = $proc.StandardOutput.ReadToEndAsync()
$stderrTask = $proc.StandardError.ReadToEndAsync()
$proc.WaitForExit()
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
$code = $proc.ExitCode

# 6. Conferencia
$rows = @{}
foreach ($line in ($stdout -split "`r?`n")) {
  if ($line -match '^(S[123])\|') { $rows[$Matches[1]] = $line.Split('|') }
}
$checks = [ordered]@{}
$checks['psql_exit_0'] = ($code -eq 0)
$checks['tres_linhas'] = ($rows.Count -eq 3)
if ($rows.Count -eq 3) {
  $s1 = $rows['S1']; $s2 = $rows['S2']; $s3 = $rows['S3']
  $checks['mesmo_pid'] = ($s1[1] -eq $s2[1] -and $s2[1] -eq $s3[1])
  $checks['usuario_postgres'] = ($s1[2] -eq 'postgres')
  $checks['banco_postgres'] = ($s1[3] -eq 'postgres')
  $checks['porta_5432'] = ($s1[4] -eq '5432')
  $checks['servidor_17'] = ($s1[5] -like '17.*')
  $checks['client_encoding_utf8'] = ($s1[6] -eq 'UTF8')
  $checks['somente_leitura'] = ($s1[7] -eq 'on')
  $checks['ssl_ativo'] = ($s2[2] -eq 'true')
  $checks['ledger_5266'] = ($s3[2] -eq '5266_create_binder_catalog_reconciliation_apply')
  $checks['fingerprint_live'] = ($s3[3] -eq '1')
}
$ok = -not ($checks.Values -contains $false)
$out = Join-Path $PSScriptRoot ("E2_probe_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$report = @(
  "sonda=E2_probe_readonly.ps1 v1.1", "psql=$PsqlPath", "psql_version=$verText", "host=$PgHost", "user=$PgUser",
  "sslmode=verify-full", "sslrootcert=$SslRootCert", "variaveis_herdadas_descartadas=$((($inherited | Sort-Object) -join ','))",
  "psql_exit=$code", "--- stdout ---", $stdout.Trim(), "--- stderr ---", $stderr.Trim(), "--- checagens ---"
)
foreach ($k in $checks.Keys) { $report += ("{0}={1}" -f $k, $checks[$k]) }
$report += ("resultado={0}" -f ($(if ($ok) { 'SONDA_CONFORME' } else { 'SONDA_DIVERGENTE' })))
$report | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("Resultado: {0} | relatorio: {1}" -f ($(if ($ok) { 'SONDA_CONFORME' } else { 'SONDA_DIVERGENTE' })), $out)
if ($ok) { exit 0 }
if ($code -ne 0) { exit $code }
exit 10
