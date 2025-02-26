# Configuration
$ClientId = "70e1355f-3082-4702-956e-13f1c9f328a3"
$ClientSecret = "e-MLnhuFBUzMcIG60zjHC6UrWIqLMDY9RHzkV6oxu2I"
$Region = "mypurecloud.ie"  # Change based on your region
$GroupId = "abbd4161-510c-4b20-ab48-faa3cca3a205"
$WorkTeamId = "eef6a722-d998-4d21-82a5-11fcd30a46eb"

# Authenticate with Genesys Cloud
$authUrl = "https://login.$Region/oauth/token"
$authHeaders = @{
    "Content-Type"  = "application/x-www-form-urlencoded"
}

$authBody = "grant_type=client_credentials&client_id=$ClientId&client_secret=$ClientSecret"
$tokenResponse = Invoke-RestMethod -Uri $authUrl -Method Post -Headers $authHeaders -Body $authBody
$AccessToken = $tokenResponse.access_token

$Headers = @{
    "Authorization" = "Bearer $AccessToken"
    "Content-Type"  = "application/json"
}

# Function to get users from a Genesys Cloud Group (Corrected API)
Function Get-GroupUsers {
    param($GroupId)
    $groupUsersUrl = "https://api.$Region/api/v2/groups/$GroupId/members?pageSize=100"
    $allUsers = @()

    do {
        Write-Host "Fetching Group Users from: $groupUsersUrl"
        $response = Invoke-RestMethod -Uri $groupUsersUrl -Method Get -Headers $Headers
        $allUsers += $response.entities | Select-Object -ExpandProperty id
        $groupUsersUrl = if ($response.nextUri) { "https://api.$Region" + $response.nextUri } else { $null }
    } while ($groupUsersUrl)

    return $allUsers
}


# Function to get users from a Genesys Cloud Work Team
Function Get-WorkTeamUsers {
    param($WorkTeamId)
    $workTeamUsersUrl = "https://apps.$Region/platform/api/v2/teams/$WorkTeamId/members"
    
    Write-Host "Fetching Work Team Users from: $workTeamUsersUrl"
    $response = Invoke-RestMethod -Uri $workTeamUsersUrl -Method Get -Headers $Headers

    if ($response.PSObject.Properties["entities"]) {
        return $response.entities | Select-Object -ExpandProperty id
    } else {
        Write-Host "⚠ No 'entities' field found in Work Team Members API response. Full Response:"
        Write-Host ($response | ConvertTo-Json -Depth 3)
        return @()
    }
}

# Function to add users to the work team
Function Add-UsersToWorkTeam {
    param($WorkTeamId, $UsersToAdd)

    if ($UsersToAdd.Count -gt 0) {
        # Ensure memberIds is always an array
        $UsersArray = @($UsersToAdd) 

        # Fixed version (since API doesn't return one)
        $WorkTeamVersion = 4

        # Prepare request body with correct structure
        $body = @{
            "memberIds" = $UsersArray
            "version"   = $WorkTeamVersion
        } | ConvertTo-Json -Depth 3

        $addUrl = "https://apps.$Region/platform/api/v2/teams/$WorkTeamId/members"

        Write-Host "🚀 Adding users: $UsersArray"
        Write-Host "🔍 JSON Payload: $body"

        # Make API request
        $response = Invoke-RestMethod -Uri $addUrl -Method Post -Headers $Headers -Body $body
        Write-Host "✅ Added users: " ($response | ConvertTo-Json -Depth 3)
    } else {
        Write-Host "ℹ No users to add. Skipping API call."
    }
}

# Function to remove users from the work team
Function Remove-UsersFromWorkTeam {
    param($WorkTeamId, $UsersToRemove)

    if ($UsersToRemove.Count -gt 0) {
        # Fixed version (since API doesn't return one)
        $WorkTeamVersion = 1

        # Prepare request body
        $body = @{
            "memberIds" = $UsersToRemove
            "version"   = $WorkTeamVersion
        } | ConvertTo-Json -Depth 3

        $removeUrl = "https://apps.$Region/platform/api/v2/teams/$WorkTeamId/members"

        Write-Host "❌ Removing users: $UsersToRemove"
        Write-Host "🔍 JSON Payload: $body"

        # Make API request
        $response = Invoke-RestMethod -Uri $removeUrl -Method Delete -Headers $Headers -Body $body
        Write-Host "✅ Removed users: " ($response | ConvertTo-Json -Depth 3)
    } else {
        Write-Host "ℹ No users to remove."
    }
}

# Get users in the Genesys Cloud Group and Work Team
$GroupUsers = Get-GroupUsers -GroupId $GroupId
$WorkTeamUsers = Get-WorkTeamUsers -WorkTeamId $WorkTeamId

# Debugging: Print users in group and work team
Write-Host "👥 Users in Group ($GroupId): $($GroupUsers.Count)"
$GroupUsers | ForEach-Object { Write-Host "  - $_" }

Write-Host "🏢 Users in Work Team ($WorkTeamId): $($WorkTeamUsers.Count)"
$WorkTeamUsers | ForEach-Object { Write-Host "  - $_" }

# Find users to add
$UsersToAdd = $GroupUsers | Where-Object { $_ -notin $WorkTeamUsers }
Write-Host "📌 Users to ADD: "
$UsersToAdd | ForEach-Object { Write-Host "  - $_" }

# Find users to remove
$UsersToRemove = $WorkTeamUsers | Where-Object { $_ -notin $GroupUsers }
Write-Host "❌ Users to REMOVE: "
$UsersToRemove | ForEach-Object { Write-Host "  - $_" }

# Add missing users to the work team
Add-UsersToWorkTeam -WorkTeamId $WorkTeamId -UsersToAdd $UsersToAdd

# Remove extra users from the work team
Remove-UsersFromWorkTeam -WorkTeamId $WorkTeamId -UsersToRemove $UsersToRemove

Write-Host "🔄 Sync completed."
