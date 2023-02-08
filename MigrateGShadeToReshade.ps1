Write-Host "GShade to Reshade migration script (v1)"
Write-Host "This script will convert your existing GShade installation into a ReShade installation and migrate your presets automatically."
Write-Host "Probably put some information on where to get help here lmao"
Write-Host "---"
$ErrorActionPreference = 'Continue'

try {
    # Locate the GShade and FFXIV installation via registry.
    # Computer\HKEY_LOCAL_MACHINE\SOFTWARE\GShade
    # instdir: C:\Program Files\GShade
    # lastexepath: C:\SquareEnix\FINAL FANTASY XIV - A Realm Reborn\game\ffxiv_dx11.exe
    Write-Host "Retrieving GShade registry keys."
    $PathGShadeInstall = Get-ItemPropertyValue -Path 'HKLM:\HKEY_LOCAL_MACHINE\SOFTWARE\GShade' -Name 'instdir'
    $PathFF14Exe = Get-ItemPropertyValue -Path 'HKLM:\HKEY_LOCAL_MACHINE\SOFTWARE\GShade' -Name 'lastexepath'

    # Verify our registry keys seem sane.
    if (-not(Test-Path -Path $PathFF14Exe)) {
        throw "Could not locate ffxiv_dx11.exe, expected it at: $PathFF14Exe"
    }
    $PathFF14Game = Split-Path -Path $PathFF14Exe
    $PathFF14GShadePresets = Join-Path -Path $PathFF14Game -ChildPath "gshade-presets"
    if (-not(Test-Path -Path $PathFF14GShadePresets)) {
        throw "Could not locate gshade-presets, expected it at: $PathFF14GShadePresets"
    }
    $PathFF14GShadeIni = Join-Path -Path $PathFF14Game -ChildPath "GShade.ini"
    if (-not(Test-Path -Path $PathFF14GShadeIni)) {
        throw "Could not locate GShade.ini, expected it at: $PathFF14GShadeIni"
    }

    if (-not(Test-Path -Path $PathGShadeInstall)) {
        throw "Could not locate GShade installation, expected it at: $PathGShadeInstall"
    }
    $PathFF14GShadeShaders = Join-Path -Path $PathGShadeInstall -ChildPath "gshade-shaders"
    if (-not(Test-Path -Path $PathFF14GShadeShaders)) {
        throw "Could not locate GShade shaders, expected it at: $PathFF14GShadeShaders"
    }

    # Print the FFXIV folder, the GShade presets folder, and the GShade installation folder, and wait for user confirm.
    Write-Host "---"
    Write-Host "FFXIV game folder: $PathFF14Game"
    Write-Host "GShade installation folder: $PathGShadeInstall"
    Write-Host "GShade presets folder: $PathFF14GShadePresets"
    Write-Host ""
    Write-Host -nonewline "Do these values look correct? Input 'Y' then hit ENTER to continue: "
    $response = Read-Host
    if ( $response -ne "Y" ) { exit }
    Write-Host "---"

    $PathReShadeShaders = Join-Path -Path $PathFF14Game -ChildPath "reshade-shaders"
    $PathReShadePresets = Join-Path -Path $PathFF14Game -ChildPath "reshade-presets"

    # Create a backup of the GShade installation and the GShade presets.
    Write-Host "Creating backup of GShade files."
    $PathBackup = "PowerShadeBackup" + "_"+ [int](Get-Date -UFormat %s -Millisecond 0)
    New-Item $PathBackup -ItemType Directory
    Copy-Item $PathFF14GShadePresets -Destination $PathBackup -Recurse -ErrorAction Stop
    Copy-Item $PathFF14GShadeShaders -Destination $PathBackup -Recurse -ErrorAction Stop
    Copy-Item $PathFF14GShadeIni -Destination $PathBackup -ErrorAction Stop
    Write-Host "Created backup of GShade files at: "(Resolve-Path $PathBackup)

    # We will back up any reshade files just in case they exist for some reason.
    if (Test-Path -Path $PathReShadeShaders) {
        Write-Host "Found reshade-shaders in FFXIV directory, moving to backup."
        Move-Item $PathReShadeShaders -Destination $PathBackup -ErrorAction Stop
    }
    if (Test-Path -Path $PathReShadePresets) {
        Write-Host "Found reshade-presets in FFXIV directory, moving to backup."
        Move-Item $PathReShadePresets -Destination $PathBackup -ErrorAction Stop
    }
    $PathReShadeIni = Join-Path -Path $PathFF14Game -ChildPath "ReShade.ini"
    if (Test-Path -Path $PathReShadeIni) {
        Write-Host "Found ReShade.ini in FFXIV directory, moving to backup."
        Move-Item $PathReShadeIni -Destination $PathBackup -ErrorAction Stop
    }


    # Download ReShade installer.
    Write-Host "Downloading ReShade installer."
    Invoke-WebRequest "http://static.reshade.me/downloads/ReShade_Setup_5.6.0_Addon.exe" -OutFile "ReShade_Setup.exe"


    # Download patched shaders. Ask Rika to add the default shaders here too.
    Write-Host "Downloading patched shaders."
    Invoke-WebRequest "https://kagamine.tech/shade/fixed_shaders.zip" -OutFile "fixed_shaders.zip"


    # Delete dxgi.dll in the FFXIV folder. Delete d3d11.dll if it exists too.
    Write-Host "Deleting old GShade binaries from FFXIV game folder."
    $PathFF14Dxgi = Join-Path -Path $PathFF14Game -ChildPath "dxgi.dll"
    $PathFF14D3d11 = Join-Path -Path $PathFF14Game -ChildPath "d3d11.dll"
    if (Test-Path -Path $PathFF14Dxgi) { Remove-Item -Path $PathFF14Dxgi -ErrorAction Stop }
    if (Test-Path -Path $PathFF14D3d11) { Remove-Item -Path $PathFF14D3d11 -ErrorAction Stop }


    # Run ReShade Installer - use headless mode. This does not install default shaders.
    Write-Host "Installing ReShade."
    Start-Process ReShade_Setup.exe -ArgumentList "`"$PathFF14Exe`" --api dxgi --headless" -NoNewWindow -Wait -ErrorAction Stop
    if (-not(Test-Path -Path $PathFF14Dxgi)) {
        throw "dxgi.dll did not install correctly, expected it at: $PathFF14Dxgi"
    }


    # Copy gshade-shaders to reshade-shaders.
    Write-Host "Migrating GShade shaders."
    Copy-Item -Path "$PathFF14GShadeShaders" -Destination $PathReShadeShaders -Recurse -Container: $true -ErrorAction Stop

    Write-Host "Installing patched shaders."
    Expand-Archive -Path "fixed_shaders.zip" -DestinationPath $PathReShadeShaders -Force -ErrorAction Stop


    # Modify ReShade.ini to point to the new effect paths.
    # We actually just copy GShade.ini to ReShade.ini and then use regex to fix the config.
    # That's basically two conspiracies to commit a crime right there.
    Write-Host "Migrating GShade.ini to ReShade.ini to use new shader folders."
    Write-Host "WARNING: This is experimental and may not work correctly! If you have problems, try deleting ReShade.ini to restore to default ReShade settings."
    $ReShadeIniContent = Get-Content -Path $PathFF14GShadeIni
    $ReShadeIniContent = $ReShadeIniContent -Replace 'EffectSearchPaths\=(.*)', 'EffectSearchPaths=.\reshade-shaders\Shaders,.\reshade-shaders\ComputeShaders'
    $ReShadeIniContent = $ReShadeIniContent -Replace 'IntermediateCachePath\=(.*)', 'IntermediateCachePath=.\reshade-shaders\Intermediate'
    $ReShadeIniContent = $ReShadeIniContent -Replace 'TextureSearchPaths\=(.*)', 'TextureSearchPaths=.\reshade-shaders\Textures'
    $ReShadeIniContent = $ReShadeIniContent -Replace 'gshade', 'reshade'
    $ReShadeIniContent | Set-Content -Path $PathReShadeIni


    # Rename gshade-presets to reshade-presets.
    Write-Host "Renaming gshade-presets to reshade-presets."
    Rename-Item -Path $PathFF14GShadePresets -NewName $PathReShadePresets

    $PathFF14GShadeAddons = Join-Path -Path $PathFF14Game -ChildPath "gshade-addons"
    if (Test-Path -Path $PathFF14GShadeAddons) {
        Write-Host "Renaming gshade-addons to reshade-addons."
        Rename-Item -Path $PathFF14GShadeAddons -NewName "reshade-addons"
    }

    Write-Host "Removing GShade.ini configuration file."
    Remove-Item -Path $PathFF14GShadeIni

    # Done!
    Write-Host "Cleaning up temporary files."
    Remove-Item "fixed_shaders.zip"
    Remove-Item "ReShade_Setup.exe"
} catch {
    Write-Error "$($_.Exception.Message)"
}
Write-Host "Finished - press any key to exit."
[void][System.Console]::ReadKey($true)