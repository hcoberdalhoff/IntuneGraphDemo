## Authentication Start

# Fill in your App ID, Tenant ID, and Certificate Thumbprint
$appid = '<YourAppIdHere>' # App ID of the App Registration
$tenantid = '<YourTenantIdHere>' # Tenant ID of your EntraID
$certThumbprint = '<YourCertificateThumbprintHere>' # Thumbprint of the certificate associated with the App Registration
# $certName = '<YourCertificateNameHere>' # Name of the certificate associated with the App Registration

$requiredPermissions = @(
        @{
            Permission = "User.Read.All"
            Reason     = "Required to read user profile information and check group memberships"
        },
        @{
            Permission = "Group.Read.All"
            Reason     = "Needed to read group information and memberships"
        },
        @{
            Permission = "DeviceManagementConfiguration.Read.All"
            Reason     = "Allows reading Intune device configuration policies and their assignments"
        },
        @{
            Permission = "DeviceManagementApps.Read.All"
            Reason     = "Necessary to read mobile app management policies and app configurations"
        },
        @{
            Permission = "DeviceManagementManagedDevices.Read.All"
            Reason     = "Required to read managed device information and compliance policies"
        },
        @{
            Permission = "Device.Read.All"
            Reason     = "Needed to read device information from Entra ID"
        }
    )

    # Check if any of the variables are not set or contain placeholder values
    if (-not $appid -or $appid -eq '<YourAppIdHere>' -or
        -not $tenantid -or $tenantid -eq '<YourTenantIdHere>' -or
        -not $certThumbprint -or $certThumbprint -eq '<YourCertificateThumbprintHere>') {
        Write-Host "App ID, Tenant ID, or Certificate Thumbprint is missing or not set correctly." -ForegroundColor Red
        $manualConnection = Read-Host "Would you like to attempt a manual interactive connection? (y/n)"
        if ($manualConnection -eq 'y') {
            # Manual connection using interactive login
            write-host "Attempting manual interactive connection (you need privileges to consent permissions)..." -ForegroundColor Yellow
            $permissionsList = ($requiredPermissions | ForEach-Object { $_.Permission }) -join ', '
            $connectionResult = Connect-MgGraph -Scopes $permissionsList -NoWelcome -ErrorAction Stop
        }
        else {
            Write-Host "Script execution cancelled by user." -ForegroundColor Red
            exit
        }
    }
      else {
        $connectionResult = Connect-MgGraph -ClientId $appid -TenantId $tenantid -CertificateThumbprint $certThumbprint -NoWelcome -ErrorAction Stop
    }

## Authentication End

## Check Scope Permissions

# Check and display the current permissions
    $context = Get-MgContext
    $currentPermissions = $context.Scopes

    Write-Host "Checking required permissions:" -ForegroundColor Cyan
    $missingPermissions = @()
    foreach ($permissionInfo in $requiredPermissions) {
        $permission = $permissionInfo.Permission
        $reason = $permissionInfo.Reason

        # Check if either the exact permission or a "ReadWrite" version of it is granted
        $hasPermission = $currentPermissions -contains $permission -or $currentPermissions -contains $permission.Replace(".Read", ".ReadWrite")

        if ($hasPermission) {
            Write-Host "  [✓] $permission" -ForegroundColor Green
            Write-Host "      Reason: $reason" -ForegroundColor Gray
        }
        else {
            Write-Host "  [✗] $permission" -ForegroundColor Red
            Write-Host "      Reason: $reason" -ForegroundColor Gray
            $missingPermissions += $permission
        }
    }

    if ($missingPermissions.Count -eq 0) {
        Write-Host "All required permissions are present." -ForegroundColor Green
        Write-Host ""
    }
    else {
        Write-Host "WARNING: The following permissions are missing:" -ForegroundColor Red
        $missingPermissions | ForEach-Object { 
            $missingPermission = $_
            $reason = ($requiredPermissions | Where-Object { $_.Permission -eq $missingPermission }).Reason
            Write-Host "  - $missingPermission" -ForegroundColor Yellow
            Write-Host "    Reason: $reason" -ForegroundColor Gray
        }
        Write-Host "The script will continue, but it may not function correctly without these permissions." -ForegroundColor Red
        Write-Host "Please ensure these permissions are granted to the app registration for full functionality." -ForegroundColor Yellow
        
        $continueChoice = Read-Host "Do you want to continue anyway? (y/n)"
        if ($continueChoice -ne 'y') {
            Write-Host "Script execution cancelled by user." -ForegroundColor Red
            exit
        }
    }

## Check Scope Permissions End


## Get all Windows Devices

