<#
================================================================
MMKYU - P3-B S1 - Executor E2 (psql) - ENSAIO LIVE COM REVERSAO TOTAL
Versao 1.0 (2026-10-25, P3-B-S1-LIVE-DRYRUN-EXECUTOR-E2-READINESS-02)
STATUS: PREPARADO. NAO EXECUTAR sem autorizacao especifica de Fabricio
        para o ENSAIO (nao abre G8). Exige -AuthorizationId e confirmacao
        digitada.

O QUE FAZ, nesta ordem, uma unica vez (sem nenhuma repeticao automatica):
  1. Confere o SHA-256 do arquivo do ensaio (copia em caminho sem espacos).
  2. Confere psql 17+.
  3. Limpa o ambiente (PGOPTIONS, PSQLRC etc.) e fixa a conexao.
  4. Pede a senha na tela (memoria apenas) e a confirmacao digitada.
  5. Executa UM processo psql:
       psql -X -v ON_ERROR_STOP=1 -v ON_ERROR_ROLLBACK=off
            -v VERBOSITY=verbose -f <arquivo>
     -X ignora psqlrc; sem -1/--single-transaction; uma sessao do inicio ao fim;
     o processo termina e a conexao fecha (D5).
  6. Classifica o resultado (secao CLASSIFICACAO) e grava um resumo.
     MSDRYRUN valido NAO e PASS: e so a condicao para o G-POST.
NAO grava senha, token ou connection string em arquivo.

Uso:
  .\E2_run_live_dryrun_s1.ps1 -DryRunFile C:\mmkyu\dryrun\LIVE_DRYRUN_S1_rollback.sql `
     -OutDir C:\mmkyu\dryrun\out -PgHost <host> -PgUser <usuario> `
     [-SslRootCert C:\mmkyu\dryrun\prod-ca-2021.crt] -AuthorizationId <id-da-autorizacao>
================================================================
#>
param(
  [Parameter(Mandatory = $true)] [string] $DryRunFile,
  [Parameter(Mandatory = $true)] [string] $OutDir,
  [Parameter(Mandatory = $true)] [string] $PgHost,
  [Parameter(Mandatory = $true)] [string] $PgUser,
  [string] $SslRootCert = '',
  [Parameter(Mandatory = $true)] [string] $AuthorizationId
)
Set-StrictMode -Version Latest
$ExpectedSha = 'ddd0dbf2ef5346f5c3536d8b2d1d62ee3eab1cbc5ecc9d732d9a598e1322f74b'
$AppName = 'mmkyu_dryrun_s1_e2'

function Stop-Run([int] $code, [string] $msg) { Write-Host "STOP ($code): $msg"; exit $code }

# 1. Arquivo e hash
if ($DryRunFile -match '\s' -or $OutDir -match '\s') { Stop-Run 90 'caminhos nao podem ter espacos (copiar para C:\mmkyu\dryrun\)' }
if ($DryRunFile -match '[^\x20-\x7E]' -or $OutDir -match '[^\x20-\x7E]') { Stop-Run 90 'caminhos devem ser ASCII' }
if (-not (Test-Path -LiteralPath $DryRunFile)) { Stop-Run 90 'arquivo do ensaio nao encontrado' }
$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $DryRunFile).Hash.ToLower()
if ($sha -ne $ExpectedSha) { Stop-Run 90 "SHA-256 divergente: $sha" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# 2. psql
if (-not (Get-Command psql -ErrorAction SilentlyContinue)) { Stop-Run 91 'psql nao encontrado' }
$ver = (& psql --version) 2>&1 | Out-String
if ($ver -notmatch 'psql \(PostgreSQL\) (\d+)\.' -or [int]$Matches[1] -lt 17) { Stop-Run 91 "psql 17+ exigido: $ver" }

# 3. Ambiente
foreach ($v in 'PGOPTIONS','PGSERVICE','PGSERVICEFILE','PGSYSCONFDIR','PGHOSTADDR','PGDATABASE','PGPORT','PGUSER','PGHOST','PGSSLMODE','PGSSLROOTCERT','PGTARGETSESSIONATTRS','PSQLRC','PGPASSFILE') {
  Remove-Item "Env:$v" -ErrorAction SilentlyContinue
}
$env:PGHOST = $PgHost
$env:PGPORT = '5432'                      # 6543 (pooler em modo transacao) nunca
$env:PGDATABASE = 'postgres'
$env:PGUSER = $PgUser
$env:PGCLIENTENCODING = 'UTF8'            # o arquivo tem 1.902 bytes nao ASCII (UTF-8)
$env:PGAPPNAME = $AppName                 # identifica a sessao em pg_stat_activity (P.11/Q.09)
$env:PGCONNECT_TIMEOUT = '10'
if ($SslRootCert -ne '') { $env:PGSSLMODE = 'verify-full'; $env:PGSSLROOTCERT = $SslRootCert } else { $env:PGSSLMODE = 'require' }

# 4. Confirmacao e senha
Write-Host "Ensaio LIVE P3-B S1 | autorizacao: $AuthorizationId | arquivo: $DryRunFile | sha: $sha | host: $PgHost"
$confirm = Read-Host 'Digite EXECUTAR ENSAIO S1 para continuar (qualquer outra coisa cancela)'
if ($confirm -cne 'EXECUTAR ENSAIO S1') { Stop-Run 92 'cancelado pelo operador antes de conectar' }
$sec = Read-Host 'Senha do banco (nao e exibida)' -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)

