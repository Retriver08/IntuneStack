<#PSScriptInfo
.VERSION 1.0.0
.GUID a1b2c3d4-e5f6-7890-abcd-ef1234567890
.AUTHOR Hailey Phillips
.DESCRIPTION IntuneStack Policy Promotion Analysis - Part of IntuneStack deployment orchestration
.COMPANYNAME
.COPYRIGHT GPL
.TAGS intune endpoint MEM policy promotion intunestack
.LICENSEURI https://github.com/AllwaysHyPe/IntuneStack/blob/main/LICENSE
.PROJECTURI https://github.com/AllwaysHyPe/IntuneStack
.EXTERNALMODULEDEPENDENCIES microsoft.graph.authentication
.REQUIREDSCRIPTS
.EXTERNALSCRIPTDEPENDENCIES
.RELEASENOTES
Part of IntuneStack - Modern Intune Configuration Management with deployment rings and automated promotion.
Based on Intune management functions by Andrew Taylor (https://github.com/andrew-s-taylor/public).
#>

<#
.SYNOPSIS
This script is used to analyze and automate Intune policy promotion through deployment rings

.DESCRIPTION
The script connects to the Graph API Interface and analyzes policy deployment status, automating promotion through dev -> test -> prod stages

.PARAMETER PolicyId
Enter the policy ID (GUID) for the policy you want to analyze for promotion

.PARAMETER ComplianceThreshold
Enter the compliance threshold percentage required for promotion (default: 80)

.PARAMETER CurrentStage
Enter the current deployment stage (dev, test, prod) - defaults to GitHub branch name

.PARAMETER AutoPromote
Enable automatic promotion when compliance threshold is met

.PARAMETER OutputPath
Enter the output path for reports and logs (default: ./reports)

.EXAMPLE
# Basic promotion analysis
.\PolicyPromotion.ps1 -PolicyId "12345678-1234-1234-1234-123456789012"

.EXAMPLE
# Automated promotion with GitHub Actions integration
.\PolicyPromotion.ps1 -PolicyId "12345678-1234-1234-1234-123456789012" -ComplianceThreshold 85 -AutoPromote -CurrentStage "dev"

.EXAMPLE
# Development testing with custom output path
.\PolicyPromotion.ps1 -PolicyId "12345678-1234-1234-1234-123456789012" -CurrentStage "dev" -OutputPath "./output/reports"

.NOTES
NAME: PolicyPromotion.ps1
VERSION: 1.0.0
AUTHOR: Hailey Phillips
CREATION DATE: 06/04/25
PURPOSE: IntuneStack policy promotion automation

Core Intune management functions adapted from:
Author: Andrew Taylor
GitHub: https://github.com/andrew-s-taylor/public

IntuneStack builds upon foundation work by:
- OpenIntuneBaseline by James (SkipToTheEndpoint)
- Maester OIDC and testing patterns
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PolicyId,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$ComplianceThreshold = 80,

    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'test', 'prod')]
    [string]$CurrentStage = $env:GITHUB_REF_NAME,

    [Parameter(Mandatory = $false)]
    [switch]$AutoPromote,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "./reports",

    [Parameter(Mandatory = $false)]
    [ValidateSet('Minimal', 'Normal', 'Detailed')]
    [string]$OutputLevel = 'Normal'
)

$version = "1.0.0"

###############################################################################################################
######                                         Install Modules                                           ######
###############################################################################################################

# Install MS Graph if not available
if (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication) {
    Write-Verbose "Microsoft Graph already installed"
} else {
    Write-Host "Installing Microsoft Graph Authentication..." -ForegroundColor Cyan
    try {
        Install-Module -Name Microsoft.Graph.Authentication -Scope CurrentUser -Repository PSGallery -Force
        Write-Host "Microsoft Graph Authentication installed" -ForegroundColor Green
    } catch [Exception] {
        Write-Host "Failed to install module: $($_.message)" -ForegroundColor Red
        exit
    }
}

# Importing Modules
Import-Module Microsoft.Graph.Authentication

###############################################################################################################
######                                          Add Functions                                            ######
###############################################################################################################

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Verbose')]
        [string]$Level = 'Info',

        [Parameter(Mandatory = $false)]
        [switch]$Console
    )

    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Oshow on console if -Console switch is used
    if ($Console) {
        $Color = switch ($Level) {
            'Info' { 'White' }
            'Warning' { 'Yellow' }
            'Error' { 'Red' }
            'Success' { 'Green' }
            'Verbose' { 'Gray' }
        }
        Write-Host "$TimeStamp - $Message" -ForegroundColor $Color
    }

    # Always log to file for artifacts
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    $LogEntry = "$TimeStamp - [$Level] $Message"
    $LogEntry | Out-File -FilePath "$OutputPath/promotion.log" -Append -Encoding UTF8
}


####################################################

