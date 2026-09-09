#Requires -Version 5.1
# UTF-8 BOM (ajoute a l'enregistrement) : Windows PowerShell 5.1 lit sinon
# le script en ANSI et casse les accents.
<#
.SYNOPSIS
    Verifie les prerequis Windows (Docker Desktop + WSL2) pour la
    formation Docker Cloudoor. Sans droits administrateur.

.DESCRIPTION
    A lancer UNE FOIS dans Windows PowerShell (pas dans WSL, pas dans
    Git Bash) avant la journee de formation. Les labs se tapent ensuite
    dans un terminal Ubuntu (WSL) ou Git Bash, jamais ici.

.NOTES
    Correctifs : docs/prerequis-installation.md
    (#windows #virtualisation #wsl #docker-desktop #integration-wsl #git-bash)
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

function Test-IsWindowsHost {
    if ($null -ne (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue)) {
        return [bool]$IsWindows
    }
    return ($env:OS -eq 'Windows_NT')
}

if (-not (Test-IsWindowsHost)) {
    Write-Host "Ce script s'execute sur Windows (PowerShell), pas dans WSL ni sur macOS/Linux."
    Write-Host 'Sur WSL / macOS / Linux : suivez docs/prerequis-installation.md (section de votre OS).'
    exit 1
}

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
}

$script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$script:DocRel = 'docs/prerequis-installation.md'
$script:DocAbs = Join-Path $script:RepoRoot $script:DocRel
if (Test-Path -LiteralPath $script:DocAbs) {
    $script:DocShown = $script:DocAbs
} else {
    $script:DocShown = $script:DocRel
}

$script:Checks = @()
$script:FailCount = 0

function Add-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Pass,
        [string]$Detail = '',
        [string]$Fix = '',
        [string]$Anchor = ''
    )
    $status = 'PASS'
    $doc = ''
    if (-not $Pass) {
        $status = 'FAIL'
        $script:FailCount++
        $doc = $script:DocShown
        if ($Anchor) {
            $doc = "$($script:DocRel)#$Anchor"
        }
    }
    $script:Checks += [pscustomobject]@{
        Name   = $Name
        Pass   = $Pass
        Status = $status
        Detail = $Detail
        Fix    = $Fix
        Doc    = $doc
    }
}

function Get-NativeOutput {
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [string[]]$Arguments = @()
    )
    $cmd = Get-Command $File -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return [pscustomobject]@{
            Found    = $false
            Ok       = $false
            ExitCode = 127
            Text     = ''
        }
    }
    $prev = $global:LASTEXITCODE
    try {
        $global:LASTEXITCODE = 0
        $text = & $cmd.Source @Arguments 2>&1 | Out-String
        $code = $global:LASTEXITCODE
        if ($null -eq $code) { $code = 0 }
        return [pscustomobject]@{
            Found    = $true
            Ok       = ($code -eq 0)
            ExitCode = $code
            Text     = $text.Trim()
        }
    } catch {
        return [pscustomobject]@{
            Found    = $false
            Ok       = $false
            ExitCode = 1
            Text     = $_.Exception.Message
        }
    } finally {
        if ($null -ne $prev) { $global:LASTEXITCODE = $prev }
    }
}