# 5. Execucao unica
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout = Join-Path $OutDir "dryrun_${stamp}_stdout.txt"
$stderr = Join-Path $OutDir "dryrun_${stamp}_stderr.txt"
$t0 = Get-Date
try {
  $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  $argv = @('-X', '-v', 'ON_ERROR_STOP=1', '-v', 'ON_ERROR_ROLLBACK=off', '-v', 'VERBOSITY=verbose', '-f', $DryRunFile)
  $p = Start-Process -FilePath 'psql' -ArgumentList $argv -NoNewWindow -Wait -PassThru `
         -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $code = $p.ExitCode
} finally {
  Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
$elapsed = [int]((Get-Date) - $t0).TotalMilliseconds

# 6. CLASSIFICACAO (nenhum caminho repete a execucao)
$errText = Get-Content -LiteralPath $stderr -Raw -Encoding UTF8
$outText = Get-Content -LiteralPath $stdout -Raw -Encoding UTF8
if ($null -eq $errText) { $errText = '' }
if ($null -eq $outText) { $outText = '' }
$errors = [regex]::Matches($errText, '(?m)(ERROR|FATAL):\s+([0-9A-Z]{5}):\s+(.*)$')
$verdict = 'STOP'
$reason = ''
if ($code -eq 0) { $reason = 'psql terminou sem erro: o ensaio nao levantou a sentinela (resultado sem excecao final)' }
elseif ($code -eq 1) { $reason = 'erro fatal do proprio psql (arquivo, memoria)' }
elseif ($code -eq 2) { $reason = 'conexao falhou ou caiu (inclui transaction/idle timeout do servidor)' }
elseif ($code -ne 3) { $reason = "codigo de saida inesperado: $code" }
elseif ($errors.Count -ne 1) { $reason = "esperado exatamente 1 erro; encontrados $($errors.Count)" }
elseif ($errors[0].Groups[1].Value -ne 'ERROR' -or $errors[0].Groups[2].Value -ne 'P0001') { $reason = "SQLSTATE inesperado: $($errors[0].Groups[1].Value) $($errors[0].Groups[2].Value) $($errors[0].Groups[3].Value)" }
elseif (-not ([regex]::Match($errors[0].Groups[3].Value, '^MSDRYRUN (\{.*\})\s*$')).Success) { $reason = "P0001 que nao e a sentinela: $($errors[0].Groups[3].Value)" }
elseif ($outText -match '(?m)^COMMIT\s*$') { $reason = 'COMMIT apareceu na saida' }
else {
  $json = ([regex]::Match($errors[0].Groups[3].Value, '^MSDRYRUN (\{.*\})\s*$')).Groups[1].Value
  try { $ev = $json | ConvertFrom-Json } catch { $ev = $null }
  if ($null -eq $ev) { $reason = 'JSON da sentinela ilegivel' }
  else {
    $props = $ev.PSObject.Properties
    $falses = @($props | Where-Object { $_.Value -is [bool] -and -not $_.Value } | ForEach-Object { $_.Name })
    $required = @('ok','precheck','txid','90.2','90.3','90.4','90.5','90.6','90.7','90.8','90.9','90.10','90.11','90.12',
                  'probe_anon_42501','probe_no_session_zero_rows','probe_update_immutable','probe_delete_immutable',
                  'probe_truncate_immutable','legacy_events','legacy_items','role_restored','duration_ms')
    $missing = @($required | Where-Object { -not ($props.Name -contains $_) })
    if ($missing.Count -gt 0) { $reason = "chaves ausentes: $($missing -join ', ')" }
    elseif ($falses.Count -gt 0) { $reason = "verificacoes false: $($falses -join ', ')" }
    elseif ([int]$ev.legacy_events -ne 1 -or [int]$ev.legacy_items -ne 1) { $reason = 'contagem do legado diferente de 1/1' }
    elseif ([double]$ev.duration_ms -gt 5000) { $reason = "duration_ms acima de 5000: $($ev.duration_ms)" }
    else { $verdict = 'SENTINELA_VALIDA'; $reason = 'MSDRYRUN valido. NAO e PASS: executar G-POST e LIVE_00 agora.' }
  }
}
$summary = Join-Path $OutDir "dryrun_${stamp}_summary.txt"
@(
  "authorization=$AuthorizationId", "file_sha256=$sha", "psql=$($ver.Trim())", "host=$PgHost", "user=$PgUser",
  "sslmode=$($env:PGSSLMODE)", "exit_code=$code", "client_elapsed_ms=$elapsed", "verdict=$verdict", "reason=$reason",
  "stdout=$stdout", "stderr=$stderr"
) | Set-Content -LiteralPath $summary -Encoding UTF8
Write-Host "RESULTADO: $verdict - $reason"
Write-Host "Resumo: $summary"
if ($verdict -eq 'SENTINELA_VALIDA') { exit 0 } else { exit 10 }
