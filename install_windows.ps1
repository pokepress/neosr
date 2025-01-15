Write-Host "--- starting neosr installation..."

# Function to check admin privileges
function Test-AdminPrivileges {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
}

# Function to prompt for package installation
function Prompt-Install {
    param(
        [string]$Package
    )
    Write-Host "--- the package '$Package' is required but not installed."
    $answer = Read-Host "--- would you like to install it? [y/N]"
    return $answer -match '^[Yy]'
}

# Function to elevate privileges if needed and restart script
function Start-AdminSession {
    if (-not (Test-AdminPrivileges)) {
        Write-Host "--- requesting administrator privileges for package installation..."
        Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -Command Set-Location '$PWD'; & '$PSCommandPath'"
        exit
    }
}

# Function to install scoop
function Install-Scoop {
    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
        return $true
    }
    catch {
        Write-Host "--- failed to install Scoop: $_"
        return $false
    }
}

# Check if git is installed
if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    if (Prompt-Install "Git") {
        $installed = $false
        
        # Try winget first
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "--- attempting to install git using winget..."
            try {
                Start-AdminSession
                winget install -e --id Git.Git
                $installed = $true
            }
            catch {
                Write-Host "--- failed to install git using winget."
            }
        }
        
        # If winget failed, try scoop
        if (-not $installed) {
            if (Get-Command scoop -ErrorAction SilentlyContinue) {
                Write-Host "--- attempting to install git using scoop..."
                try {
                    scoop install main/git
                    $installed = $true
                }
                catch {
                    Write-Host "--- failed to install git using scoop."
                }
            }
            # If scoop is not installed, offer to install it
            else {
                Write-Host "--- scoop is not installed."
                if (Prompt-Install "Scoop package manager") {
                    if (Install-Scoop) {
                        Write-Host "--- scoop installed successfully, installing Git..."
                        try {
                            scoop install main/git
                            $installed = $true
                        }
                        catch {
                            Write-Host "--- failed to install Git using scoop."
                        }
                    }
                }
            }
        }
        
        if ($installed) {
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        }
        else {
            Write-Error "--- failed to install git through any available method. Please install it manually from https://git-scm.com/"
            exit 1
        }
    }
    else {
        Write-Host "--- git is required for installation, exiting."
        exit 1
    }
}

# Create and move to installation directory
$INSTALL_DIR = "$env:USERPROFILE\Desktop\neosr"
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
Set-Location $env:USERPROFILE\Desktop

# Clone repository
git clone https://github.com/neosr-project/neosr
Set-Location neosr

# Install uv
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"

# Refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Update uv and sync dependencies
uv self update > $null 2>&1
Write-Host "--- syncing dependencies (this might take several minutes)..."
uv sync > $null 2>&1

# Create functions for commands
$PROFILE_CONTENT = @'
function neosr-train { 
    Set-Location "$env:USERPROFILE\Desktop\neosr"
    uv run --isolated train.py -opt $args 
}
function neosr-test { 
    Set-Location "$env:USERPROFILE\Desktop\neosr"
    uv run --isolated test.py -opt $args 
}
function neosr-convert { 
    Set-Location "$env:USERPROFILE\Desktop\neosr"
    uv run --isolated convert.py $args 
}
function neosr-update {
    Set-Location "$env:USERPROFILE\Desktop\neosr"
    git pull --autostash
    uv sync
    uv lock
}
'@

# Create or update PowerShell profile
if (!(Test-Path -Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}
Add-Content -Path $PROFILE -Value $PROFILE_CONTENT

Write-Host "--- neosr installation complete!"
