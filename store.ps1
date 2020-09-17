$NUGET_BASE_PATH="~/.nuget"

Function Convert-HexToByteArray {

    [cmdletbinding()]

    param(
        [parameter(Mandatory=$true)]
        [String]
        $HexString
    )

    $Bytes = [byte[]]::new($HexString.Length / 2)

    For($i=0; $i -lt $HexString.Length; $i+=2){
        $Bytes[$i/2] = [convert]::ToByte($HexString.Substring($i, 2), 16)
    }

    $Bytes
}

for ($i=1; $i -lt $args.Length; $i++)
{
	$key=$args[$i]
    if ($key -eq "-h" -Or $key -eq "--help")
    {
        echo "Usage: LocalNugetStore"
        echo ""
        echo "Options:"
        echo "`t-h, --help Print this help"
        exit 0
    }
	else
	{

	}
}

$cmd = $args[0]
# Read nuget config
[xml]$nugetConfig = Get-Content -Path $NUGET_BASE_PATH/NuGet/NuGet.Config
$localStores=@{}
foreach($source in $nugetConfig.configuration.packageSources.add){
    $sourceUri = New-Object -TypeName System.Uri -ArgumentList $source.GetAttribute("value")
    if ($sourceUri.IsFile) {
        $localStores[$source.GetAttribute("key")] = $source.GetAttribute("value")
    }
}

function chooseLocalStore($localStores)
{
    [int32]$i = 0
    $array=@{}
    foreach($store in $localStores.keys) {
        Write-Host "[$($i)] - $($store)"
        $array[$i] = $store
        $i++
    }
    do {
        try{
            [int32]$number = Read-Host -Prompt "Enter a Number"
        }catch{}
    } while(($number -lt 0) -Or ($number -ge $i))

    return $array[$number]
}


