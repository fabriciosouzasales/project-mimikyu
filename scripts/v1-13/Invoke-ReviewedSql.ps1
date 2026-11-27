<#
.SYNOPSIS
  V1-13 — executor por arquivo (STD-005 §3), versão 1.4. Envia ao LIVE exatamente os arquivos revisados.

.DESCRIPTION
  1. Lê o manifesto (linhas "passo|caminho relativo ao repositório|sha256|modo").
     Modos: gate = leitura AVALIADA (PRE/POST: STOP se reprovar), no MESMO papel da escrita;
            read = leitura só registrada (--read-only, papel de leitura); write = escrita (migration).
     Todo arquivo gate/read precisa ser um único SELECT sem palavra de escrita fora de literais
     (conferido antes de qualquer conexão) — é isso, e não o --read-only, que garante que o gate
     não escreve; o --read-only da CLI troca o papel da sessão (supabase_read_only_user) e
     impediria o PRE de provar as capacidades do papel que aplicará a migration.
  2. Confere o SHA-256 do MANIFESTO contra -ShaManifestoEsperado (o valor auditado e citado na
     autorização) e o SHA-256 de cada arquivo contra o manifesto — ANTES de qualquer conexão.
  3. Confere o destino (supabase\.temp\linked-project.json = -Projeto) e a versão da CLI.
  4. Exige a confirmação digitada "EXECUTAR <projeto> <8 primeiros do sha256 do manifesto>".
  5. Executa cada passo com `supabase db query --file` (arquivo inteiro, sem transcrição);
     gate/write com --yes, só read com --read-only. Para no primeiro erro OU no primeiro gate reprovado; nunca
     repete (SUPABASE_API_MAX_RETRIES=0; sem laço de repetição).
     Inventário de escritores (chaves "escritores_*", exceto "*_md5"): obrigatório comparar com
     -Expectativas (JSON auditado, sha256 em -ShaExpectativas). Chave sem expectativa, valor ausente,
     vazio, nome a mais, a menos ou repetido (sobrecarga) → gate reprovado. No PRIMEIRO gate, toda
     chave esperada precisa aparecer.
     Gate reprovado = um booleano de primeiro nível falso; "barreira" <> CLOSED;
     "identidades_teste" <> 0; "executor" <> -Papel; ou chave "*_md5" diferente da do gate anterior.
  6. Grava o registro fora do repositório (-DirRegistro): hashes, UTC, código de saída,
     avaliação dos gates, stdout/stderr brutos (as consultas só devolvem contagens e nomes de papéis).
  Trava por manifesto: repetir o mesmo manifesto exige remover a trava à mão (= nova autorização).
  Não guarda credenciais (usa o login da própria CLI), não usa --debug, não abre a barreira,
  não ativa TEST, não escolhe nem executa rollback.

