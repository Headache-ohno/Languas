[CmdletBinding()]
param(
    [string] $ToolDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ToolDirectory)) {
    $ToolDirectory = Join-Path $PSScriptRoot '..\build_arm\tools'
}

$packer = Join-Path $ToolDirectory 'rom_packer.exe'
$inspector = Join-Path $ToolDirectory 'rom_inspect.exe'
if (-not (Test-Path -LiteralPath $packer -PathType Leaf) -or
    -not (Test-Path -LiteralPath $inspector -PathType Leaf)) {
    throw 'Build the ARM target before running the ROM tool tests.'
}

function Invoke-Tool {
    param([string] $Executable, [string[]] $Arguments, [int] $ExpectedExit)

    & $Executable @Arguments
    if ($LASTEXITCODE -ne $ExpectedExit) {
        throw "$Executable returned $LASTEXITCODE; expected $ExpectedExit"
    }
}

$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ("languas-rom-test-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $testDirectory | Out-Null

try {
    $bootex = Join-Path $testDirectory 'bootex.bin'
    $languas = Join-Path $testDirectory 'languas.bin'
    $rom = Join-Path $testDirectory 'valid.rom'

    [IO.File]::WriteAllBytes($bootex, [byte[]]@(
        0x00, 0x10, 0x00, 0x20,
        0x09, 0x00, 0x00, 0x00,
        0x00, 0xBF
    ))
    [IO.File]::WriteAllBytes($languas, [byte[]]@(
        0x4C, 0x47, 0x55, 0x53,
        0x00, 0x01, 0x02, 0x00,
        0x0C, 0x00, 0x00, 0x00,
        0x00, 0xBF
    ))

    Invoke-Tool $packer @($bootex, $languas, $rom) 0
    Invoke-Tool $inspector @('verify', $rom) 0
    if ((Get-Item -LiteralPath $rom).Length -ne 4110) {
        throw 'Minimal valid ROM does not have the proven 4110-byte size.'
    }

    $oversizedBootex = Join-Path $testDirectory 'bootex-too-large.bin'
    [IO.File]::WriteAllBytes($oversizedBootex, [byte[]]::new(4097))
    Invoke-Tool $packer @($oversizedBootex, $languas,
        (Join-Path $testDirectory 'bad-bootex.rom')) 1

    $truncatedBootex = Join-Path $testDirectory 'bootex-truncated-handler.bin'
    [IO.File]::WriteAllBytes($truncatedBootex, [byte[]]@(
        0x00, 0x10, 0x00, 0x20,
        0x09, 0x00, 0x00, 0x00
    ))
    Invoke-Tool $packer @($truncatedBootex, $languas,
        (Join-Path $testDirectory 'bad-handler.rom')) 1

    $oversizedLanguas = Join-Path $testDirectory 'languas-too-large.bin'
    [IO.File]::WriteAllBytes($oversizedLanguas, [byte[]]::new(28673))
    Invoke-Tool $packer @($bootex, $oversizedLanguas,
        (Join-Path $testDirectory 'bad-languas.rom')) 1

    $badProfile = Join-Path $testDirectory 'bad-profile.rom'
    $badProfileBytes = [IO.File]::ReadAllBytes($rom)
    $badProfileBytes[0x1006] = 0x04
    [IO.File]::WriteAllBytes($badProfile, $badProfileBytes)
    Invoke-Tool $inspector @('verify', $badProfile) 1

    $badStack = Join-Path $testDirectory 'bad-stack.rom'
    $badStackBytes = [IO.File]::ReadAllBytes($rom)
    $badStackBytes[1] = 0x20
    [IO.File]::WriteAllBytes($badStack, $badStackBytes)
    Invoke-Tool $inspector @('verify', $badStack) 1

    Write-Host 'ROM tool boundary tests passed.'
} finally {
    if (Test-Path -LiteralPath $testDirectory) {
        Remove-Item -LiteralPath $testDirectory -Recurse -Force
    }
}