if ($cmd -eq "list")
{
    echo $localStores
}
elseif ($cmd -eq "list-packages")
{
    if (($args.Length -lt 2) -Or (!$localStores.ContainsKey($args[1])))
    {
        if ($localStores.keys.Count -eq 0) {
            Write-Host "No local store available"
            exit 0
        }
        if ($localStores.keys.Count -eq 1) {
            $packageSource = $localStores.keys[0]
        }
        else {
            echo "Select a store to list packages"
            $packageSource = chooseLocalStore($localStores)
        }
    }
    else
    {
        $packageSource = $args[1]
    }
    $localStore = $localStores[$packageSource]
    if (Test-Path -Path $localStore ) {
        foreach($pDir in Get-ChildItem -Path $localStore -Directory) {
            echo $pDir.Name
            $len = $pDir.Name.Length
            $pDir = $pDir.FullName
            $pName = [System.IO.Path]::GetDirectoryName($pDir)
            foreach($p in Get-ChildItem -Path $pDir/*/*.nupkg){
                Write-Host "  $(($p.BaseName).Substring($len + 1))"
            }
        }
    }
}
elseif($cmd -eq "add")
{
    echo "Not Implemented"
}
elseif($cmd -eq "add-packages")
{
    if ($args.Length -lt 2)
    {
        Write-Host "Not enough parameters"
        exit 1
    }
    $startIndex = 1
    if ((!$localStores.ContainsKey($args[1])))
    {
        if ($localStores.keys.Count -eq 0) {
            Write-Host "No local store available"
            exit 0
        }
        if ($localStores.keys.Count -eq 1) {
            $packageSource = $localStores.keys[0]
        }
        else {
            echo "Select a store to add the package to:"
            $packageSource = chooseLocalStore($localStores)
        }
    }
    else
    {
        $packageSource = $args[1]
        $startIndex = 2
    }
    
    $localStore = $localStores[$packageSource]
    if (-Not $(Test-Path -Path $localStore)) {
        New-Item -ItemType directory -Path $localStore >$null 2>&1
    }
    
    $overrideAllPackages = $false
    $uninstallAllPackages = $false
    for ($i=$startIndex; $i -lt $args.Length; $i++) {
        
        $packageSearchString = $args[$i]
        
        foreach($packageToAdd in Get-ChildItem -Path $packageSearchString -File) {
            Write-host "Add $($packageToAdd) to $($packageSource)"

            $packageName = $packageToAdd.Name
            if (-Not $($packageName -match "^(.*?)\.((?:\.?[0-9]+){3,}(?:[\.-a-z]+)?)\.nupkg$")) {
                Write-Host "Cannot parse package name"
                continue
            }
            $packageBaseName = $Matches[1].ToLower()
            $packageVersion = $Matches[2].ToLower()
            
            if (-Not $(Test-Path -Path $localStore/$packageBaseName)) {
                New-Item -ItemType directory -Path $localStore/$packageBaseName >$null 2>&1
            }
            if (-Not $(Test-Path -Path  $localStore/$packageBaseName/$packageVersion)) {
                New-Item -ItemType directory -Path $localStore/$packageBaseName/$packageVersion >$null 2>&1
            } else {
            
                $doOverride = $false
                if (-Not $overrideAllPackages) {
                    $res = Read-Host -Prompt "Package already exists do you want to override?[(Y)es/(N)o/Yes to (A)ll]"
                    if (($res -eq "y") -Or ($res -eq "Y")) {
                        $doOverride = $true
                    }elseif(($res -eq "a") -Or ($res -eq "A")) {
                        $doOverride = $true
                        $overrideAllPackages = $true
                    }
                }

                if ($overrideAllPackages -Or $doOverride){
                    Remove-Item -Path $localStore/$packageBaseName/$packageVersion -Force -Recurse >$null 2>&1
                    New-Item -ItemType directory -Path $localStore/$packageBaseName/$packageVersion >$null 2>&1
                }            
                else{
                    echo "Package not added"
                    continue
                }
                
            }
            
            $packageNameLowercase = $packageName.ToLower()
            
            #Calculate Hash
            $packageHash = Convert-HexToByteArray $(Get-FileHash $packageToAdd -Algorithm SHA512).Hash
            $packageHash = [System.Convert]::ToBase64String($packageHash)
            
            #Write hash file
            $packageHash | Out-File -NoNewline -FilePath $localStore/$packageBaseName/$packageVersion/$packageNameLowercase.sha512 -NoClobber >$null 2>&1
            
            #Write metadata
            New-Item $localStore/$packageBaseName/$packageVersion/.nupkg.metadata >$null 2>&1
            Set-Content $localStore/$packageBaseName/$packageVersion/.nupkg.metadata "{" >$null 2>&1
            Add-Content $localStore/$packageBaseName/$packageVersion/.nupkg.metadata "  `"version`": 1," >$null 2>&1
            Add-Content $localStore/$packageBaseName/$packageVersion/.nupkg.metadata "  `"contentHash`": `"$packageHash`"" >$null 2>&1
            Add-Content $localStore/$packageBaseName/$packageVersion/.nupkg.metadata "}" -NoNewline >$null 2>&1
            
            #Extract nuspec
            $zip = [System.IO.Compression.ZipFile]::OpenRead($packageToAdd)
            $zip.Entries | Where-Object { $_.FullName -like "*.nuspec" } |
                  ForEach-Object { 
                        $FileName = $_.Name.ToLower()
                        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, "$localStore/$packageBaseName/$packageVersion/$FileName", $true)
                    }
            #Copy package
            Copy-Item $packageToAdd $localStore/$packageBaseName/$packageVersion/$packageBaseName.$packageVersion.nupkg
            
            #Uninstall package locally
            if (Test-Path -Path $NUGET_BASE_PATH/packages/$packageBaseName/$packageVersion) {
                $doUninstall = $false
                if (-Not $uninstallAllPackages) {
                    $res = Read-Host -Prompt "Package already installed locally do you want to uninstall it?[(Y)es/(N)o/Yes to (A)ll]"
                    if (($res -eq "y") -Or ($res -eq "Y")) {
                        $doUninstall = $true
                    }elseif(($res -eq "a") -Or ($res -eq "A")) {
                        $doUninstall = $true
                        $uninstallAllPackages = $true
                    }
                }
                if ($uninstallAllPackages -Or $doUninstall){
                    Remove-Item -Path $NUGET_BASE_PATH/packages/$packageBaseName/$packageVersion -Force -Recurse >$null 2>&1
                }
                else{
                    echo "Package not uninstalled"
                }
            }
        }
    }
}