function Connect-ToGraph {
    <#
    .SYNOPSIS
    Authenticates to the Graph API via OIDC token or interactive authentication.
    .DESCRIPTION
    The Connect-ToGraph cmdlet authenticates to the Graph API using OIDC token from GitHub Actions
    or falls back to interactive authentication for local development.
    .PARAMETER Tenant
    Specifies the tenant (e.g. contoso.onmicrosoft.com) to which to authenticate.
    .PARAMETER AppId
    Specifies the Azure AD app ID (GUID) for the application that will be used to authenticate.
    .PARAMETER OidcToken
    Specifies the OIDC token for GitHub Actions authentication.
    .PARAMETER Scopes
    Specifies the user scopes for interactive authentication.
    .EXAMPLE
    Connect-ToGraph -TenantId $tenantID -AppId $app -OidcToken $token
    #>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $false)] [string]$TenantId,
        [Parameter(Mandatory = $false)] [string]$AppId,
        [Parameter(Mandatory = $false)] [string]$OidcToken,
        [Parameter(Mandatory = $false)] [string]$scopes
    )

    process {
        Import-Module Microsoft.Graph.Authentication

        # Check for OIDC authentication (GitHub Actions)
        if ($OidcToken -and $AppId -and $TenantId) {
            Write-Log "Authenticating with OIDC for GitHub Actions..."

            try {
                # Request Graph access token using OIDC
                $body = @{
                    client_id             = $AppId
                    client_assertion      = $OidcToken
                    client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
                    scope                 = "https://graph.microsoft.com/.default"
                    grant_type            = "client_credentials"
                }

                $tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
                $accessToken = $tokenResponse.access_token

                # Convert to SecureString as required by Connect-MgGraph
                $secureAccessToken = ConvertTo-SecureString $accessToken -AsPlainText -Force

                # Connect to Microsoft Graph using the secure access token
                Connect-MgGraph -AccessToken $secureAccessToken

                Write-Log "Connected to Microsoft Graph using OIDC authentication" -Level Success -Console
                return $true
            } catch {
                Write-Log "OIDC authentication failed: $($_.Exception.Message)" -Level Error -Console
                throw
            }
        }
        # Check for environment variables (set by GitHub Actions)
        elseif ($env:OIDC_TOKEN -and $env:AZURE_CLIENT_ID -and $env:AZURE_TENANT_ID) {
            Write-Log "Using OIDC authentication from environment variables" -Level Verbose
            return Connect-ToGraph -TenantId $env:AZURE_TENANT_ID -AppId $env:AZURE_CLIENT_ID -OidcToken $env:OIDC_TOKEN
        }
        # Fall back to interactive authentication
        else {
            Write-Log "Using interactive authentication" -Level Info -Console
            $version = (Get-Module microsoft.graph.authentication | Select-Object -ExpandProperty Version).major

            if ($version -ne 2) {
                Select-MgProfile -Name Beta
            }
            $graph = Connect-MgGraph -Scopes $scopes
            Write-Log "Connected to Intune tenant $($graph.TenantId)" -Level Success -Console
        }
    }
}

####################################################

function Get-EntraGroup() {
    <#
    .SYNOPSIS
    This function is used to get Entra ID groups from the Graph API REST interface

    .DESCRIPTION
    The function connects to the Graph API Interface and gets Entra ID groups by name or returns all groups

    .PARAMETER GroupName
    Optional filter by group display name (exact match)

    .PARAMETER SearchTerm
    Optional search term to find groups containing this text

    .PARAMETER GraphApiVersion
    Graph API version to use (default: beta)

    .EXAMPLE
    Get-EntraGroup -GroupName "Intune-Dev-Users"
    Returns the specific group with exact name match

    .EXAMPLE
    Get-EntraGroup -SearchTerm "Intune"
    Returns all groups containing "Intune" in their name

    .EXAMPLE
    Get-EntraGroup
    Returns all groups (use with caution in large tenants)

    .NOTES
    NAME: Get-EntraGroup
    #>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$GroupName,

        [Parameter(Mandatory = $false)]
        [string]$SearchTerm,

        [Parameter(Mandatory = $false)]
        [ValidateSet('beta', 'v1.0')]
        [string]$GraphApiVersion = "beta"
    )

    try {
        $uri = $null

        if ($GroupName) {
            # Exact match filter
            $uri = "https://graph.microsoft.com/$GraphApiVersion/groups?`$filter=displayName eq '$GroupName'"
        } elseif ($SearchTerm) {
            # Search for groups containing the term
            $uri = "https://graph.microsoft.com/$GraphApiVersion/groups?`$filter=startswith(displayName,'$SearchTerm')"
        } else {
            # Get all groups (use with caution)
            $uri = "https://graph.microsoft.com/$GraphApiVersion/groups"
        }

        $result = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject

        if ($GroupName) {
            # For exact match, return single result or null
            if ($result.value -and $result.value.Count -gt 0) {
                Write-Log "Found group: $GroupName (ID: $($result.value[0].id))" -Level Info
                return $result.value[0]
            } else {
                Write-Log "Group not found: $GroupName" -Level Warning -Console
                return $null
            }
        } else {
            Write-Log "Found $($result.value.Count) groups" -Level Info
            return $result.value
        }

    } catch {
        $ex = $_.Exception
        $responseBody = ""

        # Check if we have a response and response stream
        if ($ex.Response -and $ex.Response.GetResponseStream) {
            try {
                $errorResponse = $ex.Response.GetResponseStream()
                if ($errorResponse) {
                    $reader = New-Object System.IO.StreamReader($errorResponse)
                    $reader.BaseStream.Position = 0
                    $reader.DiscardBufferedData()
                    $responseBody = $reader.ReadToEnd()
                }
            } catch {
                $responseBody = "Unable to read error response stream"
            }
        }

        if ($responseBody) {
            Write-Host "Response content:`n$responseBody" -f Red
        }

        if ($ex.Response) {
            Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        } else {
            Write-Error "Request failed: $($ex.Message)"
        }


        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "Error getting group: $($ex.Message)" -Level Error
        }

        throw
    }
}

####################################################