$graphendpoint = "https://graph.microsoft.com/v1.0/devices?`$filter=operatingSystem eq 'Windows'"
$devices = Invoke-MgGraphRequest -Uri $graphendpoint -Method Get -ErrorAction Stop

$devices.value | Select-Object -Property displayName, operatingSystem, id, trustType, enrollmentProfileName

## Get all Devices End

## Get all Non-Compliant Devices

$graphendpoint = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=complianceState eq 'nonCompliant'"
$nonCompliantWindowsDevices = Invoke-MgGraphRequest -Uri $graphendpoint -Method Get -ErrorAction Stop

$nonCompliantWindowsDevices.value | Select-Object -Property deviceName, serialNumber, operatingSystem, complianceState, complianceGracePeriodExpirationDateTime, userPrincipalName

## Get all Non-Compliant Devices End

## Sync All Managed Devices in Intune

# Retrieve all managed devices
$graphendpoint = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
$managedDevices = Invoke-MgGraphRequest -Uri $graphendpoint -Method Get -ErrorAction Stop

# Loop through each device and trigger a sync action
foreach ($device in $managedDevices.value) {
    $deviceId = $device.id
    Write-Host "Triggering sync for device:" $device.deviceName -ForegroundColor Yellow

    # Trigger the sync action
    $syncEndpoint = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$deviceId/syncDevice"
    try {
        Invoke-MgGraphRequest -Uri $syncEndpoint -Method Post -ErrorAction Stop
        Write-Host "Sync triggered successfully for device:" $device.deviceName -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to trigger sync for device:" $device.deviceName -ForegroundColor Red
    }
}

Write-Host "Device sync process completed." -ForegroundColor Cyan

## Sync All Managed Devices End

## Rotate All Device Bitlocker Keys

# Get all managed Windows devices from Intune with pagination
$managedDevices = @()
$nextLink = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$select=id,deviceName,operatingSystem&`$filter=operatingSystem eq 'Windows'"

# This loop will get all managed devices from Intune with pagination
while ($nextLink) {
    $response = Invoke-MgGraphRequest -Method GET -Uri $nextLink
    $managedDevices += $response.value
    $nextLink = $response.'@odata.nextLink'
}

foreach ($device in $managedDevices) {
    $deviceId = $device.id
    $deviceName = $device.deviceName

    Write-Host "Processing device: $deviceName" -ForegroundColor Cyan

    # Attempt to rotate the BitLocker keys
    try {
        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$deviceId')/rotateBitLockerKeys" -ContentType "application/json"

        Write-Host "Successfully rotated BitLocker keys for device $deviceName" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to rotate BitLocker keys for device $deviceName" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

## Rotate All Device Bitlocker Keys End

## Check if Bitlocker Keys are stored in EntraID

# Function to get BitLocker key for a device
function Get-BitLockerKey {
    param (
        [string]$azureADDeviceId
    )

    $keyIdUri = "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$azureADDeviceId'"
    $keyIdResponse = Invoke-MgGraphRequest -Uri $keyIdUri -Method GET

    if ($keyIdResponse.value.Count -gt 0) {
        return "Yes"
    }
    return "No"
}

# Get all Windows devices from Intune (with pagination)
$devicesUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=operatingSystem eq 'Windows'"
$devices = @()

do {
    $response = Invoke-MgGraphRequest -Uri $devicesUri -Method GET
    $devices += $response.value
    $devicesUri = $response.'@odata.nextLink'
} while ($devicesUri)

$results = @()

foreach ($device in $devices) {
    $hasBitlockerKey = Get-BitLockerKey -azureADDeviceId $device.azureADDeviceId

    $results += [PSCustomObject]@{
        DeviceName = $device.deviceName
        SerialNumber = $device.serialNumber
        "BitLocker Key in EntraID" = $hasBitlockerKey
        "Last Sync With Intune" = $device.lastSyncDateTime.ToString("yyyy-MM-dd")
    }
}

# Display results
$results | Format-Table -AutoSize

# Calculate summary statistics
$totalDevices = $results.Count
$devicesWithKey = ($results | Where-Object { $_.'BitLocker Key in EntraID' -eq 'Yes' }).Count
$devicesWithoutKey = $totalDevices - $devicesWithKey

# Display summary
Write-Host "`nSummary:" -ForegroundColor Cyan
Write-Host "Total Windows devices in Intune: $totalDevices" -ForegroundColor Yellow
Write-Host "Devices with BitLocker key stored in Entra ID: $devicesWithKey" -ForegroundColor Green
Write-Host "Devices without BitLocker key stored in Entra ID: $devicesWithoutKey" -ForegroundColor Red

## Check if Bitlocker Keys are stored in EntraID End