<#
.SYNOPSIS
Updates a list of Git repositories. Then builds, tags, and pushes a Docker image from each repository.
.DESCRIPTION
This script reads the ".\images.txt" file to determine which repositories to update and build. The format of the file is one image per line, with each line containing 1) the directory/name of the image, 2) the address of the Git repository of the image, and optionally 3) the Docker registry to use. The information must be tab delimited (not space). Example:
my-program	https://github.com/my-git-account/my-program.git	my-registry/

Each repository is cloned or pulled, and must contain the subdirectory "compose-build" with a docker-compose.yml file to build the image. The built image is tagged with the Git tag of the HEAD commit (if present) combined with the current date. The image is also tagged "latest".

Optionally, a single image from ".\images.txt" can be built instead of all images by supplying the -Image parameter.
#>


param (
    # Build a specific image, if provided. Otherwise, build all images in ".\images.txt".
    [Parameter(Mandatory=$false, Position=0)]
    [string]
    $Image,
    # Whether to not use --no-cache when building.
    [switch]
    $UseCache
)

Set-StrictMode -Version 3.0

$InformationPreference = "Continue"
$logFileName = "$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss").log"

function Write-InformationWithLog {
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [object]
        $Object
    )
    
    $Object | Tee-Object -FilePath $script:logFileName -Append | Write-Information
}

function Write-WarningWithLog {
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [object]
        $Object
    )
    
    $Object | Tee-Object -FilePath $script:logFileName -Append | Write-Warning
}

function Write-ErrorWithLog {
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [object]
        $Object
    )
    
    $Object | Tee-Object -FilePath $script:logFileName -Append | Write-Error
}

if (!(Test-Path .\images.txt -PathType Leaf)) {
    Write-ErrorWithLog "The file "".\images.txt"" does not exist. View the script help for usage instructions."
    exit 1
}

docker info *> $null
if (!$?) {
    Write-ErrorWithLog "Docker is not running. Start Docker and run this script again."
    exit 1
}

<#
.SYNOPSIS
Uses Git to clone or pull a specified repository.
.OUTPUTS
bool. $true if the repository was cloned/pulled. $false if it failed.
#>
function Update-Repository {
    param (
        # The directory of the repository.
        [Parameter(Mandatory=$true, Position=0)]
        [string]
        $Directory,
        # The remote address of the Git repository.
        [Parameter(Mandatory=$true, Position=1)]
        [string]
        $Repository
    )

    if (Test-Path $Directory) { # Pull
        git -C $Directory pull *> $null
        if ($?) {
            Write-InformationWithLog "Pull:  Success"
            return $true
        }
        else {
            Write-ErrorWithLog "Pull:  Fail"
            return $false
        }
    }
    else { # Clone
        git clone $Repository $Directory *> $null
        if ($?) {
            Write-InformationWithLog "Clone: Success"
            return $true
        }
        else {
            Write-ErrorWithLog "Clone: Fail"
            return $false
        }
    }
}

<#
.SYNOPSIS
Builds, tags, and pushes a Docker image via Docker Compose in the current directory.
.OUTPUTS
bool. $true if build and push succeeded. $false if either failed.
#>
function Build-Image {
    param (
        # Whether to not use --no-cache when building.
        [Parameter(Mandatory=$true, Position=1)]
        [bool]
        $UseCache,
        # The Docker registry to use.
        [Parameter(Mandatory=$false, Position=2)]
        [string]
        $Registry = "",
        # The tag to use for image.
        [Parameter(Mandatory=$false, Position=3)]
        [string]
        $BuildTag
    )

    $success = $false
       
    $Env:DOCKER_REGISTRY = $Registry

    if ($PSBoundParameters.ContainsKey("BuildTag")) {
        $Env:DOCKER_TAG = $BuildTag
    }
    else {
        $Env:DOCKER_TAG = $null
    }

    if ($UseCache) {
        docker compose build *> $null
    }
    else {
        docker compose build --no-cache *> $null
    }
    if ($?) {
        Write-InformationWithLog "Build: Success"
        docker compose push *> $null
        if ($?) {
            Write-InformationWithLog "Push:  Success"
            $success = $true
        }
        else {
            Write-ErrorWithLog "Push:  Fail"
        }
    }
    else {
        Write-ErrorWithLog "Build: Fail"
    }

    return $success
}

<#
.SYNOPSIS
Updates a Git repository, then builds, tags, and pushes a Docker image.
.DESCRIPTION
`Build-All` uses `Update-Repository`, then attempts to navigate to the "compose-build" subdirectory within the repository. It then uses `Build-Image` and tags the image with the Git tag of the HEAD commit (if present) combined with the current date. The same image is then also tagged with "latest".
.OUTPUTS
bool. $true if all steps succeeded. $false if any failed.
#>
function Build-All {
    param (
        # Parts from images.txt file.
        [Parameter(Mandatory=$true, Position=0)]
        [string[]]
        $Parts,
        # Whether to use --no-cache when building.
        [Parameter(Mandatory=$true, Position=1)]
        [bool]
        $UseCache,
        # The date portion of the tag to use for image.
        [Parameter(Mandatory=$true, Position=2)]
        [string]
        $DateTag
    )

    $success = $false

    if (Update-Repository $Parts[0] $Parts[1]) {
        if (Test-Path "$($Parts[0])\compose-build") {
            Set-Location "$($Parts[0])\compose-build"

            $buildTag = $DateTag
            $gitTag = git tag --points-at HEAD
            if ($gitTag.Length -gt 0) {
                if ($gitTag.StartsWith("v")) {
                    $gitTag = $gitTag.Substring(1)
                }
                $buildTag = "$gitTag.$buildTag"
            }

            Write-InformationWithLog "-$buildTag"
            if (Build-Image -UseCache $UseCache -Registry $Parts[2] -BuildTag $buildTag) {
                Write-InformationWithLog "-latest"
                if (Build-Image -UseCache $true -Registry $Parts[2]) {
                    $success = $true
                }
            }

            Set-Location ..\..
        }
        else {
            Write-ErrorWithLog "The ""compose-build"" subdirectory does not exist."
        }
    }

    return $success
}

$dateTag = Get-Date -Format "yyyyMMdd"
$lineNumber = 0

if ($PSBoundParameters.ContainsKey("Image")) { # Build a single image.
    foreach($line in Get-Content -Path .\images.txt) {
        $lineNumber++
        $parts = $line.Split("`t")
        if ($parts.Length -lt 2) {
            Write-WarningWithLog "Line $lineNumber of images.txt is missing information. Skipping."
            continue
        }

        if ($parts[0] -eq $Image) {
            if (Build-All -Parts $parts -UseCache $UseCache -DateTag $dateTag) {
                exit 0
            }
            else {
                exit 1
            }
        }
    }

    Write-ErrorWithLog "Specified image ""$Image"" was not found in the images.txt file."
    exit 1
}
else { # Build all images.
    $exitCode = 0

    foreach($line in Get-Content -Path .\images.txt) {
        $lineNumber++
        $parts = $line.Split("`t")
        if ($parts.Length -lt 2) {
            Write-WarningWithLog "Line $lineNumber of images.txt is missing information. Skipping."
            continue
        }

        $header = "-" * $parts[0].Length
        Write-InformationWithLog "`n$header`n$($parts[0])`n$header"

        if (!(Build-All -Parts $parts -UseCache $UseCache -DateTag $dateTag)) {
            $exitCode = 1
        }
    }

    exit $exitCode
}