function Get-DeviceConfigurationPolicy {
    <#
        .SYNOPSIS
        This function is used to dynamically get device configuration policy from the Graph API REST interface

        .DESCRIPTION
        The function connects to the Graph API Interface and dynamically gets any device configuration policies

        .PARAMETER Category
        Category of policy (AutopilotProfile, ApplicationProtection, ConditionalAccess, CompliancePolicies, DeviceConfiguration, SettingsCatalog, etc)

        .PARAMETER Name
        Optional filter by policy name

        .EXAMPLE
        Get-DeviceConfigurationPolicy -Category "DeviceConfiguration"
        Returns any device configuration policies configured in Intune

        .EXAMPLE
        Get-DeviceConfigurationPolicy -Category "DeviceConfigurationSC" -name "Security Baseline"
        Returns Settings Catalog policies with the specified name

        .NOTES
        NAME: Get-DeviceConfigurationPolicy
        Author: Hailey Phillips
        Version: 0.0.1
        Modified: 2025-07-23
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        $Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('AutopilotProfile', 'ApplicationProtection', 'ConditionalAccess', 'CompliancePolicies', 'DeviceConfiguration', 'DeviceConfigurationSC', '*')]
        [string]$Category

    )

    $graphApiVersion = "beta"

    # Dynamically setting Graph resource path based off of category
    $DCP_resource = switch ($Category) {
        'AutopilotProfile' { "deviceManagement/windowsAutopilotDeploymentProfiles" }
        'ApplicationProtection' { "deviceAppManagement/managedAppPolicies" }
        'CompliancePolicies' { "deviceManagement/deviceCompliancePolicies" }
        'ConditionalAccess' { "identity/conditionalAccess/policies" }
        'DeviceConfiguration' { "deviceManagement/deviceConfigurations" }
        'DeviceConfigurationSC' { "deviceManagement/configurationPolicies" }
        default { throw "Unknown category: $Category" }
    }

    $displayNameProperty = switch ($Category) {
        'DeviceConfigurationSC' { 'name' }
        default { 'displayName' }
    }

    try {
        if ($Name) {
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)?`$filter=$displayNameProperty eq '$name'"
            (Invoke-MgGraphRequest -Uri $uri -Method Get -OutputType PSObject).Value
        } else {
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)"
            (Invoke-MgGraphRequest -Uri $uri -Method Get -OutputType PSObject).Value
        }
    } catch {
        $ex = $_.Exception
        $errorResponse = $ex.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        Write-Host
        break
    }

} # end function Get-DeviceConfigurationPolicy


################################################

function Get-DeviceConfigurationPolicyAssignment() {
    <#
        .SYNOPSIS
        This function is used to dynamically get device configuration policy assignment from the Graph API REST interface

        .DESCRIPTION
        The function connects to the Graph API Interface and dynamically gets any device configuration policy assignment

        .PARAMETER id
        Enter id (guid) for the Device Configuration Policy you want to check assignment (optional - if not provided, gets all policies)

        .PARAMETER Category
        Category of policy (AutopilotProfile, ApplicationProtection, ConditionalAccess, CompliancePolicies, DeviceConfiguration, SettingsCatalog, etc)

        .PARAMETER Name
        Optional filter by policy name

        .EXAMPLE
        Get-DeviceConfigurationPolicyAssignment -Category "DeviceConfiguration"
        Returns all device configuration policies and their assignments

        .EXAMPLE
        Get-DeviceConfigurationPolicyAssignment -id "12345678-1234-1234-1234-123456789012" -Category "DeviceConfiguration"
        Returns assignments for a specific device configuration policy

        .NOTES
        NAME: Get-DeviceConfigurationPolicyAssignment
        Author: Hailey Phillips
        Version: 0.0.1
        Modified: 2025-07-23
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, HelpMessage = "Enter id (guid) for the Device Configuration Policy you want to check assignment")]
        $id,

        [Parameter(Mandatory = $true)]
        [ValidateSet('AutopilotProfile', 'ApplicationProtection', 'ConditionalAccess', 'CompliancePolicies', 'DeviceConfiguration', 'DeviceConfigurationSC', '*')]
        [string]$Category
    )

    $graphApiVersion = "beta"

    # Dynamically setting Graph resource path based off of category
    $DCP_resource = switch ($Category) {
        'AutopilotProfile' { "deviceManagement/windowsAutopilotDeploymentProfiles" }
        'ApplicationProtection' { "deviceAppManagement/managedAppPolicies" }
        'CompliancePolicies' { "deviceManagement/deviceCompliancePolicies" }
        'ConditionalAccess' { "identity/conditionalAccess/policies" }
        'DeviceConfiguration' { "deviceManagement/deviceConfigurations" }
        'DeviceConfigurationSC' { "deviceManagement/configurationPolicies" }
        default { throw "Unknown category: $Category" }
    }

    $assignmentEndpoint = "assignments"

    $displayNameProperty = switch ($Category) {
        'DeviceConfigurationSC' { 'name' }
        default { 'displayName' }
    }

    try {
        # If specific ID is provided, get assignments for that policy only
        if ($id) {

            $uri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)/$($id)/$assignmentEndpoint"
            $PolicyAssignments = (Invoke-MgGraphRequest -Uri $uri -Method Get -OutputType PSObject).Value
            $AssignedGroups = [ordered]@{}

            foreach ($Assignment in $PolicyAssignments) {

                # Handle different assignment structures based on category
                $GroupId = $Assignment.target.groupId

                if ($GroupId -and $AssignedGroups.Keys -notcontains $GroupId) {
                    $AssignmentType = switch ($Assignment.target.'@odata.type') {
                        '#microsoft.graph.exclusionGroupAssignmentTarget' { "Exclude" }
                        default { "Include" }
                    }

                    try {

                        $GroupDetails = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/groups/$($GroupId)" -OutputType PSObject
                        $AssignedGroups[$GroupId] = [PSCustomObject]@{
                            Id             = $GroupId
                            Name           = $GroupDetails.displayName
                            Description    = $GroupDetails.description
                            AssignmentType = $AssignmentType
                            Intent         = $Assignment.intent
                            Source         = $Assignment.source
                            SourceId       = $Assignment.sourceId
                            FilterId       = $Assignment.target.deviceAndAppManagementAssignmentFilterId
                            FilterType     = $Assignment.target.deviceAndAppManagementAssignmentFilterType
                        }
                        Write-Log "Policy is assigned to: $($GroupDetails.displayName)" -Level Verbose
                    } catch {
                        Write-Log "Unable to get details for group ID: $GroupId" -Level Warning
                    }
                }
            }
            return $AssignedGroups.Values
        }
        # If no ID provided, get all policies of this type and their assignments
        else {
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)"
            $AllPolicies = (Invoke-MgGraphRequest -Uri $uri -Method Get -OutputType PSObject).Value

            $PolicyResults = @()
            foreach ($Policy in $AllPolicies) {
                # Get assignments for each policy
                $assignmentUri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)/$($Policy.id)/$assignmentEndpoint"
                try {
                    $PolicyAssignments = (Invoke-MgGraphRequest -Uri $assignmentUri -Method Get -OutputType PSObject).Value
                    $AssignedGroups = [ordered]@{}

                    foreach ($Assignment in $PolicyAssignments) {

                        $GroupId = $Assignment.target.groupId

                        if ($GroupId -and $AssignedGroups.Keys -notcontains $GroupId) {
                            $AssignmentType = switch ($Assignment.target.'@odata.type') {
                                '#microsoft.graph.exclusionGroupAssignmentTarget' { "Exclude" }
                                default { "Include" }
                            }

                            try {
                                $GroupDetails = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/groups/$($GroupId)" -OutputType PSObject
                                $AssignedGroups[$GroupId] = [PSCustomObject]@{
                                    Id             = $GroupId
                                    Name           = $GroupDetails.displayName
                                    Description    = $GroupDetails.description
                                    AssignmentType = $AssignmentType
                                    Intent         = $Assignment.intent
                                    Source         = $Assignment.source
                                    SourceId       = $Assignment.sourceId
                                    FilterId       = $Assignment.target.deviceAndAppManagementAssignmentFilterId
                                    FilterType     = $Assignment.target.deviceAndAppManagementAssignmentFilterType
                                }
                                Write-Host "Policy is assigned to: $($GroupDetails.displayName)" -Level Info
                            } catch {
                                Write-Log "Unable to get details for group ID: $GroupId" -Level Warning
                            }
                        }
                    }

                    $PolicyResults += [PSCustomObject]@{
                        PolicyId          = $Policy.id
                        PolicyName        = $Policy.$displayNameProperty
                        PolicyDescription = $Policy.description
                        Category          = $Category
                        AssignedGroups    = $AssignedGroups.Values
                        AssignmentCount   = $AssignedGroups.Count
                    }
                } catch {
                    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                        Write-Log "Unable to get assignments for policy: $($Policy.$displayNameProperty)" -Level Warning
                    }
                }
            }
            return $PolicyResults
        }
    } catch {
        $ex = $_.Exception
        $responseBody = ""

        # Check if we have a response and response stream
        if ($ex.Response -and $ex.Response.GetResponseStream) {
            try {
                $errorResponse = $ex.Response.GetResponseStream()
                if ($errorResponse) {
                    $reader = New-Object System.IO.StreamReader($errorResponse)
                    $reader.BaseStream.Position = 0
                    $reader.DiscardBufferedData()
                    $responseBody = $reader.ReadToEnd()
                }
            } catch {
                $responseBody = "Unable to read error response stream"
            }
        }

        if ($responseBody) {
            Write-Host "Response content:`n$responseBody" -f Red
        }

        if ($ex.Response) {
            Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        } else {
            Write-Error "Request failed: $($ex.Message)"
        }
        Write-Host
        break
    }

} # end function Get-DeviceConfigurationPolicyAssignment