function Get-WslExe {
    $candidates = @(
        (Join-Path $env:SystemRoot 'System32\wsl.exe'),
        (Join-Path $env:SystemRoot 'Sysnative\wsl.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    $cmd = Get-Command 'wsl.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-WslOutput {
    param(
        [Parameter(Mandatory = $true)][string[]]$WslArgs
    )
    $wslExe = Get-WslExe
    if (-not $wslExe) {
        return [pscustomobject]@{
            Found    = $false
            Ok       = $false
            ExitCode = 127
            Text     = ''
        }
    }
    $prev = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        $global:LASTEXITCODE = 0
        $output = & $wslExe @WslArgs 2>&1 | ForEach-Object {
            ([string]$_) -replace "`0", ''
        }
        $code = $global:LASTEXITCODE
        if ($null -eq $code) { $code = 0 }
        $text = (($output | Out-String) -replace "`0", '').Trim()
        return [pscustomobject]@{
            Found    = $true
            Ok       = ($code -eq 0)
            ExitCode = $code
            Text     = $text
        }
    } catch {
        return [pscustomobject]@{
            Found    = $true
            Ok       = $false
            ExitCode = 1
            Text     = $_.Exception.Message
        }
    } finally {
        [Console]::OutputEncoding = $prev
    }
}

function Get-WindowsBuildInfo {
    try {
        $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $build = 0
        $ubr = 0
        try { $build = [int]$cv.CurrentBuildNumber } catch { $build = 0 }
        try {
            if ($null -ne $cv.UBR) { $ubr = [int]$cv.UBR }
        } catch { $ubr = 0 }
        $display = [string]$cv.DisplayVersion
        $product = [string]$cv.ProductName
        # Win10 22H2 = 19045 ; Win11 21H2 = 22000 (insuffisant) ;
        # Win11 22H2 = 22621.
        $ok = $false
        if ($build -ge 22621) {
            $ok = $true
        } elseif ($build -ge 19045 -and $build -lt 22000) {
            $ok = $true
        }
        $detail = "$product, $display, build $build.$ubr"
        return [pscustomobject]@{
            Ok     = $ok
            Build  = $build
            Detail = $detail
        }
    } catch {
        return [pscustomobject]@{
            Ok     = $false
            Build  = 0
            Detail = $_.Exception.Message
        }
    }
}

function Test-VirtualizationEnabled {
    $notes = New-Object System.Collections.Generic.List[string]

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($cs.HypervisorPresent) {
            return [pscustomobject]@{
                Ok     = $true
                Detail = 'HypervisorPresent=True (un hyperviseur tourne deja)'
            }
        }
        [void]$notes.Add('HypervisorPresent=False')
    } catch {
        [void]$notes.Add("CIM: $($_.Exception.Message)")
    }

    try {
        $ci = Get-ComputerInfo -Property @(
            'HyperVRequirementVirtualizationFirmwareEnabled',
            'HyperVisorPresent'
        ) -ErrorAction Stop
        if ($ci.HyperVisorPresent) {
            return [pscustomobject]@{
                Ok     = $true
                Detail = 'Get-ComputerInfo.HyperVisorPresent=True'
            }
        }
        $fw = $ci.HyperVRequirementVirtualizationFirmwareEnabled
        if ($fw -eq $true) {
            return [pscustomobject]@{
                Ok     = $true
                Detail = 'HyperVRequirementVirtualizationFirmwareEnabled=True'
            }
        }
        if ($fw -eq $false) {
            [void]$notes.Add('HyperVRequirementVirtualizationFirmwareEnabled=False')
        }
    } catch {
        [void]$notes.Add("Get-ComputerInfo: $($_.Exception.Message)")
    }

    try {
        $si = (& systeminfo.exe 2>$null | Out-String)
        if ($si -match 'A hypervisor has been detected') {
            return [pscustomobject]@{
                Ok     = $true
                Detail = 'systeminfo : hypervisor detected'
            }
        }
        if ($si -match 'Virtualization Enabled In Firmware:\s*Yes') {
            return [pscustomobject]@{
                Ok     = $true
                Detail = 'systeminfo : Virtualization Enabled In Firmware = Yes'
            }
        }
        if ($si -match 'Virtualisation activ[^\r\n]+:\s*Oui') {
            return [pscustomobject]@{
                Ok     = $true
                Detail = 'systeminfo : virtualisation firmware = Oui'
            }
        }
        if ($si -match 'Virtualization Enabled In Firmware:\s*No') {
            return [pscustomobject]@{
                Ok     = $false
                Detail = 'systeminfo : Virtualization Enabled In Firmware = No'
            }
        }
    } catch {
        [void]$notes.Add("systeminfo: $($_.Exception.Message)")
    }

    return [pscustomobject]@{
        Ok     = $false
        Detail = ($notes -join '; ')
    }
}

function Get-UbuntuDistro {
    param([string]$ListText)
    $found = New-Object System.Collections.Generic.List[object]
    foreach ($raw in ($ListText -split '\r?\n')) {
        $line = $raw.Trim()
        if (-not $line) { continue }
        if ($line -match '(?i)^NAME\s+STATE\s+VERSION') { continue }
        $isDefault = $false
        if ($line -match '^\*') {
            $isDefault = $true
            $line = $line -replace '^\*\s*', ''
        }
        if ($line -match '(?i)(?<name>Ubuntu(?:-\d+\.\d+)?)(?:\s+(?<state>\S+)\s+(?<ver>\d+))?') {
            $name = $Matches['name']
            $ver = $Matches['ver']
            if (-not $ver -and $line -match '\b([12])\s*$') {
                $ver = $Matches[1]
            }
            [void]$found.Add([pscustomobject]@{
                Name      = $name
                Version   = $ver
                IsDefault = $isDefault
            })
        }
    }
    if ($found.Count -eq 0) { return $null }
    foreach ($item in $found) {
        if ($item.IsDefault) { return $item }
    }
    return $found[0]
}

# --- Controles ---

$win = Get-WindowsBuildInfo
Add-Check -Name 'Windows 10 22H2 ou plus recent' -Pass $win.Ok -Detail $win.Detail `
    -Anchor 'windows' `
    -Fix ("Mettez a jour Windows vers 22H2 ou plus recent (Parametres > Windows Update). " +
          "Docker Desktop exige Windows 10 build 19045+ ou Windows 11 build 22621+. " +
          "Poste actuel : $($win.Detail).")

$virt = Test-VirtualizationEnabled
Add-Check -Name 'Virtualisation activee (firmware / hyperviseur)' -Pass $virt.Ok -Detail $virt.Detail `
    -Anchor 'virtualisation' `
    -Fix ("Activez VT-x (Intel) ou AMD-V / SVM (AMD) dans le BIOS/UEFI, puis redemarrez. " +
          "L'option s'appelle parfois Virtualization Technology, Intel VT, ou SVM Mode. " +
          "Sans cela WSL 2 et Docker Desktop ne demarrent pas.")

$wslExe = Get-WslExe
$wslStatus = $null
if ($wslExe) {
    $wslStatus = Get-WslOutput -WslArgs @('--status')
}
$wslInstalled = $false
if ($wslExe) {
    $st = ''
    if ($wslStatus) { $st = $wslStatus.Text }
    $broken = $st -match '(?i)(is not enabled|n.est pas activ|not installed|pas installe)'
    $wslInstalled = -not $broken
}
$wslDetail = 'wsl.exe introuvable'
if ($wslExe) { $wslDetail = "wsl.exe = $wslExe" }
Add-Check -Name 'WSL installe' -Pass $wslInstalled -Detail $wslDetail `
    -Anchor 'wsl' `
    -Fix ("Installez WSL 2 + Ubuntu (une fois, compte admin si Windows le demande) : " +
          "wsl --install -d Ubuntu   puis redemarrez. Alternative : Microsoft Store > Ubuntu.")

$defaultV2 = $false
$defaultDetail = 'WSL absent'
if ($wslStatus -and $wslStatus.Text) {
    $defaultDetail = ($wslStatus.Text -split '\r?\n' | Select-Object -First 6) -join ' | '
    if ($wslStatus.Text -match '(?i)Default Version\s*:\s*2\b') {
        $defaultV2 = $true
    } elseif ($wslStatus.Text -match '(?i)Version par d[eé]faut\s*:\s*2\b') {
        $defaultV2 = $true
    }
}
Add-Check -Name 'WSL version 2 par defaut' -Pass $defaultV2 -Detail $defaultDetail `
    -Anchor 'wsl' `
    -Fix 'Dans PowerShell :  wsl --set-default-version 2   (puis reouvrez le terminal Ubuntu).'

$wslList = $null
$ubuntu = $null
if ($wslExe) {
    $wslList = Get-WslOutput -WslArgs @('-l', '-v')
    if ($wslList.Text) {
        $ubuntu = Get-UbuntuDistro -ListText $wslList.Text
    }
}
$ubuntuOk = $false
$ubuntuDetail = 'Aucune distribution Ubuntu dans wsl -l -v'
if ($ubuntu) {
    $ubuntuDetail = "distro=$($ubuntu.Name) VERSION=$($ubuntu.Version)"
    if ($ubuntu.Version -eq '2') { $ubuntuOk = $true }
}
$ubuntuFix = 'Installez Ubuntu :  wsl --install -d Ubuntu   (Microsoft Store > Ubuntu aussi).'
if ($ubuntu -and $ubuntu.Version -ne '2') {
    $ubuntuFix = "Passez $($ubuntu.Name) en WSL 2 :  wsl --set-version $($ubuntu.Name) 2"
}
Add-Check -Name 'Distribution Ubuntu en WSL 2' -Pass $ubuntuOk -Detail $ubuntuDetail `
    -Anchor 'wsl' `
    -Fix $ubuntuFix

$dockerExePath = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
$dockerApp = Test-Path -LiteralPath $dockerExePath
$dockerVer = Get-NativeOutput -File 'docker' -Arguments @('--version')
$dockerOk = $dockerVer.Ok
$dockerDetail = $dockerVer.Text
if (-not $dockerVer.Found) {
    if ($dockerApp) {
        $dockerDetail = 'Docker Desktop est installe mais docker.exe n est pas dans le PATH (rouvrez le terminal).'
    } else {
        $dockerDetail = 'docker.exe introuvable'
    }
}
Add-Check -Name 'Docker Desktop installe (docker --version)' -Pass $dockerOk -Detail $dockerDetail `
    -Anchor 'docker-desktop' `
    -Fix ("Installez Docker Desktop for Windows avec le backend WSL 2 : " +
          "https://docs.docker.com/desktop/setup/install/windows-install/   " +
          "Cochez Use WSL 2 based engine. Fermez puis rouvrez le terminal apres l'install.")

$daemon = Get-NativeOutput -File 'docker' -Arguments @('info')
Add-Check -Name 'Daemon Docker joignable (docker info)' -Pass $daemon.Ok `
    -Detail $(if ($daemon.Ok) { 'docker info exit 0' } else { "exit $($daemon.ExitCode)" }) `
    -Anchor 'docker-desktop' `
    -Fix ("Lancez Docker Desktop et attendez que l'icone baleine soit stable (moteur demarre). " +
          "Settings > General > Use the WSL 2 based engine doit etre coche. " +
          "Si le moteur reste orange : redemarrez Docker Desktop, puis le PC.")

$compose = Get-NativeOutput -File 'docker' -Arguments @('compose', 'version')
$composeOk = $false
if ($compose.Ok -and $compose.Text -match 'v?2\.') { $composeOk = $true }
Add-Check -Name 'Docker Compose v2 (docker compose version)' -Pass $composeOk -Detail $compose.Text `
    -Anchor 'docker-desktop' `
    -Fix ("Mettez a jour Docker Desktop. Compose v2 est le plugin 'docker compose' " +
          "(espace, pas le binaire docker-compose v1).")

# Integration WSL : docker doit marcher *dans* Ubuntu (hint stagiaire).
$skipInteg = (-not $ubuntuOk) -or (-not $daemon.Ok)
if (-not $skipInteg) {
    $integ = Get-WslOutput -WslArgs @('-d', $ubuntu.Name, '--', 'docker', 'info')
    $integOk = $integ.Ok
    $integDetail = "wsl -d $($ubuntu.Name) -- docker info  (exit $($integ.ExitCode))"
    Add-Check -Name 'Integration WSL (docker dans Ubuntu)' -Pass $integOk -Detail $integDetail `
        -Anchor 'integration-wsl' `
        -Fix ("Docker Desktop > Settings > Resources > WSL Integration : activez $($ubuntu.Name), " +
              "Apply & Restart. Ensuite, dans le terminal Ubuntu : docker info. " +
              "Clonez le repo dans le home WSL (~/) pas sous /mnt/c.")
}

$gitBashCandidates = @(
    (Join-Path $env:ProgramFiles 'Git\bin\bash.exe')
)
if ($env:ProgramFiles -and ${env:ProgramFiles(x86)}) {
    $gitBashCandidates += (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe')
}
$gitCmd = Join-Path $env:ProgramFiles 'Git\cmd\git.exe'
$gitVer = Get-NativeOutput -File 'git' -Arguments @('--version')
$hasBash = $false
$gitBash = $null
foreach ($candidate in $gitBashCandidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) {
        $hasBash = $true
        $gitBash = $candidate
        break
    }
}
$hasGitWin = (Test-Path -LiteralPath $gitCmd) -or $hasBash -or ($gitVer.Text -match '\.windows\.')
$gitOk = $gitVer.Ok -and $hasGitWin
$gitDetail = $gitVer.Text
if ($hasBash) { $gitDetail = "$gitDetail ; Git Bash = $gitBash" }
if ($gitVer.Ok -and -not $hasGitWin) {
    $gitDetail = "$($gitVer.Text) (git est dans le PATH mais Git Bash est absent : installez Git for Windows)"
}
Add-Check -Name 'Git for Windows + Git Bash' -Pass $gitOk -Detail $gitDetail `
    -Anchor 'git-bash' `
    -Fix ("Installez Git for Windows : https://git-scm.com/download/win   " +
          "Gardez l'option Git Bash. Les commandes des labs se tapent dans Git Bash " +
          "ou, de preference, dans Ubuntu (WSL) — jamais dans PowerShell.")

# --- Affichage ---

Write-Host ''
Write-Host '================================================================'
Write-Host '  Formation Docker (Cloudoor) — prerequis Windows'
Write-Host '  Aucun droit administrateur n est requis pour ce script.'
Write-Host '================================================================'
Write-Host ''

foreach ($c in $script:Checks) {
    $color = 'Green'
    if (-not $c.Pass) { $color = 'Red' }
    Write-Host ("[{0}] {1}" -f $c.Status, $c.Name) -ForegroundColor $color
    if ($c.Detail) {
        Write-Host ("       Detail    : {0}" -f $c.Detail)
    }
    if (-not $c.Pass) {
        Write-Host ("       Correctif : {0}" -f $c.Fix)
        Write-Host ("       Doc       : {0}" -f $c.Doc)
    }
}

Write-Host ''
Write-Host '----------------------------------------------------------------'
if ($script:FailCount -gt 0) {
    Write-Host ("Resultat : {0} ECHEC(S). Corrigez-les avant la formation." -f $script:FailCount) -ForegroundColor Red
    Write-Host ("Guide     : {0}" -f $script:DocShown)
    Write-Host 'Ne lancez PAS les labs tant que la table n est pas 100 % PASS.'
    exit 1
}

Write-Host 'Resultat : tous les controles sont PASS.' -ForegroundColor Green
Write-Host ''
Write-Host 'Ensuite (important) :'
Write-Host '  1. Fermez PowerShell.'
Write-Host '  2. Ouvrez Ubuntu (WSL) — ou Git Bash si WSL est bloque.'
Write-Host '  3. Clonez dans le home Linux, PAS sous /mnt/c :'
Write-Host '       cd ~'
Write-Host '       git clone https://github.com/doorcloud/formation-docker-kubernetes.git'
Write-Host '  4. Tapez TOUTES les commandes des labs dans ce terminal, jamais dans PowerShell.'
Write-Host ''
exit 0
