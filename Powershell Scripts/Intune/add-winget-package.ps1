<#PSScriptInfo
.VERSION 3.0
.AUTHOR AndrewTaylor
.DESCRIPTION Creates an Intune application from a Winget Manifest
.GUID ebed646c-ee4a-418c-ac46-0a2af1925016
.COMPANYNAME 
.COPYRIGHT GPL
.TAGS intune aad
.LICENSEURI https://github.com/andrew-s-taylor/public/blob/main/LICENSE
.PROJECTURI https://github.com/andrew-s-taylor/public
.ICONURI 
.EXTERNALMODULEDEPENDENCIES powershell-yaml AzureADPreview IntuneWin32App
.REQUIREDSCRIPTS 
.EXTERNALSCRIPTDEPENDENCIES
.RELEASENOTES
#>
<#
.SYNOPSIS
  Creates an Intune application from a Winget Manifest
.DESCRIPTION
Complete end-end creation of application in Intune.
Creates AzureAD group for Install and Uninstall
Extracts information from Winget custom manifest

.INPUTS
Winget YAML URL
.OUTPUTS
None
.NOTES
  Version:        3.0
  Author:         Andrew Taylor
  Twitter:        @AndrewTaylor_2
  WWW:            andrewstaylor.com
  Creation Date:  12/11/2021
  Modified Date:  08/05/2022
  Purpose/Change: Initial script development
  Change:   Switched AAD to Graph Module
  Change: Added app reg connection
  Change: Added web hook ability
  Change: Creates groups if they don't exist
  Change: Switched to using content prep tool to lose Windows requirement

.EXAMPLE
N/A
#>
[CmdletBinding()]
param (
    [Parameter()]
    [String]$yamlFile,
    [string]$tenant #Tenant ID (optional) for when automating and you want to use across tenants instead of hard-coded
    ,
    [string]$clientid #ClientID is the type of Azure AD App Reg ID
    ,
    [string]$clientsecret #ClientSecret is the type of Azure AD App Reg Secret
    ,
    [string]$email #Email for confirmation
    ,
    [object] $WebHookData #Webhook data for Azure Automation
)

###############################################################################################################
######                                         Install Modules                                           ######
###############################################################################################################
Write-Host "Installing Intune modules if required (current user scope)"

#Install MS Graph if not available
if (Get-Module -ListAvailable -Name powershell-yaml) {
    Write-Host "PowerShell YAML Already Installed"
} 
else {
    try {
        Install-Module -Name powershell-yaml -Scope CurrentUser -Repository PSGallery -Force 
    }
    catch [Exception] {
        $_.message 
    }
}

Write-Host "Installing Microsoft Graph modules if required (current user scope)"

#Install MS Graph if not available
if (Get-Module -ListAvailable -Name Microsoft.Graph.authentication) {
    Write-Host "Microsoft Graph Already Installed"
} 
else {
    try {
        Install-Module -Name Microsoft.Graph.authentication -Scope CurrentUser -Repository PSGallery -Force 
    }
    catch [Exception] {
        $_.message 
    }
}

#Install MS Graph if not available
if (Get-Module -ListAvailable -Name Microsoft.Graph.groups) {
    Write-Host "Microsoft Graph Already Installed"
} 
else {
    try {
        Install-Module -Name Microsoft.Graph.groups -Scope CurrentUser -Repository PSGallery -Force 
    }
    catch [Exception] {
        $_.message 
    }
}


#Install IntuneWin32App  if not available
if (Get-Module -ListAvailable -Name IntuneWin32App ) {
    Write-Host "IntuneWin32App Module Already Installed"
} 
else {
    try {
        Install-Module -Name IntuneWin32App  -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -AcceptLicense
    }
    catch [Exception] {
        $_.message 
    }
}

if (Get-Module -ListAvailable -Name SvRooij.ContentPrep.Cmdlet ) {
    Write-Host "ContentPrep Installed"

} 
else {

        Install-Module -Name SvRooij.ContentPrep.Cmdlet  -Scope CurrentUser -Repository PSGallery -Force 
    }


#Importing Modules
Import-Module -Name SvRooij.ContentPrep.Cmdlet

#Importing Modules
Import-Module powershell-yaml
import-module IntuneWin32App 
Import-Module microsoft.graph.authentication
import-module microsoft.graph.groups


###############################################################################################################
######                                         Add functions                                             ######
###############################################################################################################

function checkforgroup() {

    [cmdletbinding()]
        
    param
    (
        $groupname
    )

    $url = "https://graph.microsoft.com/beta/groups?`$filter=displayName eq '$groupname'"
    $group = ((Invoke-MgGraphRequest -Uri $url -Method GET -OutputType PSObject -SkipHttpErrorCheck).value) | Sort-Object createdDateTime -Descending | Select-Object -First 1
        return $group.id
}