function Get-DeviceConfigurationPolicyStatus() {
    <#
    .SYNOPSIS
    This function is used to get device configuration policy status from the Graph API REST interface

    .DESCRIPTION
    The function connects to the Graph API Interface and gets device configuration policy status with summary counts

    .PARAMETER id
    Enter id (guid) for the Device Configuration Policy you want to check status

    .PARAMETER Category
    Category of policy (AutopilotProfile, ApplicationProtection, ConditionalAccess, CompliancePolicies, DeviceConfiguration, SettingsCatalog, etc)

    .EXAMPLE
    Get-DeviceConfigurationPolicyStatus -id "12345678-1234-1234-1234-123456789012" -Category "DeviceConfiguration"
    Returns device configuration policy status and summary statistics

    .NOTES
    NAME: Get-DeviceConfigurationPolicyStatus
    Author: Hailey Phillips
    Version: 0.0.1
    Modified: 2025-07-23
    #>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Enter id (guid) for the Device Configuration Policy you want to check status")]
        $id,

        [Parameter(Mandatory = $true)]
        [ValidateSet('AutopilotProfile', 'CompliancePolicies', 'DeviceConfiguration', 'DeviceConfigurationSC', 'ApplicationProtection', 'ConditionalAccess')]
        [string]$Category
    )

    $graphApiVersion = "Beta"

    $DCP_resource = switch ($Category) {
        'AutopilotProfile' { "deviceManagement/windowsAutopilotDeploymentProfiles" }
        'CompliancePolicies' { "deviceManagement/deviceCompliancePolicies" }
        'DeviceConfiguration' { "deviceManagement/deviceConfigurations" }
        'DeviceConfigurationSC' { "deviceManagement/configurationPolicies" }
        'ApplicationProtection' { "deviceAppManagement/managedAppPolicies" }
        'ConditionalAccess' { "identity/conditionalAccess/policies" }
        default { throw "Unknown category: $Category" }
    }

    # Handle different property names for display name
    $displayNameProperty = switch ($Category) {
        'DeviceConfigurationSC' { 'name' }
        default { 'displayName' }
    }

    try {
        # Get policy details for display name
        $policyUri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)/$id"
        $PolicyDetails = Invoke-MgGraphRequest -Uri $policyUri -Method GET -OutputType PSObject

        # Get device statuses
        $uri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)/$id/deviceStatuses"
        $DeviceStatuses = (Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject).value

        # Count statuses based on Intune values
        $StatusCounts = @{
            Total         = $DeviceStatuses.Count
            Succeeded     = ($DeviceStatuses | Where-Object status -EQ 'compliant').Count
            Error         = ($DeviceStatuses | Where-Object status -EQ 'error').Count
            Conflict      = ($DeviceStatuses | Where-Object status -EQ 'conflict').Count
            NotApplicable = ($DeviceStatuses | Where-Object status -EQ 'notApplicable').Count
            Pending       = ($DeviceStatuses | Where-Object { $_.status -in @('pending', 'unknown') }).Count
        }

        $SuccessRate = if ($StatusCounts.Total -gt 0) {
            [Math]::Round(($StatusCounts.Succeeded / $StatusCounts.Total) * 100, 2)
        } else { 0 }

        # Return summary object
        [PSCustomObject]@{
            PolicyId             = $id
            DisplayName          = $PolicyDetails.$displayNameProperty
            Category             = $Category
            TotalDevices         = $StatusCounts.Total
            SuccessfulDevices    = $StatusCounts.Succeeded
            ErrorDevices         = $StatusCounts.Error
            ConflictDevices      = $StatusCounts.Conflict
            NotApplicableDevices = $StatusCounts.NotApplicable
            PendingDevices       = $StatusCounts.Pending
            SuccessRate          = $SuccessRate
        }
    } catch {
        $ex = $_.Exception
        $errorResponse = $ex.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        Write-Host
        break
    }
}


