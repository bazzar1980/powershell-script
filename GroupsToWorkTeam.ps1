# Configuration
$ClientId = "<CLIENT_ID>"
$ClientSecret = "<CLIENT_SECRET>"
$Region = "mypurecloud.ie"  # Change based on your region
$GroupId = "<GROUP_ID>"
# $WorkTeamId = "eef6a722-d998-4d21-82a5-11fcd30a46eb"

# Define a mapping between Division IDs and Work Team IDs
$DivisionWorkTeams = @{
    # "division_1_id" = "workteam_1_id"
    # "division_2_id" = "workteam_2_id"
    # "division_3_id" = "workteam_3_id"
    # "division_N_id" = "workteam_N_id"
}

# Function: Authenticate with Genesys Cloud
Function Get-AuthToken {
    $authUrl = "https://login.$Region/oauth/token"
    $authHeaders = @{
        "Content-Type"  = "application/x-www-form-urlencoded"
    }

    $authBody = "grant_type=client_credentials&client_id=$ClientId&client_secret=$ClientSecret"

    try {
        $tokenResponse = Invoke-RestMethod -Uri $authUrl -Method Post -Headers $authHeaders -Body $authBody
        return $tokenResponse.access_token
    } catch {
        Write-Host "❌ Authentication failed: $_"
        exit
    }
}

# Get Auth Token
$AccessToken = Get-AuthToken

# Headers for API requests
$Headers = @{
    "Authorization" = "Bearer $AccessToken"
    "Content-Type"  = "application/json"
}

# Function: Get Users from a Genesys Cloud Group
Function Get-GroupUsers {
    param($GroupId)
    $groupUsersUrl = "https://api.$Region/api/v2/groups/$GroupId/members?pageSize=100"
    $allUsers = @()

    do {
        try {
            Write-Host "🔍 Fetching Group Users from: $groupUsersUrl"
            $response = Invoke-RestMethod -Uri $groupUsersUrl -Method Get -Headers $Headers
            $allUsers += $response.entities | Select-Object -ExpandProperty id
            $groupUsersUrl = if ($response.nextUri) { "https://api.$Region" + $response.nextUri } else { $null }
        } catch {
            Write-Host "❌ Error fetching group users: $_"
            exit
        }
    } while ($groupUsersUrl)

    return $allUsers
}

# Function: Get User Details (to retrieve Division ID)
Function Get-UserDivision {
    param($UserId)
    $userUrl = "https://api.$Region/api/v2/users/$UserId"

    try {
        Write-Host "🔍 Fetching Division for User: $UserId"
        $response = Invoke-RestMethod -Uri $userUrl -Method Get -Headers $Headers
        return $response.division.id
    } catch {
        Write-Host "❌ Error fetching user division: $_"
        return $null
    }
}

# Function: Get Users from a Work Team
Function Get-WorkTeamUsers {
    param($WorkTeamId)
    $workTeamUsersUrl = "https://apps.$Region/platform/api/v2/teams/$WorkTeamId/members"

    try {
        Write-Host "🔍 Fetching Work Team Users from: $workTeamUsersUrl"
        $response = Invoke-RestMethod -Uri $workTeamUsersUrl -Method Get -Headers $Headers

        if ($response.PSObject.Properties["entities"]) {
            return $response.entities | Select-Object -ExpandProperty id
        } else {
            Write-Host "⚠ No 'entities' field found in Work Team API response."
            return @()
        }
    } catch {
        Write-Host "❌ Error fetching work team users: $_"
        return @()
    }
}

# Function: Add Users to Work Team (with Division ID)
Function Add-UserToWorkTeam {
    param($UserId, $DivisionId)

    $WorkTeamId = $DivisionWorkTeams[$DivisionId]
    if (-not $WorkTeamId) {
        Write-Host "⚠ No Work Team found for Division: $DivisionId. Skipping."
        return
    }

    $WorkTeamVersion = 4

    $body = @{
        "memberIds" = @($UserId)
        "version"   = $WorkTeamVersion
    } | ConvertTo-Json -Depth 3

    $addUrl = "https://apps.$Region/platform/api/v2/teams/$WorkTeamId/members"

    try {
        Write-Host "🚀 Adding User $UserId to Work Team $WorkTeamId"
        Write-Host "🔍 JSON Payload: $body"
        $response = Invoke-RestMethod -Uri $addUrl -Method Post -Headers $Headers -Body $body
        Write-Host "✅ Successfully added User $UserId to Work Team $WorkTeamId"
    } catch {
        Write-Host "❌ Error adding User $UserId to Work Team: $_"
    }
}

# Function: Remove Users from Work Team
Function Remove-UserFromWorkTeam {
    param($UserId, $DivisionId)

    $WorkTeamId = $DivisionWorkTeams[$DivisionId]
    if (-not $WorkTeamId) {
        Write-Host "⚠ No Work Team found for Division: $DivisionId. Skipping removal."
        return
    }

    # Correct API format: Use query parameters only (no body needed)
    $removeUrl = "https://apps.$Region/platform/api/v2/teams/$WorkTeamId/members?id=$UserId"

    try {
        Write-Host "❌ Removing User $UserId from Work Team $WorkTeamId"
        Write-Host "🔍 API Call: $removeUrl"

        # Remove Content-Type to match expected API behavior
        $Headers.Remove("Content-Type")

        # Send DELETE request without a body
        $response = Invoke-RestMethod -Uri $removeUrl -Method Delete -Headers $Headers
        Write-Host "✅ Successfully removed User $UserId from Work Team $WorkTeamId"
    } catch {
        Write-Host "❌ Error removing User $UserId from Work Team: $_"
    }
}

# Fetch users from the Group
$GroupUsers = Get-GroupUsers -GroupId $GroupId

# Fetch users from all Work Teams
$AllWorkTeamUsers = @{}
foreach ($DivisionId in $DivisionWorkTeams.Keys) {
    $WorkTeamId = $DivisionWorkTeams[$DivisionId]
    $AllWorkTeamUsers[$DivisionId] = Get-WorkTeamUsers -WorkTeamId $WorkTeamId
}

# Process each user in the Group
foreach ($UserId in $GroupUsers) {
    $UserDivision = Get-UserDivision -UserId $UserId

    if ($UserDivision) {
        Add-UserToWorkTeam -UserId $UserId -DivisionId $UserDivision
    }
}

# Process each Work Team and remove users who are no longer in the group
foreach ($DivisionId in $DivisionWorkTeams.Keys) {
    $WorkTeamId = $DivisionWorkTeams[$DivisionId]
    $WorkTeamUsers = $AllWorkTeamUsers[$DivisionId]

    foreach ($UserId in $WorkTeamUsers) {
        if ($UserId -notin $GroupUsers) {
            Remove-UserFromWorkTeam -UserId $UserId -DivisionId $DivisionId
        }
    }
}

Write-Host "✅ Sync completed successfully."