Function Connect-ToGraph {
    <#
.SYNOPSIS
Authenticates to the Graph API via the Microsoft.Graph.Authentication module.
 
.DESCRIPTION
The Connect-ToGraph cmdlet is a wrapper cmdlet that helps authenticate to the Intune Graph API using the Microsoft.Graph.Authentication module. It leverages an Azure AD app ID and app secret for authentication or user-based auth.
 
.PARAMETER Tenant
Specifies the tenant (e.g. contoso.onmicrosoft.com) to which to authenticate.
 
.PARAMETER AppId
Specifies the Azure AD app ID (GUID) for the application that will be used to authenticate.
 
.PARAMETER AppSecret
Specifies the Azure AD app secret corresponding to the app ID that will be used to authenticate.

.PARAMETER Scopes
Specifies the user scopes for interactive authentication.
 
.EXAMPLE
Connect-ToGraph -TenantId $tenantID -AppId $app -AppSecret $secret
 
-#>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $false)] [string]$Tenant,
        [Parameter(Mandatory = $false)] [string]$AppId,
        [Parameter(Mandatory = $false)] [string]$AppSecret,
        [Parameter(Mandatory = $false)] [string]$scopes
    )

    Process {
        Import-Module Microsoft.Graph.Authentication
        $version = (get-module microsoft.graph.authentication | Select-Object -expandproperty Version).major

        if ($AppId -ne "") {
            $body = @{
                grant_type    = "client_credentials";
                client_id     = $AppId;
                client_secret = $AppSecret;
                scope         = "https://graph.microsoft.com/.default";
            }
     
            $response = Invoke-RestMethod -Method Post -Uri https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token -Body $body
            $accessToken = $response.access_token
     
            $accessToken
            if ($version -eq 2) {
                write-host "Version 2 module detected"
                $accesstokenfinal = ConvertTo-SecureString -String $accessToken -AsPlainText -Force
            }
            else {
                write-host "Version 1 Module Detected"
                Select-MgProfile -Name Beta
                $accesstokenfinal = $accessToken
            }
            $graph = Connect-MgGraph  -AccessToken $accesstokenfinal 
            Write-Host "Connected to Intune tenant $TenantId using app-based authentication (Azure AD authentication not supported)"
        }
        else {
            if ($version -eq 2) {
                write-host "Version 2 module detected"
            }
            else {
                write-host "Version 1 Module Detected"
                Select-MgProfile -Name Beta
            }
            $graph = Connect-MgGraph -scopes $scopes
            Write-Host "Connected to Intune tenant $($graph.TenantId)"
        }
    }
}    



###############################################################################################################
######                                        Pre-Requisite Work                                         ######
###############################################################################################################


if ($WebHookData){

    $bodyData = ConvertFrom-Json -InputObject $WebHookData.RequestBody
    $tenant = ((($bodyData.tenant) | out-string).trim())
    $clientid = ((($bodyData.clientid) | out-string).trim())
    $clientsecret = ((($bodyData.clientsecret) | out-string).trim())
    $yamlFile1 = ((($bodyData.yamlFile) | out-string).trim())
    $email = ((($bodyData.email) | out-string).trim())
    ##Convert $yamlFile1 from base64 and store in $yamlFile
    $yamlFile = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($yamlFile1))

    write-output $bodyData

}
#Get Creds and connect
#Connect to Graph
if ($clientid -and $clientsecret -and $tenant) {

    Connect-ToGraph -Tenant $tenant -AppId $clientid -AppSecret $clientsecret
    write-output "Graph Connection Established"
    
    }
    else {
    
Connect-ToGraph -Scopes "RoleAssignmentSchedule.ReadWrite.Directory, Domain.Read.All, Domain.ReadWrite.All, Directory.Read.All, Policy.ReadWrite.ConditionalAccess, DeviceManagementApps.ReadWrite.All, DeviceManagementConfiguration.ReadWrite.All, DeviceManagementManagedDevices.ReadWrite.All, openid, profile, email, offline_access"
write-output "Graph Connection Established"

    }

#Get Tenant ID
write-output "Grabbing Tenant ID"
$uri = "https://graph.microsoft.com/beta/organization"
$tenantdetails = (Invoke-MgGraphRequest -Uri $uri -Method Get -OutputType PSObject).value
$tenantid = $tenantdetails.id
write-output "Tenant ID is $tenantid"
write-output "Connecting to App Module"
if ($clientid -and $clientsecret -and $tenant) {
Connect-MSIntuneGraph -TenantID $tenantId -ClientID $clientid -ClientSecret $clientsecret
}
else {
    Connect-MSIntuneGraph -TenantID $tenantId 
}
write-output "Connected"

##Set Download Directory

$directory = $env:TEMP
#Create Temp location
$random = Get-Random -Maximum 1000 
$random = $random.ToString()
$date =get-date -format yyMMddmmss
$date = $date.ToString()
$path2 = $random + "-"  + $date
$path = $directory + "\" + $path2 + "\"
new-item -ItemType Directory -Path $path




$filename = $yamlFile.Substring($yamlFile.LastIndexOf("/") + 1)

##File Name
$templateFilePath = $path + $filename

###############################################################################################################
######                                          Download YAML                                            ######
###############################################################################################################
write-output "Downloading YAML from $yamlFile"
Invoke-WebRequest `
   -Uri $yamlFile `
   -OutFile $templateFilePath `
   -UseBasicParsing `
   -Headers @{"Cache-Control"="no-cache"}

   write-output "YAML Downloaded, manipulating"
[string[]]$fileContent = Get-Content $templateFilePath
$content = ''
foreach ($line in $fileContent) { $content = $content + "`n" + $line }
$obj = ConvertFrom-Yaml $content
$tags = $obj.Tags
foreach ($tag in $tags) {
    if ($tag -like '*ICON*') {
        $icon = $tag
    }
    if ($tag -like '*DETECTION*') {
        $detection = $tag
    }
    if ($tag -like 'UNINSTALLCOMMAND*') {
        $uninstall = $tag
    }
    if ($tag -like '*ADGROUPI*') {
        $adgroupi = $tag
    }
    if ($tag -like '*ADGROUPU*') {
        $adgroupu = $tag
    }
}