.PARAMETER Simular
  Confere manifesto, hashes, destino e versão da CLI (consulta só o registro npm); NÃO conecta ao
  banco e não executa SQL.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\v1-13\Invoke-ReviewedSql.ps1 `
    -Repo . -Manifesto database\proposals\<pacote>\<MANIFESTO>.txt -Projeto <ref> -Simular
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string]$Repo,
  [Parameter(Mandatory = $true)] [string]$Manifesto,
  [Parameter(Mandatory = $true)] [string]$Projeto,
  [string]$ShaManifestoEsperado = '',
  [string]$Expectativas = '',
  [string]$ShaExpectativas = '',
  [string]$Papel = 'postgres',
  [string]$DirRegistro = (Join-Path $env:USERPROFILE 'Downloads\mmkyu-runs'),
  [string]$CliPacote = 'supabase@3.2.0',
  [switch]$Simular
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Utc { (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
function Quote([string[]]$a) { ($a | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ' }

# Executa a CLI; devolve código de saída. Saída padrão e de erro vão para arquivos.
function Invoke-Cli([string[]]$cliArgs, [string]$out, [string]$err) {
  $proc = Start-Process -FilePath 'npx.cmd' -ArgumentList (Quote $cliArgs) -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $out -RedirectStandardError $err
  return $proc.ExitCode
}

# Arquivo gate/read: um único SELECT; nenhuma palavra de escrita fora de comentários e literais.
function Test-ReadOnlySql([string]$path) {
  $s = Get-Content -LiteralPath $path -Raw -Encoding UTF8
  $s = [regex]::Replace($s, '/\*[\s\S]*?\*/', ' ')
  $s = [regex]::Replace($s, '--[^\r\n]*', ' ')
  $s = [regex]::Replace($s, "'(?:[^']|'')*'", "''")
  $s = $s.Trim()
  if ($s -notmatch '^(?i)select\b') { return $false }
  # [regex]::Matches devolve sempre uma coleção: sob StrictMode, .Count de um único [char] lançaria exceção.
  if ([regex]::Matches($s, ';').Count -ne 1 -or -not $s.EndsWith(';')) { return $false }
  if ($s -match '\$') { return $false }
  return ($s -notmatch '(?i)\b(insert|update|delete|merge|drop|alter|create|grant|revoke|truncate|lock|comment|copy|call|do|execute|vacuum|analyze|refresh|reindex|cluster|set_config|nextval|setval|pg_terminate_backend|pg_cancel_backend|dblink)\b')
}

# Avalia um gate: devolve @{ ok; motivos; objeto }.
function Test-Gate([string]$stdoutPath, $anterior, $expect, [bool]$exigirInventario) {
  $motivos = @()
  $vistos = @()
  $raw = (Get-Content -LiteralPath $stdoutPath -Raw)
  if (-not $raw) { return @{ ok = $false; motivos = @('saída vazia'); objeto = $null } }
  try { $rows = @((ConvertFrom-Json -InputObject $raw.Trim()) | ForEach-Object { $_ }) }
  catch { return @{ ok = $false; motivos = @('resposta inválida (JSON)'); objeto = $null } }
  if ($rows.Count -ne 1) { return @{ ok = $false; motivos = @("esperada 1 linha, veio $($rows.Count)"); objeto = $null } }
  $props = @($rows[0].PSObject.Properties)
  if ($props.Count -ne 1) { return @{ ok = $false; motivos = @('esperada 1 coluna'); objeto = $null } }
  $obj = $props[0].Value
  if ($obj -is [string]) {
    try { $obj = ConvertFrom-Json -InputObject $obj }
    catch { return @{ ok = $false; motivos = @('resposta inválida (objeto JSON)'); objeto = $null } }
  }
  if ($obj -isnot [System.Management.Automation.PSCustomObject]) { return @{ ok = $false; motivos = @('objeto do gate ausente'); objeto = $null } }
  $criterios = 0
  foreach ($p in $obj.PSObject.Properties) {
    if ($p.Value -is [bool]) { $criterios++ }
    if ($p.Value -is [bool] -and -not $p.Value) { $motivos += "$($p.Name) = false" }
    if ($p.Name -eq 'barreira' -and $p.Value -ne 'CLOSED') { $motivos += "barreira = $($p.Value)" }
    if ($p.Name -eq 'identidades_teste' -and ([string]$p.Value) -ne '0') { $motivos += "identidades_teste = $($p.Value)" }
    if ($p.Name -eq 'executor' -and $p.Value -ne $Papel) { $motivos += "executor = $($p.Value) (esperado $Papel)" }
    if ($p.Name -match '^escritores_[a-z_]+$' -and $p.Name -notlike '*_md5') {
      # Inventário de escritores: gate obrigatório, comparado com as expectativas auditadas.
      $vistos += $p.Name
      $e = $null
      if ($null -ne $expect) { $e = $expect.PSObject.Properties[$p.Name] }
      if ($null -eq $e) { $motivos += "$($p.Name): inventário sem expectativa auditada" }
      elseif ($p.Value -isnot [string]) { $motivos += "$($p.Name): inventário ausente ou inválido" }
      else {
        $real = @()
        if ($p.Value -ne '') { $real = @($p.Value -split ', ') }
        $a = @($real | Sort-Object -CaseSensitive) -join '|'
        $b = @(@($e.Value) | Sort-Object -CaseSensitive) -join '|'
        if ($a -cne $b) { $motivos += "$($p.Name) diferente do esperado: [$($p.Value)]" }
      }
    }
    if ($p.Name -like '*_md5' -and $null -ne $anterior) {
      $a = $anterior.PSObject.Properties[$p.Name]
      if ($null -ne $a -and $a.Value -ne $p.Value) { $motivos += "$($p.Name) diferente do gate anterior" }
    }
  }
  if ($criterios -eq 0) { $motivos += 'gate sem critério booleano' }
  if ($exigirInventario -and $null -ne $expect) {
    foreach ($k in @($expect.PSObject.Properties)) { if ($vistos -notcontains $k.Name) { $motivos += "inventário ausente: $($k.Name)" } }
  }
  return @{ ok = ($motivos.Count -eq 0); motivos = $motivos; objeto = $obj }
}

if ($PSVersionTable.PSVersion.Major -lt 5) { throw 'requer Windows PowerShell 5.1 ou superior' }
$Repo = (Resolve-Path -LiteralPath $Repo).Path
$ArqManifesto = (Resolve-Path -LiteralPath (Join-Path $Repo $Manifesto)).Path
$ShaManifesto = Sha $ArqManifesto
if ($Projeto -notmatch '^[a-z0-9]{20}$') { throw 'ref de projeto inválida' }
if (-not $Simular) {
  if ($ShaManifestoEsperado -notmatch '^[0-9a-f]{64}$') { throw 'informe -ShaManifestoEsperado (sha256 auditado do manifesto)' }
  if ($ShaManifestoEsperado -ne $ShaManifesto) { throw "manifesto diferente do auditado (arquivo=$ShaManifesto)" }
}

# Expectativas do inventário de escritores (antes de qualquer conexão).
$Expect = $null
$ShaExpect = ''
if ($Expectativas) {
  $ArqExpect = (Resolve-Path -LiteralPath (Join-Path $Repo $Expectativas)).Path
  $ShaExpect = Sha $ArqExpect
  if (-not $Simular) {
    if ($ShaExpectativas -notmatch '^[0-9a-f]{64}$') { throw 'informe -ShaExpectativas (sha256 auditado das expectativas)' }
    if ($ShaExpectativas -ne $ShaExpect) { throw "expectativas diferentes das auditadas (arquivo=$ShaExpect)" }
  }
  try { $Expect = Get-Content -LiteralPath $ArqExpect -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { throw 'expectativas: JSON inválido' }
  $eprops = @($Expect.PSObject.Properties)
  if ($eprops.Count -eq 0) { throw 'expectativas vazias' }
  foreach ($ep in $eprops) {
    if ($ep.Name -notmatch '^escritores_[a-z_]+$' -or $ep.Name -like '*_md5') { throw "expectativas: chave inválida $($ep.Name)" }
    $ev = @($ep.Value)
    if ($ev.Count -eq 0 -or @($ev | Where-Object { $_ -isnot [string] -or -not $_ }).Count -gt 0) { throw "expectativas: lista inválida em $($ep.Name)" }
    if (@($ev | Sort-Object -CaseSensitive -Unique).Count -ne $ev.Count) { throw "expectativas: nome repetido em $($ep.Name)" }
  }
}

# 1–2. Manifesto e hashes (antes de qualquer conexão).
$passos = @()
$n = 0
foreach ($linha in (Get-Content -LiteralPath $ArqManifesto)) {
  if ($linha -match '^\s*(#|$)') { continue }
  $c = $linha.Split('|')
  if ($c.Count -ne 4) { throw "manifesto: linha inválida: $linha" }
  $n++
  if ([int]$c[0] -ne $n) { throw "manifesto: passo fora de ordem: $linha" }
  if ($c[3] -notin @('gate', 'read', 'write')) { throw "manifesto: modo inválido: $linha" }
  $abs = Join-Path $Repo $c[1]
  if (-not (Test-Path -LiteralPath $abs -PathType Leaf)) { throw "arquivo ausente: $($c[1])" }
  $h = Sha $abs
  if ($h -ne $c[2].ToLowerInvariant()) { throw "SHA-256 divergente: $($c[1]) (arquivo=$h, manifesto=$($c[2]))" }
  if ($c[3] -ne 'write' -and -not (Test-ReadOnlySql $abs)) { throw "arquivo $($c[3]) não é um SELECT único somente leitura: $($c[1])" }
  $passos += [pscustomobject]@{ passo = $n; arquivo = $c[1]; caminho = $abs; sha256 = $h; modo = $c[3] }
}
if ($passos.Count -eq 0) { throw 'manifesto vazio' }
$primeiraEscrita = @($passos | Where-Object { $_.modo -eq 'write' } | Select-Object -First 1)
if ($primeiraEscrita.Count -gt 0 -and -not @($passos | Where-Object { $_.modo -eq 'gate' -and $_.passo -lt $primeiraEscrita[0].passo }).Count) {
  throw 'manifesto: toda escrita precisa de um gate (PRE) antes'
}

# 3. Destino e CLI.
$lp = Join-Path $Repo 'supabase\.temp\linked-project.json'
if (-not (Test-Path -LiteralPath $lp -PathType Leaf)) { throw 'supabase\.temp\linked-project.json ausente' }
if (((Get-Content -LiteralPath $lp -Raw) | ConvertFrom-Json).ref -ne $Projeto) { throw 'linked-project.json aponta para outro projeto' }
foreach ($k in @('SUPABASE_DB_PASSWORD', 'PGPASSWORD', 'DATABASE_URL')) {
  if ([Environment]::GetEnvironmentVariable($k)) { throw "variável $k definida: remova-a antes (o canal é a CLI autenticada)" }
}
$env:SUPABASE_API_MAX_RETRIES = '0'
$tmpV = [IO.Path]::GetTempFileName(); $tmpE = [IO.Path]::GetTempFileName()
if ((Invoke-Cli @('--yes', $CliPacote, '--version') $tmpV $tmpE) -ne 0) { throw 'CLI indisponível' }
$verEsperada = $CliPacote.Split('@')[-1]
if ((Get-Content -LiteralPath $tmpV -Raw).Trim() -ne $verEsperada) { throw "versão da CLI inesperada (esperada $verEsperada)" }
Remove-Item -LiteralPath $tmpV, $tmpE -Force

Write-Host "Manifesto : $Manifesto  sha256=$ShaManifesto"
Write-Host "Projeto   : $Projeto   Papel esperado: $Papel   CLI: $CliPacote"
if ($Expect) { Write-Host "Expectativas: $Expectativas  sha256=$ShaExpect" } else { Write-Host 'Expectativas: nenhuma (gate com inventário de escritores reprovará)' }
$passos | ForEach-Object { Write-Host ("  {0}. [{1}] {2}  {3}" -f $_.passo, $_.modo, $_.arquivo, $_.sha256) }

if ($Simular) { Write-Host 'SIMULAÇÃO: manifesto, hashes, destino e CLI conferidos; nenhuma conexão ao banco, nada enviado.'; exit 0 }

# Trava por manifesto (nova tentativa = nova autorização).
New-Item -ItemType Directory -Force -Path $DirRegistro | Out-Null
$trava = Join-Path $DirRegistro ("lock-" + $ShaManifesto.Substring(0, 16))
if (Test-Path -LiteralPath $trava) { throw "trava existente ($trava): este manifesto já foi executado; nova tentativa exige nova autorização" }

# 4. Confirmação digitada.
$esperado = "EXECUTAR $Projeto $($ShaManifesto.Substring(0, 8))"
$resp = Read-Host "Digite exatamente: $esperado"
if ($resp -cne $esperado) { throw 'confirmação não confere; nada foi enviado' }

$dirRun = Join-Path $DirRegistro ("run-" + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))
New-Item -ItemType Directory -Force -Path $dirRun | Out-Null
Set-Content -LiteralPath $trava -Value "$(Utc) $ShaManifesto" -Encoding ASCII
$registro = [ordered]@{ manifesto = $Manifesto; manifesto_sha256 = $ShaManifesto; projeto = $Projeto; papel = $Papel;
                        cli = $CliPacote; expectativas = $Expectativas; expectativas_sha256 = $ShaExpect;
                        inicio_utc = (Utc); passos = @() }
$gateAnterior = $null
$primeiroGate = $true

# 5. Execução, um passo por vez; para no primeiro erro ou gate reprovado.
try {
  foreach ($p in $passos) {
    if ((Sha $p.caminho) -ne $p.sha256) { $registro.resultado = "STOP: arquivo mudou antes do passo $($p.passo)"; break }
    $cliArgs = @('--yes', $CliPacote, 'db', 'query', '--file', $p.caminho, "--remote=$Projeto", '--agent=no', '-o', 'json')
    # gate e write: papel da escrita, com --yes (a CLI com -o json recusa sem confirmação);
    # só read usa --read-only (papel de leitura).
    if ($p.modo -eq 'read') { $cliArgs += '--read-only' } else { $cliArgs += '--yes' }
    $out = Join-Path $dirRun ("passo{0:D2}.stdout.json" -f $p.passo)
    $err = Join-Path $dirRun ("passo{0:D2}.stderr.txt" -f $p.passo)
    $ini = Utc
    $exit = Invoke-Cli $cliArgs $out $err
    $reg = [ordered]@{ passo = $p.passo; arquivo = $p.arquivo; sha256 = $p.sha256; modo = $p.modo;
                       inicio_utc = $ini; fim_utc = (Utc); exit = $exit }
    if ($exit -ne 0) {
      $registro.passos += $reg
      $registro.resultado = "STOP: erro no passo $($p.passo) (exit $exit) — conferir se a transação foi desfeita; sem rollback redundante"
      break
    }
    if ($p.modo -eq 'gate') {
      $g = Test-Gate $out $gateAnterior $Expect $primeiroGate
      $primeiroGate = $false
      $reg.gate_ok = $g.ok
      $reg.gate_motivos = $g.motivos
      $registro.passos += $reg
      Write-Host ("  passo {0} [gate] {1}" -f $p.passo, $(if ($g.ok) { 'PASS' } else { 'STOP: ' + ($g.motivos -join '; ') }))
      if (-not $g.ok) { $registro.resultado = "STOP: gate do passo $($p.passo) reprovado"; break }
      $gateAnterior = $g.objeto
    } else {
      $registro.passos += $reg
      Write-Host ("  passo {0} [{1}] exit=0" -f $p.passo, $p.modo)
    }
  }
  if (-not $registro.Contains('resultado')) { $registro.resultado = 'PASS (todos os passos concluídos e gates aprovados)' }
  $registro.fim_utc = (Utc)
} catch {
  $registro.resultado = "STOP: exceção no executor: $($_.Exception.Message)"
  $registro.fim_utc = (Utc)
}

# 6. Registro (fora do repositório).
$registro | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dirRun 'run.json') -Encoding UTF8
Write-Host "Registro: $dirRun"
Write-Host "Resultado: $($registro.resultado)"
if ($registro.resultado -notlike 'PASS*') { exit 2 }