####################################################

function Add-DeviceConfigurationPolicyAssignment() {
    <#
    .SYNOPSIS
    This function is used to add a device configuration policy assignment using the Graph API REST interface

    .DESCRIPTION
    The function connects to the Graph API Interface and adds a device configuration policy assignment

    .PARAMETER Category
    Category of policy (AutopilotProfile, ApplicationProtection, ConditionalAccess, CompliancePolicies, DeviceConfiguration, SettingsCatalog, etc)

    .PARAMETER ConfigurationPolicyId
    The policy ID to assign

    .PARAMETER TargetGroupId
    The group ID to assign the policy to

    .PARAMETER AssignmentType
    Whether to include or exclude the group

    .EXAMPLE
    Add-DeviceConfigurationPolicyAssignment -Category "DeviceConfiguration" -ConfigurationPolicyId $ConfigurationPolicyId -TargetGroupId $TargetGroupId -AssignmentType "Included"

    Adds a device configuration policy assignment in Intune

    .NOTES
    NAME: Add-DeviceConfigurationPolicyAssignment
    #>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('AutopilotProfile', 'CompliancePolicies', 'DeviceConfiguration', 'DeviceConfigurationSC', 'ApplicationProtection', 'ConditionalAccess')]
        [string]$Category,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $ConfigurationPolicyId,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $TargetGroupId,

        [parameter(Mandatory = $true)]
        [ValidateSet("Included", "Excluded")]
        [ValidateNotNullOrEmpty()]
        [string]$AssignmentType
    )

    $graphApiVersion = "Beta"

    $DCP_resource = switch ($Category) {
        'AutopilotProfile' { "deviceManagement/windowsAutopilotDeploymentProfiles" }
        'CompliancePolicies' { "deviceManagement/deviceCompliancePolicies" }
        'DeviceConfiguration' { "deviceManagement/deviceConfigurations" }
        'DeviceConfigurationSC' { "deviceManagement/configurationPolicies" }
        'ApplicationProtection' { "deviceAppManagement/managedAppPolicies" }
        'ConditionalAccess' { "identity/conditionalAccess/policies" }
        default { throw "Unknown category: $Category" }
    }

    $Resource = "$($DCP_resource)/$ConfigurationPolicyId/assign"

    try {
        if (!$ConfigurationPolicyId) {
            Write-Host "No Configuration Policy Id specified, specify a valid Configuration Policy Id" -f Red
            break
        }

        if (!$TargetGroupId) {
            Write-Host "No Target Group Id specified, specify a valid Target Group Id" -f Red
            break
        }

        # Checking if there are Assignments already configured in the Policy
        $DCPA = Get-DeviceConfigurationPolicyAssignment -Category $Category -id $ConfigurationPolicyId

        $TargetGroups = @()

        if (@($DCPA).count -ge 1) {
            if ($DCPA.Id -contains $TargetGroupId) {
                Write-Host "Group with Id '$TargetGroupId' already assigned to Policy..." -ForegroundColor Red
                break
            }

            # Looping through previously configured assignments
            $DCPA | ForEach-Object {
                $TargetGroup = New-Object -TypeName psobject

                if ($_.AssignmentType -eq "Exclude") {
                    $TargetGroup | Add-Member -MemberType NoteProperty -Name '@odata.type' -Value '#microsoft.graph.exclusionGroupAssignmentTarget'
                } else {
                    $TargetGroup | Add-Member -MemberType NoteProperty -Name '@odata.type' -Value '#microsoft.graph.groupAssignmentTarget'
                }

                $TargetGroup | Add-Member -MemberType NoteProperty -Name 'groupId' -Value $_.Id

                $Target = New-Object -TypeName psobject
                $Target | Add-Member -MemberType NoteProperty -Name 'target' -Value $TargetGroup

                $TargetGroups += $Target
            }

            # Adding new group to psobject
            $TargetGroup = New-Object -TypeName psobject

            if ($AssignmentType -eq "Excluded") {
                $TargetGroup | Add-Member -MemberType NoteProperty -Name '@odata.type' -Value '#microsoft.graph.exclusionGroupAssignmentTarget'
            } elseif ($AssignmentType -eq "Included") {
                $TargetGroup | Add-Member -MemberType NoteProperty -Name '@odata.type' -Value '#microsoft.graph.groupAssignmentTarget'
            }

            $TargetGroup | Add-Member -MemberType NoteProperty -Name 'groupId' -Value "$TargetGroupId"

            $Target = New-Object -TypeName psobject
            $Target | Add-Member -MemberType NoteProperty -Name 'target' -Value $TargetGroup

            $TargetGroups += $Target

        } else {
            # No assignments configured creating new JSON object of group assigned
            $TargetGroup = New-Object -TypeName psobject

            if ($AssignmentType -eq "Excluded") {
                $TargetGroup | Add-Member -MemberType NoteProperty -Name '@odata.type' -Value '#microsoft.graph.exclusionGroupAssignmentTarget'
            } elseif ($AssignmentType -eq "Included") {
                $TargetGroup | Add-Member -MemberType NoteProperty -Name '@odata.type' -Value '#microsoft.graph.groupAssignmentTarget'
            }

            $TargetGroup | Add-Member -MemberType NoteProperty -Name 'groupId' -Value "$TargetGroupId"

            $Target = New-Object -TypeName psobject
            $Target | Add-Member -MemberType NoteProperty -Name 'target' -Value $TargetGroup

            $TargetGroups = $Target
        }

        # Creating JSON object to pass to Graph
        $Output = New-Object -TypeName psobject
        $Output | Add-Member -MemberType NoteProperty -Name 'assignments' -Value @($TargetGroups)
        $JSON = $Output | ConvertTo-Json -Depth 3

        # POST to Graph Service
        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
        Invoke-MgGraphRequest -Uri $uri -Method POST -Body $JSON -ContentType "application/json"


    } catch {
        $ex = $_.Exception
        $responseBody = ""

        # Check if we have a response and response stream
        if ($ex.Response -and $ex.Response.GetResponseStream) {
            try {
                $errorResponse = $ex.Response.GetResponseStream()
                if ($errorResponse) {
                    $reader = New-Object System.IO.StreamReader($errorResponse)
                    $reader.BaseStream.Position = 0
                    $reader.DiscardBufferedData()
                    $responseBody = $reader.ReadToEnd()
                }
            } catch {
                $responseBody = "Unable to read error response stream"
            }
        }

        if ($responseBody) {
            Write-Host "Response content:`n$responseBody" -f Red
        }

        if ($ex.Response) {
            Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        } else {
            Write-Error "Request failed: $($ex.Message)"
        }
        Write-Host
        break
    }
}