write-output "Fields grabbed"
$icon2 = $icon -split '='
$iconpath = $icon2[1]
$iconname = $iconpath.Substring($iconpath.LastIndexOf("/") + 1)
$icondownload = $path + $iconname

write-output "Downloading icon"
##Download Icon
Invoke-WebRequest `
   -Uri $iconpath `
   -OutFile $icondownload `
   -UseBasicParsing `
   -Headers @{"Cache-Control"="no-cache"}

   write-output "Icon Downloaded"

$detection2 = $detection -split '='
$detectionrule = $detection2[1]

$uninstall2 = $uninstall -split '='
$uninstallcommand = $uninstall2[1]

$adgroupi2 = $adgroupi -split '='
$adgroupinstall = $adgroupi2[1]

$adgroupu2 = $adgroupu -split '='
$adgroupuninstall = $adgroupu2[1]

$publisher = $obj.publisher
$name = $obj.packagename
$description = $obj.shortdescription
$appversion = $obj.PackageVersion
$infourl = $obj.PackageUrl

write-output "Publisher is $publisher"
write-output "App name is $name"
write-output "App version is $appversion"
    ##Strip spaces and special characters into $nameid
    $nameid = $name -replace '[^a-zA-Z0-9]', ''

$apppath = "$path\$nameid"
new-item -Path $apppath -ItemType Directory -Force

write-output "Checking for groups"
$groupname1 = $name + "-INSTALL"
    ##Check if groups exist
    $installgrptest = checkforgroup -groupname $adgroupinstall
    if ($installgrptest) {
        write-output "Install group exists, continuing"
        $installid = $installgrptest
    }
    else {
#Create Install Group
write-output "Install group does not exist, creating group"
$installgroup = New-MgGroup -DisplayName $adgroupinstall -Description "Install group for $name" -SecurityEnabled -MailEnabled:$false -MailNickName "group" 
$installid = $installgroup.id
write-output "Install group created"
    }

$groupname2 = $name + "-UNINSTALL"
#Create Uninstall Group
$uninstallgrptest = checkforgroup -groupname $adgroupuninstall
if ($uninstallgrptest) {
    write-output "Uninstall group exists, continuing"

    $uninstallid = $uninstallgrptest
}
else {
    write-output "Uninstall group does not exist, creating group"

$uninstallgroup = New-MgGroup -DisplayName $adgroupuninstall -Description "Uninstall group for $name" -SecurityEnabled -MailEnabled:$false -MailNickName "group" 
$uninstallid = $uninstallgroup.id
write-output "Uninstall group created"

}

write-output "Creating Setup file"
$setupfile = "$apppath\$name-Install.ps1"
$setupfilename = "$name-Install.ps1"
##Create Install File
Set-Content $setupfile @'

$filename2 = 
'@ -NoNewline
add-Content $setupfile @"
"$filename"
"@
add-Content $setupfile @'
$filename = $filename2.Substring($filename2.LastIndexOf("/") + 1)
   $curDir = Get-Location
   $filebase = Join-Path $curDir $filename
   $Winget = Get-ChildItem -Path (Join-Path -Path (Join-Path -Path $env:ProgramFiles -ChildPath "WindowsApps") -ChildPath "Microsoft.DesktopAppInstaller*_x64*\Winget.exe")
   Start-Process -NoNewWindow -FilePath $winget -ArgumentList "settings --enable LocalManifestFiles"
   Start-Process -NoNewWindow -FilePath $winget -ArgumentList "install --silent  --manifest $filename"

'@
write-output "File created"

