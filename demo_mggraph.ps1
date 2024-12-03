# Signin with User Credentials, using the Graph SDK Enterprise App
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All", "DeviceManagementManagedDevices.PrivilegedOperations.All"

# Get the list of all Intune Filters using Invoke-MgGraphRequest - ONLY in Beta
$filters = Invoke-MgGraphRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters' -Method Get

# More than 100?
# Handle paging (throttling is already handled by MGGraph)
# Also - directly returns "values" array
function Invoke-MgGraphRequestAll {
    param (
        [string]$Uri
    )
    $result = Invoke-MgGraphRequest -Uri $Uri -Method GET
    $results = $result.value
    while ($sresult.'@odata.nextLink') {
        $nextLink = $sresult.'@odata.nextLink'
        $result = Invoke-MgGraphRequest -Uri $nextLink -Method GET
        $results += $result.value
    }
    return $results
}

$filters = Invoke-MgGraphRequestAll -Uri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters' 
# If you use Microsoft.Graph.Beta.DeviceManagement: Get-MgBetaDeviceManagementAssignmentFilter

# Export to a CSV file. Use Select-Object to choose and sort the properties
$filters | select-object -Property id, displayName, platform, rule | Export-Csv -Path "filters.csv" -NoTypeInformation 

# Create a new filter (you could use data from the CSV file)
$body = @{
    displayName = "Filter Demo"
    platform    = "windows10AndLater"
    rule        = 'device.osVersion -eq "10.0.19041.1"'
}
$createdFilter = Invoke-MgGraphRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters' -Method Post -body $body

# "$createdFilter" will contain the new filter object's properties, including its object id
$createdFilter.id

## Sync all Intune devices

# Get all Intune devices - needs "DeviceManagementManagedDevices.Read.All" permission
$devices = Invoke-MgGraphRequestAll -Uri 'https://graph.microsoft.com/beta/deviceManagement/managedDevices'

# You can get each devices Intune object id and infos.
"# ID:     " + $devices[1].id
"# Serial: " + $devices[1].serialNumber
"# Name:   " + $devices[1].deviceName

# use foreach to sync each device - needs "DeviceManagementManagedDevices.PrivilegedOperations.All" permission
foreach ($device in $devices) {
    Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($device.id)/syncDevice" -Method Post
}

Disconnect-MgGraph