####################################################


function Start-PolicyPromotionAnalysis() {
    <#
    .SYNOPSIS
    This function is used to analyze and automate Intune policy promotion through deployment rings

    .DESCRIPTION
    The function connects to the Graph API Interface and analyzes policy deployment status, automating promotion through dev -> test -> prod stages

    .PARAMETER PolicyId
    Enter the policy ID (GUID) for the policy you want to analyze for promotion

    .PARAMETER ComplianceThreshold
    Enter the compliance threshold percentage required for promotion

    .PARAMETER CurrentStage
    Enter the current deployment stage

    .PARAMETER AutoPromote
    Enable automatic promotion when compliance threshold is met

    .PARAMETER OutputPath
    Enter the output path for reports and logs

    .EXAMPLE
    Start-PolicyPromotionAnalysis -PolicyId "12345678-1234-1234-1234-123456789012"
    Analyzes policy promotion readiness for the specified policy

    .EXAMPLE
    Start-PolicyPromotionAnalysis -PolicyId "12345678-1234-1234-1234-123456789012" -ComplianceThreshold 85 -AutoPromote -CurrentStage "dev"
    Analyzes and automatically promotes policy if compliance threshold is met

    .NOTES
    NAME: Start-PolicyPromotionAnalysis
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Enter the policy ID (GUID) for the policy you want to analyze for promotion")]
        [string]$PolicyId,

        [Parameter(Mandatory = $false, HelpMessage = "Enter the compliance threshold percentage required for promotion")]
        [ValidateRange(1, 100)]
        [int]$ComplianceThreshold = 80,

        [Parameter(Mandatory = $false, HelpMessage = "Enter the current deployment stage")]
        [ValidateSet('dev', 'test', 'prod')]
        [string]$CurrentStage = $env:GITHUB_REF_NAME,

        [Parameter(Mandatory = $false, HelpMessage = "Enable automatic promotion when compliance threshold is met")]
        [switch]$AutoPromote,

        [Parameter(Mandatory = $false, HelpMessage = "Enter the output path for reports and logs")]
        [string]$OutputPath = "./reports"
    )

    $version = "1.0.0"

    # Deployment rings configuration - with fallback values
    $RingGroups = @{
        "dev"  = if ($env:INTUNESTACK_DEV_GROUP) { $env:INTUNESTACK_DEV_GROUP } else { "Intune-Dev-Users" }
        "test" = if ($env:INTUNESTACK_TEST_GROUP) { $env:INTUNESTACK_TEST_GROUP } else { "Intune-Test-Users" }
        "prod" = if ($env:INTUNESTACK_PROD_GROUP) { $env:INTUNESTACK_PROD_GROUP } else { "Intune-Prod-Users" }
    }

    # Create output directory
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    try {
        ###############################################################################################################
        ######                                          Execute Analysis                                         ######
        ###############################################################################################################

        Write-Host "🔥 IntuneStack Policy Promotion Analysis v$version" -ForegroundColor Cyan
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

        # Connect to Graph
        Write-Host "`n🔐 Connecting to Microsoft Graph..." -ForegroundColor Yellow
        if ($env:OIDC_TOKEN) {
            Connect-ToGraph -Tenant $env:AZURE_TENANT_ID -AppId $env:AZURE_CLIENT_ID -OidcToken $env:OIDC_TOKEN
        } else {
            Connect-ToGraph
        }

        # Display parameters
        Write-Host "`n📋 Configuration" -ForegroundColor Cyan
        Write-Host "   Policy ID:         $PolicyId" -ForegroundColor White
        Write-Host "   Current Stage:     $CurrentStage" -ForegroundColor White
        Write-Host "   Threshold:         $ComplianceThreshold%" -ForegroundColor White
        Write-Host "   Auto Promote:      $(if($AutoPromote){'✅ Enabled'}else{'❌ Disabled'})" -ForegroundColor White

        Write-Log "Policy ID: $PolicyId, Stage: $CurrentStage, Threshold: $ComplianceThreshold%" -Level Info

        # Determine policy type
        Write-Host "`n🔍 Detecting policy type..." -ForegroundColor Cyan
        Write-Log "Checking traditional device configuration..." -Level Verbose

        $PolicyType = $null
        $PolicyDetails = $null

        # Check traditional device configuration first
        $TestTraditional = Get-DeviceConfigurationPolicy -Category "DeviceConfiguration" | Where-Object { $_.id -eq $PolicyId }
        if ($TestTraditional) {
            $PolicyType = "DeviceConfiguration"
            $PolicyDetails = $TestTraditional
            Write-Log "Detected traditional device configuration policy" -Level Verbose
        }

        # Check Settings Catalog if not found
        if (-not $PolicyType) {
            $TestSettingsCatalog = Get-DeviceConfigurationPolicy -Category "DeviceConfigurationSC" | Where-Object { $_.id -eq $PolicyId }
            if ($TestSettingsCatalog) {
                $PolicyType = "DeviceConfigurationSC"
                $PolicyDetails = $TestSettingsCatalog
                Write-Log "Detected Settings Catalog policy" -Level Info
            }
        }

        # Check compliance policies if not found
        if (-not $PolicyType) {
            $TestCompliance = Get-DeviceConfigurationPolicy -Category "CompliancePolicies" | Where-Object { $_.id -eq $PolicyId }
            if ($TestCompliance) {
                $PolicyType = "CompliancePolicies"
                $PolicyDetails = $TestCompliance
                Write-Log "Detected compliance policy" -Level Info
            }
        }

        # Check Autopilot profiles if not found
        if (-not $PolicyType) {
            $TestAutopilot = Get-DeviceConfigurationPolicy -Category "AutopilotProfile" | Where-Object { $_.id -eq $PolicyId }
            if ($TestAutopilot) {
                $PolicyType = "AutopilotProfile"
                $PolicyDetails = $TestAutopilot
                Write-Log "Detected Autopilot profile" -Level Info
            }
        }

        if (-not $PolicyType) {
            Write-Host "   ❌ Policy not found with ID: $PolicyId" -ForegroundColor Red
            Write-Log "Policy not found with ID: $PolicyId" -Level Error
            return $false
        }

        # Show only the result
        $displayName = if ($PolicyDetails.displayName) { $PolicyDetails.displayName } else { $PolicyDetails.name }
        Write-Host "   ✓ $displayName" -ForegroundColor Green
        Write-Host "     Type: $PolicyType" -ForegroundColor Gray
        Write-Log "Policy found: $displayName ($PolicyType)" -Level Info


        # Get assignments - show summary only
        Write-Host "`n📋 Getting current policy assignments..." -ForegroundColor Cyan
        Write-Log "Retrieving policy assignments..." -Level Verbose
        $AssignedGroups = Get-DeviceConfigurationPolicyAssignment -Category $PolicyType -id $PolicyId

        if ($AssignedGroups.Count -gt 0) {
            Write-Host "✅ Found $($AssignedGroups.Count) group assignment(s)" -ForegroundColor Green
            foreach ($group in $AssignedGroups) {
                Write-Host "   ✓ $($group.Name)" -ForegroundColor Green
            }
        } else {
            Write-Host "   (none)" -ForegroundColor gray

        }


        # Get policy deployment status
        Write-Host "`n📊 Analyzing policy deployment status..." -ForegroundColor Yellow
        Write-Log "Retrieving policy deployment status..." -Level Verbose
        $PolicyStatus = Get-DeviceConfigurationPolicyStatus -Category $PolicyType -id $PolicyId

        if (-not $PolicyStatus) {
            Write-Host "   ❌ Unable to retrieve policy status" -ForegroundColor Red
            Write-Log "Unable to retrieve policy status" -Level Error
            return $false
        }

        Write-Log "Policy status retrieved: $($PolicyStatus.TotalDevices) total devices, $($PolicyStatus.SuccessRate)% success rate"

        Write-Host "📋 Current Policy Status:" -ForegroundColor Cyan
        Write-Host "   Policy Name: $($PolicyStatus.DisplayName)" -ForegroundColor White
        Write-Host "   Success Rate: $($PolicyStatus.SuccessRate)%" -ForegroundColor $(if ($PolicyStatus.SuccessRate -ge $ComplianceThreshold) { 'Green' } else { 'Yellow' })

        # Determine next stage based on current deployment status
        $CurrentStageGroup = $RingGroups[$CurrentStage]
        $AssignedToCurrentStage = $AssignedGroups | Where-Object { $_.Name -eq $CurrentStageGroup }

        if ($AssignedToCurrentStage) {
            # Policy is already deployed to current stage, determine next stage for promotion
            $NextStage = switch ($CurrentStage) {
                "dev" { "test" }
                "test" { "prod" }
                "prod" { "completed" }
                default { "unknown" }
            }
            $ActionType = "promote"
        } else {
            # Policy is NOT deployed to current stage, deploy to current stage first
            $NextStage = $CurrentStage
            $ActionType = "deploy"
        }
        # Next stage readiness
        $ReadyForPromotion = $PolicyStatus.SuccessRate -ge $ComplianceThreshold -and $PolicyStatus.TotalDevices -gt 0

        # Initialize promotion tracking variables
        $PromotionExecuted = $false
        $PromotionTargetStage = $null
        $PromotionTargetGroup = $null
        $PromotionTargetGroupId = $null
        $PromotionTimestamp = $null
        $PromotionGuidance = $null
        $PromotionCommand = $null

        Write-Host "`n🎯 Promotion Analysis:" -ForegroundColor Cyan
        Write-Host "   Ready for Promotion: $(if($ReadyForPromotion){'✅ YES'}else{'❌ NO'})" -ForegroundColor $(if ($ReadyForPromotion) { 'Green' }else { 'Yellow' })
        Write-Host "   Current Stage Assignment: $(if($AssignedToCurrentStage){'✅ YES'}else{'❌ NO'})" -ForegroundColor $(if ($AssignedToCurrentStage) { 'Green' }else { 'Yellow' })
        Write-Host "   Action: $(if($ActionType -eq 'deploy'){"Deploy to $NextStage"}else{"Promote to $NextStage"})" -ForegroundColor White
        Write-Host "   Target Stage: $NextStage" -ForegroundColor White

        if ($ReadyForPromotion -and $NextStage -ne "completed") {
            $NextStageGroup = $RingGroups[$NextStage]
            Write-Host "   Target Group: $NextStageGroup" -ForegroundColor White
            Write-Log "Policy ready for $NextStage stage" -Level Success
            Write-Log "Target Group: $NextStageGroup"

            if ($AutoPromote) {
                Write-Host "`n🚀 Auto-deployment enabled - deploying to $NextStage..." -ForegroundColor Green
                Write-Log "Starting auto-deployment to $NextStage stage"

                # Get the target group
                $TargetGroup = Get-EntraGroup -GroupName $NextStageGroup

                if (-not $TargetGroup) {
                    Write-Host "   ✗ Target group '$NextStageGroup' not found" -ForegroundColor Red
                    Write-Log "Target group '$NextStageGroup' not found - operation failed" -Level Error
                    return $false
                }

                # Show current assignments before operation
                Write-Host "🔍 Current assignments before deployment:" -ForegroundColor Cyan
                if ($AssignedGroups.Count -gt 0) {
                    foreach ($group in $AssignedGroups) {
                        Write-Host "   - $($group.Name) ($($group.Id))" -ForegroundColor Gray
                    }
                } else {
                    Write-Host "   - No existing assignments" -ForegroundColor Gray
                }

                Write-Log "Assigning policy to $NextStageGroup (ID: $($TargetGroup.id))" -Level Verbose
                Add-DeviceConfigurationPolicyAssignment -Category $PolicyType -ConfigurationPolicyId $PolicyId -TargetGroupId $TargetGroup.id -AssignmentType "Included"

                Write-Host "`n✅ Policy successfully deployed to $NextStage stage" -ForegroundColor Green
                Write-Log "Policy $PolicyId successfully deployed to $NextStage stage (Group: $NextStageGroup)" -Level Success

                # Verify the assignment was successful
                Write-Host "🔍 Verifying updated assignments..." -ForegroundColor Cyan
                Write-Log "Verifying assignment..." -Level Verbose
                $UpdatedAssignments = Get-DeviceConfigurationPolicyAssignment -Category $PolicyType -id $PolicyId

                Write-Host "✅ Policy now assigned to $($UpdatedAssignments.Count) group(s):" -ForegroundColor Green
                foreach ($group in $UpdatedAssignments) {
                    Write-Host "   - $($group.Name) ($($group.Id))" -ForegroundColor White
                }

                # Update promotion tracking variables
                $PromotionExecuted = $true
                $PromotionTargetStage = $NextStage
                $PromotionTargetGroup = $NextStageGroup
                $PromotionTargetGroupId = $TargetGroup.id
                $PromotionTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"

            } else {
                Write-Host "`n⏸  Auto-promotion disabled" -ForegroundColor Yellow
                Write-Host "   Run with -AutoPromote to execute" -ForegroundColor Gray
                Write-Log "Ready for promotion but auto-promotion disabled"

                # Set promotion guidance for manual execution
                if ($ActionType -eq "deploy") {
                    $PromotionGuidance = "Policy is ready for deployment to $NextStage stage. Run with -AutoPromote to execute deployment."
                } else {
                    $PromotionGuidance = "Policy is ready for promotion to $NextStage stage. Run with -AutoPromote to execute promotion."
                }
                $PromotionCommand = "Start-PolicyPromotionAnalysis -PolicyId '$PolicyId' -CurrentStage '$CurrentStage' -AutoPromote"
            }
        } elseif ($NextStage -eq "completed") {
            Write-Host "`n✅ All stages complete" -ForegroundColor Green
            Write-Log "Policy deployment complete across all stages" -Level Success
            $PromotionGuidance = "Policy has been deployed to all stages (dev → test → prod). No further promotion needed."
        } else {
            Write-Host "`n⏳ Not ready (need $ComplianceThreshold%, have $($PolicyStatus.SuccessRate)%)" -ForegroundColor Yellow
            Write-Log "Policy does not meet promotion criteria" -Level Warning
            $PromotionGuidance = "Policy needs to achieve $ComplianceThreshold% success rate before promotion. Current: $($PolicyStatus.SuccessRate)%"
        }


        if ($PromotionExecuted) {
            Write-Host "`n🎉 Policy promotion analysis completed successfully!" -ForegroundColor Green
        }

        Write-Log "Policy promotion analysis completed" -Level Success

        # Create comprehensive report object
        $Report = [PSCustomObject]@{
            Timestamp              = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
            PolicyId               = $PolicyId
            PolicyType             = $PolicyType
            PolicyName             = $PolicyStatus.DisplayName
            CurrentStage           = $CurrentStage
            NextStage              = $NextStage
            ReadyForPromotion      = $ReadyForPromotion
            AssignedGroups         = $AssignedGroups
            Metrics                = $PolicyStatus
            ComplianceThreshold    = $ComplianceThreshold
            AutoPromoteEnabled     = $AutoPromote.IsPresent
            RingGroups             = $RingGroups
            PromotionExecuted      = $PromotionExecuted
            PromotionTargetStage   = $PromotionTargetStage
            PromotionTargetGroup   = $PromotionTargetGroup
            PromotionTargetGroupId = $PromotionTargetGroupId
            PromotionTimestamp     = $PromotionTimestamp
            PromotionGuidance      = $PromotionGuidance
            PromotionCommand       = $PromotionCommand
        }

        # Save reports
        Write-Log "Saving promotion report..." -Level Verbose
        $ReportJson = $Report | ConvertTo-Json -Depth 10
        $ReportJson | Out-File -FilePath "$OutputPath/promotion-report.json" -Encoding UTF8

        return $ReadyForPromotion

    } catch {
        $ex = $_.Exception
        Write-Host "`n✗ Error during policy promotion analysis: $($ex.Message)" -ForegroundColor Red
        Write-Log "Error during policy promotion analysis: $($ex.Message)" -Level Error
        throw
    }
}


###############################################################################################################
######                                          Script Execution                                         ######
###############################################################################################################

# Script execution
if ($MyInvocation.InvocationName -ne '.') {
    $result = Start-PolicyPromotionAnalysis -PolicyId $PolicyId -ComplianceThreshold $ComplianceThreshold -CurrentStage $CurrentStage -AutoPromote:$AutoPromote -OutputPath $OutputPath

    if ($result) {
        exit 0
    } else {
        exit 1
    }
}