write-output "Creating Detection fule"
$path4 = $detectionrule
$fname = $path4.Substring($path4.LastIndexOf("\") + 1)
$fpath = Split-Path -Path $path4

write-output "Rule created"

write-output "Creating intunewin"

    # Package as .intunewin file
    #New-IntuneWin32AppPackage -SourceFolder $SourceFolder -SetupFile $setupfilename -OutputFolder $OutputFolder -Verbose
    $intunewinpath = $path + "\install$nameid.intunewin"
    New-IntuneWinPackage -SourcePath "$apppath" -SetupFile "$setupfilename" -DestinationPath "$path" 
    Write-Host "Intunewin $intunewinpath Created"
    $sleep = 10
    foreach ($i in 0..$sleep) {
        Write-Progress -Activity "Sleeping for $($sleep-$i) seconds" -PercentComplete ($i / $sleep * 100) -SecondsRemaining ($sleep - $i)
        Start-Sleep -s 1
    }

    $IntuneWinFile = Get-ChildItem -Path  $path | Where-Object Name -Like "*.intunewin"
    $IntuneWinFile.Name

    # Create custom display name like 'Name' and 'Version'
    $DisplayName = $name

    # Create detection rule
    $DetectionRule = New-IntuneWin32AppDetectionRuleFile -Existence -Path "$fpath" -FileOrFolder $fname -Check32BitOn64System $false -DetectionType "exists"

write-output "Created"

    # Add new EXE Win32 app
    $InstallationScriptFile = Get-ChildItem -Path $path | Where-Object Name -Like "*-Install.ps1"
    $InstallCommandLine = "powershell.exe -ExecutionPolicy Bypass -File .\$($InstallationScriptFile.Name)"
    $UninstallCommandLine = $uninstallcommand
    $ImageFile = $icondownload
    $Icon = New-IntuneWin32AppIcon -FilePath $ImageFile

    write-output "Adding app to Intune"
    Add-IntuneWin32App -FilePath $IntuneWinFile.FullName -DisplayName $DisplayName -Description $description -Publisher $publisher -AppVersion $appversion -InformationURL $infourl -Icon $Icon -InstallExperience "system" -RestartBehavior "suppress" -DetectionRule $DetectionRule -InstallCommandLine $InstallCommandLine -UninstallCommandLine $UninstallCommandLine -Verbose
    write-output "App added"

    ##Assignments
    $Win32App = (Get-IntuneWin32App -DisplayName $DisplayName -Verbose)  | Sort-Object createdDateTime -Descending | Select-Object -First 1



    #Install
    write-output "Assigning install group"
Add-IntuneWin32AppAssignmentGroup -Include -ID $Win32App.id -GroupID $installid -Intent "available" -Notification "showAll" -Verbose
write-output "Install group assigned"


#Uninstall
write-output "Assigning uninstall group"
Add-IntuneWin32AppAssignmentGroup -Include -ID $Win32App.id -GroupID $uninstallid -Intent "uninstall" -Notification "showAll" -Verbose
write-output "Uninstall group assigned"

# SIG # Begin signature block
# MIIoGQYJKoZIhvcNAQcCoIIoCjCCKAYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBPhbAS3AWXPXoq
# EBhhOSUfYQ2dMHY1D4X9SRaIHurrdKCCIRwwggWNMIIEdaADAgECAhAOmxiO+dAt
# 5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNV
# BAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0yMjA4MDEwMDAwMDBa
# Fw0zMTExMDkyMzU5NTlaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lD
# ZXJ0IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
# ggIBAL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3E
# MB/zG6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKy
# unWZanMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsF
# xl7sWxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU1
# 5zHL2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJB
# MtfbBHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObUR
# WBf3JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6
# nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxB
# YKqxYxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5S
# UUd0viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+x
# q4aLT8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjggE6MIIB
# NjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTs1+OC0nFdZEzfLmc/57qYrhwP
# TzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzAOBgNVHQ8BAf8EBAMC
# AYYweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdp
# Y2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNv
# bS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwRQYDVR0fBD4wPDA6oDigNoY0
# aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENB
# LmNybDARBgNVHSAECjAIMAYGBFUdIAAwDQYJKoZIhvcNAQEMBQADggEBAHCgv0Nc
# Vec4X6CjdBs9thbX979XB72arKGHLOyFXqkauyL4hxppVCLtpIh3bb0aFPQTSnov
# Lbc47/T/gLn4offyct4kvFIDyE7QKt76LVbP+fT3rDB6mouyXtTP0UNEm0Mh65Zy
# oUi0mcudT6cGAxN3J0TU53/oWajwvy8LpunyNDzs9wPHh6jSTEAZNUZqaVSwuKFW
# juyk1T3osdz9HNj0d1pcVIxv76FQPfx2CWiEn2/K2yCNNWAcAgPLILCsWKAOQGPF
# mCLBsln1VWvPJ6tsds5vIy30fnFqI2si/xK4VC0nftg62fC2h5b9W9FcrBjDTZ9z
# twGpn1eqXijiuZQwggauMIIElqADAgECAhAHNje3JFR82Ees/ShmKl5bMA0GCSqG
# SIb3DQEBCwUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMx
# GTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRy
# dXN0ZWQgUm9vdCBHNDAeFw0yMjAzMjMwMDAwMDBaFw0zNzAzMjIyMzU5NTlaMGMx
# CzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMy
# RGlnaUNlcnQgVHJ1c3RlZCBHNCBSU0E0MDk2IFNIQTI1NiBUaW1lU3RhbXBpbmcg
# Q0EwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDGhjUGSbPBPXJJUVXH
# JQPE8pE3qZdRodbSg9GeTKJtoLDMg/la9hGhRBVCX6SI82j6ffOciQt/nR+eDzMf
# UBMLJnOWbfhXqAJ9/UO0hNoR8XOxs+4rgISKIhjf69o9xBd/qxkrPkLcZ47qUT3w
# 1lbU5ygt69OxtXXnHwZljZQp09nsad/ZkIdGAHvbREGJ3HxqV3rwN3mfXazL6IRk
# tFLydkf3YYMZ3V+0VAshaG43IbtArF+y3kp9zvU5EmfvDqVjbOSmxR3NNg1c1eYb
# qMFkdECnwHLFuk4fsbVYTXn+149zk6wsOeKlSNbwsDETqVcplicu9Yemj052FVUm
# cJgmf6AaRyBD40NjgHt1biclkJg6OBGz9vae5jtb7IHeIhTZgirHkr+g3uM+onP6
# 5x9abJTyUpURK1h0QCirc0PO30qhHGs4xSnzyqqWc0Jon7ZGs506o9UD4L/wojzK
# QtwYSH8UNM/STKvvmz3+DrhkKvp1KCRB7UK/BZxmSVJQ9FHzNklNiyDSLFc1eSuo
# 80VgvCONWPfcYd6T/jnA+bIwpUzX6ZhKWD7TA4j+s4/TXkt2ElGTyYwMO1uKIqjB
# Jgj5FBASA31fI7tk42PgpuE+9sJ0sj8eCXbsq11GdeJgo1gJASgADoRU7s7pXche
# MBK9Rp6103a50g5rmQzSM7TNsQIDAQABo4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB
# /wIBADAdBgNVHQ4EFgQUuhbZbU2FL3MpdpovdYxqII+eyG8wHwYDVR0jBBgwFoAU
# 7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoG
# CCsGAQUFBwMIMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29j
# c3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0cy5kaWdp
# Y2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNydDBDBgNVHR8EPDA6MDig
# NqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9v
# dEc0LmNybDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEwDQYJKoZI
# hvcNAQELBQADggIBAH1ZjsCTtm+YqUQiAX5m1tghQuGwGC4QTRPPMFPOvxj7x1Bd
# 4ksp+3CKDaopafxpwc8dB+k+YMjYC+VcW9dth/qEICU0MWfNthKWb8RQTGIdDAiC
# qBa9qVbPFXONASIlzpVpP0d3+3J0FNf/q0+KLHqrhc1DX+1gtqpPkWaeLJ7giqzl
# /Yy8ZCaHbJK9nXzQcAp876i8dU+6WvepELJd6f8oVInw1YpxdmXazPByoyP6wCeC
# RK6ZJxurJB4mwbfeKuv2nrF5mYGjVoarCkXJ38SNoOeY+/umnXKvxMfBwWpx2cYT
# gAnEtp/Nh4cku0+jSbl3ZpHxcpzpSwJSpzd+k1OsOx0ISQ+UzTl63f8lY5knLD0/
# a6fxZsNBzU+2QJshIUDQtxMkzdwdeDrknq3lNHGS1yZr5Dhzq6YBT70/O3itTK37
# xJV77QpfMzmHQXh6OOmc4d0j/R0o08f56PGYX/sr2H7yRp11LB4nLCbbbxV7HhmL
# NriT1ObyF5lZynDwN7+YAN8gFk8n+2BnFqFmut1VwDophrCYoCvtlUG3OtUVmDG0
# YgkPCr2B2RP+v6TR81fZvAT6gt4y3wSJ8ADNXcL50CN/AAvkdgIm2fBldkKmKYcJ
# RyvmfxqkhQ/8mJb2VVQrH4D6wPIOK+XW+6kvRBVK5xMOHds3OBqhK/bt1nz8MIIG
# sDCCBJigAwIBAgIQCK1AsmDSnEyfXs2pvZOu2TANBgkqhkiG9w0BAQwFADBiMQsw
# CQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cu
# ZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQw
# HhcNMjEwNDI5MDAwMDAwWhcNMzYwNDI4MjM1OTU5WjBpMQswCQYDVQQGEwJVUzEX
# MBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0
# ZWQgRzQgQ29kZSBTaWduaW5nIFJTQTQwOTYgU0hBMzg0IDIwMjEgQ0ExMIICIjAN
# BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA1bQvQtAorXi3XdU5WRuxiEL1M4zr
# PYGXcMW7xIUmMJ+kjmjYXPXrNCQH4UtP03hD9BfXHtr50tVnGlJPDqFX/IiZwZHM
# gQM+TXAkZLON4gh9NH1MgFcSa0OamfLFOx/y78tHWhOmTLMBICXzENOLsvsI8Irg
# nQnAZaf6mIBJNYc9URnokCF4RS6hnyzhGMIazMXuk0lwQjKP+8bqHPNlaJGiTUyC
# EUhSaN4QvRRXXegYE2XFf7JPhSxIpFaENdb5LpyqABXRN/4aBpTCfMjqGzLmysL0
# p6MDDnSlrzm2q2AS4+jWufcx4dyt5Big2MEjR0ezoQ9uo6ttmAaDG7dqZy3SvUQa
# khCBj7A7CdfHmzJawv9qYFSLScGT7eG0XOBv6yb5jNWy+TgQ5urOkfW+0/tvk2E0
# XLyTRSiDNipmKF+wc86LJiUGsoPUXPYVGUztYuBeM/Lo6OwKp7ADK5GyNnm+960I
# HnWmZcy740hQ83eRGv7bUKJGyGFYmPV8AhY8gyitOYbs1LcNU9D4R+Z1MI3sMJN2
# FKZbS110YU0/EpF23r9Yy3IQKUHw1cVtJnZoEUETWJrcJisB9IlNWdt4z4FKPkBH
# X8mBUHOFECMhWWCKZFTBzCEa6DgZfGYczXg4RTCZT/9jT0y7qg0IU0F8WD1Hs/q2
# 7IwyCQLMbDwMVhECAwEAAaOCAVkwggFVMBIGA1UdEwEB/wQIMAYBAf8CAQAwHQYD
# VR0OBBYEFGg34Ou2O/hfEYb7/mF7CIhl9E5CMB8GA1UdIwQYMBaAFOzX44LScV1k
# TN8uZz/nupiuHA9PMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAKBggrBgEFBQcD
# AzB3BggrBgEFBQcBAQRrMGkwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2lj
# ZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29t
# L0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcnQwQwYDVR0fBDwwOjA4oDagNIYyaHR0
# cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcmww
# HAYDVR0gBBUwEzAHBgVngQwBAzAIBgZngQwBBAEwDQYJKoZIhvcNAQEMBQADggIB
# ADojRD2NCHbuj7w6mdNW4AIapfhINPMstuZ0ZveUcrEAyq9sMCcTEp6QRJ9L/Z6j
# fCbVN7w6XUhtldU/SfQnuxaBRVD9nL22heB2fjdxyyL3WqqQz/WTauPrINHVUHmI
# moqKwba9oUgYftzYgBoRGRjNYZmBVvbJ43bnxOQbX0P4PpT/djk9ntSZz0rdKOtf
# JqGVWEjVGv7XJz/9kNF2ht0csGBc8w2o7uCJob054ThO2m67Np375SFTWsPK6Wrx
# oj7bQ7gzyE84FJKZ9d3OVG3ZXQIUH0AzfAPilbLCIXVzUstG2MQ0HKKlS43Nb3Y3
# LIU/Gs4m6Ri+kAewQ3+ViCCCcPDMyu/9KTVcH4k4Vfc3iosJocsL6TEa/y4ZXDlx
# 4b6cpwoG1iZnt5LmTl/eeqxJzy6kdJKt2zyknIYf48FWGysj/4+16oh7cGvmoLr9
# Oj9FpsToFpFSi0HASIRLlk2rREDjjfAVKM7t8RhWByovEMQMCGQ8M4+uKIw8y4+I
# Cw2/O/TOHnuO77Xry7fwdxPm5yg/rBKupS8ibEH5glwVZsxsDsrFhsP2JjMMB0ug
# 0wcCampAMEhLNKhRILutG4UI4lkNbcoFUCvqShyepf2gpx8GdOfy1lKQ/a+FSCH5
# Vzu0nAPthkX0tGFuv2jiJmCG6sivqf6UHedjGzqGVnhOMIIGwjCCBKqgAwIBAgIQ
# BUSv85SdCDmmv9s/X+VhFjANBgkqhkiG9w0BAQsFADBjMQswCQYDVQQGEwJVUzEX
# MBUGA1UEChMORGlnaUNlcnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0
# ZWQgRzQgUlNBNDA5NiBTSEEyNTYgVGltZVN0YW1waW5nIENBMB4XDTIzMDcxNDAw
# MDAwMFoXDTM0MTAxMzIzNTk1OVowSDELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRp
# Z2lDZXJ0LCBJbmMuMSAwHgYDVQQDExdEaWdpQ2VydCBUaW1lc3RhbXAgMjAyMzCC
# AiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAKNTRYcdg45brD5UsyPgz5/X
# 5dLnXaEOCdwvSKOXejsqnGfcYhVYwamTEafNqrJq3RApih5iY2nTWJw1cb86l+uU
# UI8cIOrHmjsvlmbjaedp/lvD1isgHMGXlLSlUIHyz8sHpjBoyoNC2vx/CSSUpIIa
# 2mq62DvKXd4ZGIX7ReoNYWyd/nFexAaaPPDFLnkPG2ZS48jWPl/aQ9OE9dDH9kgt
# XkV1lnX+3RChG4PBuOZSlbVH13gpOWvgeFmX40QrStWVzu8IF+qCZE3/I+PKhu60
# pCFkcOvV5aDaY7Mu6QXuqvYk9R28mxyyt1/f8O52fTGZZUdVnUokL6wrl76f5P17
# cz4y7lI0+9S769SgLDSb495uZBkHNwGRDxy1Uc2qTGaDiGhiu7xBG3gZbeTZD+BY
# QfvYsSzhUa+0rRUGFOpiCBPTaR58ZE2dD9/O0V6MqqtQFcmzyrzXxDtoRKOlO0L9
# c33u3Qr/eTQQfqZcClhMAD6FaXXHg2TWdc2PEnZWpST618RrIbroHzSYLzrqawGw
# 9/sqhux7UjipmAmhcbJsca8+uG+W1eEQE/5hRwqM/vC2x9XH3mwk8L9CgsqgcT2c
# kpMEtGlwJw1Pt7U20clfCKRwo+wK8REuZODLIivK8SgTIUlRfgZm0zu++uuRONhR
# B8qUt+JQofM604qDy0B7AgMBAAGjggGLMIIBhzAOBgNVHQ8BAf8EBAMCB4AwDAYD
# VR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAgBgNVHSAEGTAXMAgG
# BmeBDAEEAjALBglghkgBhv1sBwEwHwYDVR0jBBgwFoAUuhbZbU2FL3MpdpovdYxq
# II+eyG8wHQYDVR0OBBYEFKW27xPn783QZKHVVqllMaPe1eNJMFoGA1UdHwRTMFEw
# T6BNoEuGSWh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRH
# NFJTQTQwOTZTSEEyNTZUaW1lU3RhbXBpbmdDQS5jcmwwgZAGCCsGAQUFBwEBBIGD
# MIGAMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wWAYIKwYB
# BQUHMAKGTGh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0
# ZWRHNFJTQTQwOTZTSEEyNTZUaW1lU3RhbXBpbmdDQS5jcnQwDQYJKoZIhvcNAQEL
# BQADggIBAIEa1t6gqbWYF7xwjU+KPGic2CX/yyzkzepdIpLsjCICqbjPgKjZ5+PF
# 7SaCinEvGN1Ott5s1+FgnCvt7T1IjrhrunxdvcJhN2hJd6PrkKoS1yeF844ektrC
# QDifXcigLiV4JZ0qBXqEKZi2V3mP2yZWK7Dzp703DNiYdk9WuVLCtp04qYHnbUFc
# jGnRuSvExnvPnPp44pMadqJpddNQ5EQSviANnqlE0PjlSXcIWiHFtM+YlRpUurm8
# wWkZus8W8oM3NG6wQSbd3lqXTzON1I13fXVFoaVYJmoDRd7ZULVQjK9WvUzF4UbF
# KNOt50MAcN7MmJ4ZiQPq1JE3701S88lgIcRWR+3aEUuMMsOI5ljitts++V+wQtaP
# 4xeR0arAVeOGv6wnLEHQmjNKqDbUuXKWfpd5OEhfysLcPTLfddY2Z1qJ+Panx+VP
# NTwAvb6cKmx5AdzaROY63jg7B145WPR8czFVoIARyxQMfq68/qTreWWqaNYiyjvr
# moI1VygWy2nyMpqy0tg6uLFGhmu6F/3Ed2wVbK6rr3M66ElGt9V/zLY4wNjsHPW2
# obhDLN9OTH0eaHDAdwrUAuBcYLso/zjlUlrWrBciI0707NMX+1Br/wd3H3GXREHJ
# uEbTbDJ8WC9nR2XlG3O2mflrLAZG70Ee8PBf4NvZrZCARK+AEEGKMIIHWzCCBUOg
# AwIBAgIQCLGfzbPa87AxVVgIAS8A6TANBgkqhkiG9w0BAQsFADBpMQswCQYDVQQG
# EwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0
# IFRydXN0ZWQgRzQgQ29kZSBTaWduaW5nIFJTQTQwOTYgU0hBMzg0IDIwMjEgQ0Ex
# MB4XDTIzMTExNTAwMDAwMFoXDTI2MTExNzIzNTk1OVowYzELMAkGA1UEBhMCR0Ix
# FDASBgNVBAcTC1doaXRsZXkgQmF5MR4wHAYDVQQKExVBTkRSRVdTVEFZTE9SLkNP
# TSBMVEQxHjAcBgNVBAMTFUFORFJFV1NUQVlMT1IuQ09NIExURDCCAiIwDQYJKoZI
# hvcNAQEBBQADggIPADCCAgoCggIBAMOkYkLpzNH4Y1gUXF799uF0CrwW/Lme676+
# C9aZOJYzpq3/DIa81oWv9b4b0WwLpJVu0fOkAmxI6ocu4uf613jDMW0GfV4dRodu
# tryfuDuit4rndvJA6DIs0YG5xNlKTkY8AIvBP3IwEzUD1f57J5GiAprHGeoc4Utt
# zEuGA3ySqlsGEg0gCehWJznUkh3yM8XbksC0LuBmnY/dZJ/8ktCwCd38gfZEO9UD
# DSkie4VTY3T7VFbTiaH0bw+AvfcQVy2CSwkwfnkfYagSFkKar+MYwu7gqVXxrh3V
# /Gjval6PdM0A7EcTqmzrCRtvkWIR6bpz+3AIH6Fr6yTuG3XiLIL6sK/iF/9d4U2P
# iH1vJ/xfdhGj0rQ3/NBRsUBC3l1w41L5q9UX1Oh1lT1OuJ6hV/uank6JY3jpm+Of
# Z7YCTF2Hkz5y6h9T7sY0LTi68Vmtxa/EgEtG6JVNVsqP7WwEkQRxu/30qtjyoX8n
# zSuF7TmsRgmZ1SB+ISclejuqTNdhcycDhi3/IISgVJNRS/F6Z+VQGf3fh6ObdQLV
# woT0JnJjbD8PzJ12OoKgViTQhndaZbkfpiVifJ1uzWJrTW5wErH+qvutHVt4/sEZ
# AVS4PNfOcJXR0s0/L5JHkjtM4aGl62fAHjHj9JsClusj47cT6jROIqQI4ejz1slO
# oclOetCNAgMBAAGjggIDMIIB/zAfBgNVHSMEGDAWgBRoN+Drtjv4XxGG+/5hewiI
# ZfROQjAdBgNVHQ4EFgQU0HdOFfPxa9Yeb5O5J9UEiJkrK98wPgYDVR0gBDcwNTAz
# BgZngQwBBAEwKTAnBggrBgEFBQcCARYbaHR0cDovL3d3dy5kaWdpY2VydC5jb20v
# Q1BTMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzCBtQYDVR0f
# BIGtMIGqMFOgUaBPhk1odHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRU
# cnVzdGVkRzRDb2RlU2lnbmluZ1JTQTQwOTZTSEEzODQyMDIxQ0ExLmNybDBToFGg
# T4ZNaHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0Q29k
# ZVNpZ25pbmdSU0E0MDk2U0hBMzg0MjAyMUNBMS5jcmwwgZQGCCsGAQUFBwEBBIGH
# MIGEMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wXAYIKwYB
# BQUHMAKGUGh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0
# ZWRHNENvZGVTaWduaW5nUlNBNDA5NlNIQTM4NDIwMjFDQTEuY3J0MAkGA1UdEwQC
# MAAwDQYJKoZIhvcNAQELBQADggIBAEkRh2PwMiyravr66Zww6Pjl24KzDcGYMSxU
# KOEU4bykcOKgvS6V2zeZIs0D/oqct3hBKTGESSQWSA/Jkr1EMC04qJHO/Twr/sBD
# CDBMtJ9XAtO75J+oqDccM+g8Po+jjhqYJzKvbisVUvdsPqFll55vSzRvHGAA6hjy
# DyakGLROcNaSFZGdgOK2AMhQ8EULrE8Riri3D1ROuqGmUWKqcO9aqPHBf5wUwia8
# g980sTXquO5g4TWkZqSvwt1BHMmu69MR6loRAK17HvFcSicK6Pm0zid1KS2z4ntG
# B4Cfcg88aFLog3ciP2tfMi2xTnqN1K+YmU894Pl1lCp1xFvT6prm10Bs6BViKXfD
# fVFxXTB0mHoDNqGi/B8+rxf2z7u5foXPCzBYT+Q3cxtopvZtk29MpTY88GHDVJsF
# MBjX7zM6aCNKsTKC2jb92F+jlkc8clCQQnl3U4jqwbj4ur1JBP5QxQprWhwde0+M
# ifDVp0vHZsVZ0pnYMCKSG5bUr3wOU7EP321DwvvEsTjCy/XDgvy8ipU6w3GjcQQF
# mgp/BX/0JCHX+04QJ0JkR9TTFZR1B+zh3CcK1ZEtTtvuZfjQ3viXwlwtNLy43vbe
# 1J5WNTs0HjJXsfdbhY5kE5RhyfaxFBr21KYx+b+evYyolIS0wR6New6FqLgcc4Ge
# 94yaYVTqMYIGUzCCBk8CAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGln
# aUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgQ29kZSBT
# aWduaW5nIFJTQTQwOTYgU0hBMzg0IDIwMjEgQ0ExAhAIsZ/Ns9rzsDFVWAgBLwDp
# MA0GCWCGSAFlAwQCAQUAoIGEMBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJ
# KoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQB
# gjcCARUwLwYJKoZIhvcNAQkEMSIEIBnhmSNMb9PXTfW96hac+yK/ORYgXvcHqGbG
# q2Otpf9nMA0GCSqGSIb3DQEBAQUABIICAI0mo1OclpuKNWJb6+IspKT3HHQVOr09
# RFh2ZkVcXIrJyPa+ftOAQUUnWobuENu0Ws6SzZYV/RxY0NrdKl4uUI2PgF0cnaAa
# ohU02yqKu3A4lMek0zzlLt0usldCNKpaXlBtkAKLwmEPhHAPWL3nWIwpFULcfCYz
# 21LzECptbpNM+GH6ghWzk3oZ4eo948Bxoxnfgo+507rO7hIJVZtyFk1xJg7plmcF
# Y8ynmrhx9z/lPQO0u+s1wEUQ3YtqbaoF70G4NIiIBZQbiMYeqE20vLoSbhtL59He
# AhlZiwjd1bRSg8HrSn8j7HbVF3moFS5n/yX0lQtC4n/g2yWIR7tQdUjXyyeDirgk
# dmb34x8j/TIYk2jes3WUctAlQDIWtsqGZ5tWZ+Bjcw7IgimPAx0j7RSOgB3J8UOP
# OkF4jzigq1msvt1dZwu3wmBRko5c3DkxtovFxnHZeZ6nlryH5hpYn0meH2aH+wHY
# JYnNguGEUm8NDcFotHmOvnO5/UgnDTx6co6gikdsL+IOc2zlZbqF8x0myZ1XGRZ8
# lJ3xu6AR0nlLYWY3s1N1eirCzgVKyaP1NxstO+KGS+9zlsrHZ6jjwib3bNZSo474
# y48r53TSgDE2zR7SrxhTDBRe01z0ylDD/VvCO7c5RwuZekJZF2RSefmjNtGmJiDL
# xgCQHfUIpRVloYIDIDCCAxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkG
# A1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdp
# Q2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQ
# BUSv85SdCDmmv9s/X+VhFjANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzEL
# BgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTI0MDUwODA4NDk1MFowLwYJKoZI
# hvcNAQkEMSIEIM6nMqWM+MbPcEUp4sG79sy9n+fSengSg5QKAsPNiOLmMA0GCSqG
# SIb3DQEBAQUABIICAGI+9zAvVci7FX82xEC8t9DucBGFkLj9oPG2tJFxn0lbZm+1
# deYG6POsRgYZkZ4Ql7VdWTZYS9GU09WtOT0HrZoourPf+kxI2ujR6pgs9cZdi6BD
# s6TYmCMj6mNQXOwyeYIZ03SwEfpFMyxezwHsCec0mkJyf2PpYVKLw88KAYHUGQ3I
# bzcfmCkpuM+Kq2G1ThtyQTAOn2YUaQd1LQKWFlkkiQlEx3IJY2O1bAZ2/Tk8xXmp
# GbRNm6OCk1OSRYvOkjM/oDHMu0/ms0LDadVCnqUC65LNM3DRY6UXK6XTbcGHHLKt
# enUDqVx0O/zssbUBKXAdFEmEHgmipOGhX29p6/mj+jT7b+2DHydfx2QEPIVCPlED
# c11ylJWlEsrwbuMr6qcbXXQN0ITMntqG+Wr7N+dVwxznifyTeT++I+FlZ/6rkfQX
# MMrwdhRGwSHHnjbD81Q+ENuP9OtUq/cUVGgGMTS1Q1FLaf6nNXOUAYCejRhlH+ET
# ifWVaEoiUKvUb56GOUG4uBTdAq6T5tzA5LRUG5AZ6ZBHvT84OpUL5xw+T/kQc+Tx
# F9/wTaL0qW2OEdH8XQNwLkqh21uqMOdhbknPCBgZBS5k10W4n9H5kdnGotDeLTP4
# swhM+ESbLW6LYsKdQZEvzFUTOzUgblLKUmcpxOYyyMFpL+WwhbFW3xuUV52T
# SIG # End signature block
