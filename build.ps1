[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string[]] $Applications = @(),

    [ValidateSet('all', 'arm', 'host')]
    [string] $Target = 'all',

    [ValidateSet('native', 'x86', 'x64')]
    [string] $HostArch = 'native',

    [switch] $List,
    [switch] $Clean,
    [switch] $DryRun,
    [switch] $Sanitize
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RootPath = $PSScriptRoot
$script:ModulesPath = Join-Path $script:RootPath 'modules'
$script:BuildPath = Join-Path $script:RootPath 'build_arm'
$script:OutputPath = Join-Path $script:RootPath 'output'

function Split-LgmList {
    param([AllowEmptyString()][string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }
    return @($Value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Convert-LgmNumber {
    param([string] $Value)

    if ($Value.StartsWith('0x', [StringComparison]::OrdinalIgnoreCase)) {
        return [Convert]::ToInt32($Value.Substring(2), 16)
    }
    return [Convert]::ToInt32($Value, 10)
}

function Read-LgmManifest {
    param([IO.FileInfo] $Manifest)

    $lines = @(Get-Content -LiteralPath $Manifest.FullName -Encoding UTF8)
    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne 'LGM1') {
        throw "$($Manifest.FullName): expected LGM1 header"
    }

    $fields = @{}
    for ($index = 1; $index -lt $lines.Count; $index++) {
        $line = $lines[$index].Trim()
        if (-not $line -or $line.StartsWith('#')) {
            continue
        }
        if (-not $line.Contains(':')) {
            throw "$($Manifest.FullName):$($index + 1): expected 'Key: value'"
        }
        $separator = $line.IndexOf(':')
        $key = $line.Substring(0, $separator).Trim().ToLowerInvariant()
        $value = $line.Substring($separator + 1).Trim()
        $fields[$key] = $value
    }

    $name = [string]$fields['name']
    $sourceNames = @(Split-LgmList ([string]$fields['sources']))
    if (-not $name -or $sourceNames.Count -eq 0) {
        throw "$($Manifest.FullName): Name and Sources are required"
    }
    if ($name -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
        throw "$($Manifest.FullName): Name must be an ASCII identifier"
    }

    $moduleDirectory = [IO.Path]::GetFullPath($Manifest.DirectoryName)
    $directoryPrefix = $moduleDirectory.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $sources = foreach ($sourceName in $sourceNames) {
        $source = [IO.Path]::GetFullPath((Join-Path $moduleDirectory $sourceName))
        if (-not $source.StartsWith($directoryPrefix, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "$($Manifest.FullName): invalid source '$sourceName'"
        }
        Get-Item -LiteralPath $source
    }

    $profile = $null
    $profileText = [string]$fields['profile']
    if ($profileText) {
        $profile = Convert-LgmNumber $profileText
        if ($profile -lt 0 -or $profile -gt 255) {
            throw "$($Manifest.FullName): Profile must fit in one byte"
        }
    }

    $dependencies = @(Split-LgmList ([string]$fields['depends']))
    foreach ($dependency in $dependencies) {
        if ($dependency -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
            throw "$($Manifest.FullName): invalid dependency name '$dependency'"
        }
    }

    [PSCustomObject]@{
        Name        = $name
        Directory   = $moduleDirectory
        Manifest    = $Manifest.FullName
        Sources     = @($sources)
        Depends     = $dependencies
        Defines     = @(Split-LgmList ([string]$fields['defines']))
        Profile     = $profile
        Description = [string]$fields['description']
    }
}

function Find-LanguasModules {
    $modules = @{}
    foreach ($manifest in Get-ChildItem -LiteralPath $script:ModulesPath -Filter '*.lgm' -File -Recurse) {
        $module = Read-LgmManifest $manifest
        if ($modules.ContainsKey($module.Name)) {
            throw "duplicate module name: $($module.Name)"
        }
        $modules[$module.Name] = $module
    }

    foreach ($module in $modules.Values) {
        foreach ($dependency in $module.Depends) {
            if (-not $modules.ContainsKey($dependency)) {
                throw "$($module.Manifest): unknown dependency '$dependency'"
            }
        }
    }
    return $modules
}

function Resolve-LanguasModules {
    param($RootModule, [hashtable] $AllModules)

    $resolved = [Collections.Generic.List[object]]::new()
    $visiting = [Collections.Generic.List[string]]::new()
    $visited = @{}

    function Visit-LanguasModule {
        param($Module)

        if ($visiting.Contains($Module.Name)) {
            throw "module dependency cycle: $(($visiting + $Module.Name) -join ' -> ')"
        }
        if ($visited.ContainsKey($Module.Name)) {
            return
        }
        $visiting.Add($Module.Name)
        foreach ($dependency in $Module.Depends) {
            Visit-LanguasModule $AllModules[$dependency]
        }
        $visiting.RemoveAt($visiting.Count - 1)
        $visited[$Module.Name] = $true
        $resolved.Add($Module)
    }

    Visit-LanguasModule $RootModule
    return @($resolved)
}

function Get-BuildTool {
    param([string] $EnvironmentName, [string] $Default)

    $configured = [Environment]::GetEnvironmentVariable($EnvironmentName)
    if ($configured) { return $configured }
    return $Default
}

function Format-CommandArgument {
    param([string] $Value)

    if ($Value -match '[\s"]') {
        return '"' + $Value.Replace('"', '\"') + '"'
    }
    return $Value
}

function Invoke-BuildCommand {
    param([string[]] $Command)

    Write-Host ('+ ' + (($Command | ForEach-Object { Format-CommandArgument $_ }) -join ' '))
    if ($DryRun) { return }

    $executable = $Command[0]
    $arguments = @($Command | Select-Object -Skip 1)
    & $executable @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "command failed with exit code ${LASTEXITCODE}: $executable"
    }
}

function Get-ObjectPath {
    param([string] $BuildDirectory, [IO.FileInfo] $Source)

    $relative = $Source.FullName.Substring($script:RootPath.Length).TrimStart([char]'\', [char]'/')
    $objectRelative = [IO.Path]::ChangeExtension($relative, '.o')
    return Join-Path (Join-Path $BuildDirectory 'obj') $objectRelative
}

function Compile-Source {
    param([IO.FileInfo] $Source, [string] $Output, [string[]] $CommonFlags)

    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Output) | Out-Null
    }
    $compiler = Get-BuildTool 'CC' 'clang'
    Invoke-BuildCommand (@($compiler) + $CommonFlags + @('-c', $Source.FullName, '-o', $Output))
}

function Build-NativeTools {
    $toolsDirectory = Join-Path $script:BuildPath 'tools'
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path $toolsDirectory | Out-Null
    }
    $compiler = Get-BuildTool 'CC' 'clang'
    $packer = Join-Path $toolsDirectory 'rom_packer.exe'
    $inspector = Join-Path $toolsDirectory 'rom_inspect.exe'
        Invoke-BuildCommand @($compiler, '-Wall', '-Wextra', '-Wpedantic', '-Werror', '-Os',
        (Join-Path $script:RootPath 'tools\rom_packer.c'), '-o', $packer)
    Invoke-BuildCommand @($compiler, '-Wall', '-Wextra', '-Os',
        (Join-Path $script:RootPath 'tools\rom_inspect.c'), '-o', $inspector)
    return @($packer, $inspector)
}

