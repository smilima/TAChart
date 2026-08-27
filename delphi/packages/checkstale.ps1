<#
    Is what is installed actually built from the current source?

    Two ways it can be out of step, and the second is the nastier one:

      1. A source file is newer than the installed BPL.  The build did not run,
         or it failed and the failure scrolled past.

      2. The import library is newer than the BPL.  This is what happens when
         the packages are rebuilt while the IDE is open: the IDE loads
         TAChartRT<sfx>.bpl and locks it, so the BPL link fails with F2039,
         but the .lib in Dcp\ is not locked and is written anyway.  An
         application then links happily against the new API and fails at
         start-up with "The procedure entry point ... could not be located",
         naming a symbol that exists in the .lib and not in the .bpl.  The
         error surfaces long after the build that caused it and says nothing
         about packages.

    Prints one line per platform and exits 1 if anything is behind.

    Parameters are supplied by build.bat / install.bat, which already know
    them; nothing here hardcodes an installation path.
#>
param(
    [Parameter(Mandatory = $true)] [string] $CommonDir,   # $(BDSCOMMONDIR)
    [Parameter(Mandatory = $true)] [string] $Suffix,      # e.g. 370
    [Parameter(Mandatory = $true)] [string] $SourceRoot   # ...\delphi
)

$ErrorActionPreference = 'Stop'

# The newest thing the packages are built from.  design\ counts too: it is in
# the design-time package.
$sourceDirs = @('src', 'compat', 'design') |
    ForEach-Object { Join-Path $SourceRoot $_ } |
    Where-Object { Test-Path $_ }

$newest = Get-ChildItem -Path $sourceDirs -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in '.pas', '.inc', '.dfm', '.rc', '.res', '.dcr' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $newest) {
    Write-Output "   could not read any source files under $SourceRoot"
    exit 1
}

Write-Output ("   newest source : {0}  ({1:yyyy-MM-dd HH:mm:ss})" -f
    $newest.Name, $newest.LastWriteTime)

# Where each platform writes its BPL and its C++ import library.  Win32 has no
# subdirectory, which is the Delphi convention.
$platforms = @(
    @{ Name = 'Win32';  Bpl = 'Bpl';        Dcp = 'Dcp' }
    @{ Name = 'Win64';  Bpl = 'Bpl\Win64';  Dcp = 'Dcp\Win64' }
    @{ Name = 'Win64x'; Bpl = 'Bpl\Win64x'; Dcp = 'Dcp\Win64x' }
)

$stale = $false

foreach ($p in $platforms) {
    $bplDir = Join-Path $CommonDir $p.Bpl
    $dcpDir = Join-Path $CommonDir $p.Dcp
    $problems = @()

    foreach ($pkg in 'TAChartRT', 'TAChartDT') {
        $bpl = Join-Path $bplDir "$pkg$Suffix.bpl"
        if (-not (Test-Path $bpl)) {
            $problems += "$pkg not built"
            continue
        }
        $bplTime = (Get-Item $bpl).LastWriteTime

        if ($bplTime -lt $newest.LastWriteTime) {
            $problems += ("$pkg BEHIND SOURCE by {0:N0} min" -f
                ($newest.LastWriteTime - $bplTime).TotalMinutes)
        }

        # The .lib is only produced for C++ use; its absence is not a fault.
        $lib = Join-Path $dcpDir "$pkg.lib"
        if (Test-Path $lib) {
            $libTime = (Get-Item $lib).LastWriteTime
            # A minute of slack: the two are written moments apart by one build.
            if ($libTime -gt $bplTime.AddMinutes(1)) {
                $problems += ("$pkg LIB NEWER THAN BPL by {0:N0} min" -f
                    ($libTime - $bplTime).TotalMinutes)
            }
        }
    }

    if ($problems.Count -eq 0) {
        Write-Output ("   {0,-7} ok" -f $p.Name)
    }
    else {
        Write-Output ("   {0,-7} {1}" -f $p.Name, ($problems -join '; '))
        $stale = $true
    }
}

if ($stale) {
    Write-Output ''
    Write-Output '   Something installed is older than the source it is built from.'
    Write-Output '   Close the IDE - it locks TAChartRT<sfx>.bpl - and run build.bat'
    Write-Output '   again.  A "LIB NEWER THAN BPL" line means exactly that already'
    Write-Output '   happened: applications built now will link but fail to start.'
    exit 1
}

exit 0