function Get-ModuleFlags {
    param($Application, [object[]] $Selected)

    $includeDirectories = @((Join-Path $script:RootPath 'core')) +
        @($Selected | ForEach-Object { $_.Directory })
    $includeFlags = foreach ($directory in $includeDirectories | Select-Object -Unique) {
        '-I'
        $directory
    }
    $definitions = @('CONFIG_PROFILE=0x{0:X2}' -f $Application.Profile) +
        @($Selected | ForEach-Object { $_.Defines })
    $defineFlags = foreach ($definition in $definitions | Select-Object -Unique) {
        "-D$definition"
    }
    return @($includeFlags) + @($defineFlags)
}

function Build-ArmApplication {
    param($Application, [object[]] $Selected, [string] $Packer, [string] $Inspector)

    $name = $Application.Name.ToLowerInvariant()
    $buildDirectory = Join-Path $script:BuildPath $name
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path $buildDirectory, $script:OutputPath | Out-Null
    }

    $flags = @(
        '-target', 'arm-none-eabi', '-mcpu=cortex-m0', '-mthumb', '-ffreestanding',
        '-fno-builtin', '-fdata-sections', '-ffunction-sections', '-fno-unwind-tables',
        '-fno-asynchronous-unwind-tables', '-fno-exceptions', '-Os', '-Wall', '-Wextra',
        '-Wpedantic', '-Werror', '-DLG_TARGET_ARMV6M=1'
    ) + @(Get-ModuleFlags $Application $Selected)

    $bootSources = @(
        Get-Item (Join-Path $script:RootPath 'bootex\startup_bootex.c')
        Get-Item (Join-Path $script:RootPath 'bootex\bootex.c')
    )
    $appSources = @(
        Get-Item (Join-Path $script:RootPath 'core\languas_header.c')
        Get-Item (Join-Path $script:RootPath 'core\languas_core.c')
        Get-Item (Join-Path $script:RootPath 'targets\armv6m\platform_armv6m.c')
        $Selected | ForEach-Object { $_.Sources }
    )
    $bootObjects = @($bootSources | ForEach-Object { Get-ObjectPath $buildDirectory $_ })
    $appObjects = @($appSources | ForEach-Object { Get-ObjectPath $buildDirectory $_ })

    for ($index = 0; $index -lt $bootSources.Count; $index++) {
        Compile-Source $bootSources[$index] $bootObjects[$index] $flags
    }
    for ($index = 0; $index -lt $appSources.Count; $index++) {
        Compile-Source $appSources[$index] $appObjects[$index] $flags
    }

    $linker = Get-BuildTool 'LD' 'ld.lld'
    $objcopy = Get-BuildTool 'OBJCOPY' 'llvm-objcopy'
    $bootElf = Join-Path $buildDirectory 'bootex.elf'
    $appElf = Join-Path $buildDirectory 'languas.elf'
    $bootBin = Join-Path $buildDirectory 'bootex.bin'
    $appBin = Join-Path $buildDirectory 'languas.bin'
    $rom = Join-Path $script:OutputPath "languas_$name.rom"
    $temporaryRom = "$rom.tmp"

    Invoke-BuildCommand (@($linker, '-nostdlib', '--gc-sections', '-T',
        (Join-Path $script:RootPath 'bootex\bootex.ld')) + $bootObjects + @('-o', $bootElf))
    Invoke-BuildCommand (@($linker, '-nostdlib', '--gc-sections', '-T',
        (Join-Path $script:RootPath 'targets\armv6m\languas.ld')) + $appObjects + @('-o', $appElf))
    Invoke-BuildCommand @($objcopy, '-O', 'binary', $bootElf, $bootBin)
    Invoke-BuildCommand @($objcopy, '-O', 'binary', $appElf, $appBin)
    Invoke-BuildCommand @($Packer, $bootBin, $appBin, $temporaryRom)
    Invoke-BuildCommand @($Inspector, 'verify', $temporaryRom)
    Write-Host "+ publish $temporaryRom -> $rom"
    if (-not $DryRun) {
        Move-Item -LiteralPath $temporaryRom -Destination $rom -Force
    }
}

function Build-HostedApplication {
    param($Application, [object[]] $Selected)

    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path $script:OutputPath | Out-Null
    }
    $name = $Application.Name.ToLowerInvariant()
    $architectureSuffix = switch ($HostArch) {
        'x86' { '_x86' }
        'x64' { '_x64' }
        default { '' }
    }
    $architectureFlags = switch ($HostArch) {
        'x86' { @('-m32') }
        'x64' { @('-m64') }
        default { @() }
    }
    $output = Join-Path $script:OutputPath "languas_${name}${architectureSuffix}.exe"
    $sources = @(
        (Join-Path $script:RootPath 'core\languas_header.c')
        (Join-Path $script:RootPath 'core\languas_core.c')
        $Selected | ForEach-Object { $_.Sources.FullName }
        (Join-Path $script:RootPath 'targets\host\platform_host.c')
        (Join-Path $script:RootPath 'targets\host\main_host.c')
    )
    $compiler = Get-BuildTool 'CC' 'clang'
    $safetyFlags = @('-Wall', '-Wextra', '-Wpedantic', '-Werror')
    if ($Sanitize) {
        $safetyFlags += @('-g', '-fno-omit-frame-pointer', '-fsanitize=address,undefined')
    }
    Invoke-BuildCommand (@($compiler, '-Os') + $safetyFlags + $architectureFlags +
        @(Get-ModuleFlags $Application $Selected) + $sources + @('-o', $output))
}

try {
    $modules = Find-LanguasModules

    if ($List) {
        foreach ($module in $modules.Values | Sort-Object Name) {
            $kind = if ($null -ne $module.Profile) {
                'application/profile 0x{0:X2}' -f $module.Profile
            } else {
                'library'
            }
            $dependencies = if ($module.Depends.Count) { $module.Depends -join ', ' } else { 'none' }
            Write-Host ('{0,-12} {1,-26} depends: {2}' -f $module.Name, $kind, $dependencies)
            if ($module.Description) { Write-Host "             $($module.Description)" }
        }
        exit 0
    }

    if ($Clean) {
        foreach ($directory in @($script:BuildPath, $script:OutputPath)) {
            if (Test-Path -LiteralPath $directory) {
                Write-Host "remove $directory"
                Remove-Item -LiteralPath $directory -Recurse -Force
            }
        }
        exit 0
    }

    $selectedApplications = @()
    if ($Applications.Count) {
        foreach ($name in $Applications) {
            if (-not $modules.ContainsKey($name)) { throw "unknown module: $name" }
            $module = $modules[$name]
            if ($null -eq $module.Profile) {
                throw "$($module.Name) is a library module, not an application"
            }
            $selectedApplications += $module
        }
    } else {
        $selectedApplications = @($modules.Values | Where-Object { $null -ne $_.Profile } | Sort-Object Name)
    }
    if (-not $selectedApplications.Count) { throw 'no application modules found' }

    $armTools = $null
    if ($Target -in @('all', 'arm')) {
        $armTools = @(Build-NativeTools)
    }
    foreach ($application in $selectedApplications) {
        $selectedModules = @(Resolve-LanguasModules $application $modules)
        Write-Host "`n== $($application.Name): $(($selectedModules.Name) -join ', ') =="
        if ($Target -in @('all', 'arm')) {
            Build-ArmApplication $application $selectedModules $armTools[0] $armTools[1]
        }
        if ($Target -in @('all', 'host')) {
            Build-HostedApplication $application $selectedModules
        }
    }
} catch {
    Write-Error $_
    exit 1
}
