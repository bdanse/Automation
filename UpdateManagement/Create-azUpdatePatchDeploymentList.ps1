<#PSScriptInfo

.VERSION 1.0

.GUID 848f7086-8a09-4f63-a7a9-f0c9b2d612b9

.AUTHOR jbritt@microsoft.com

.COMPANYNAME Microsoft

.COPYRIGHT Microsoft

.TAGS 

.LICENSEURI 

.PROJECTURI 
https://aka.ms/JimBritt

.ICONURI 

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES
Mar 20, 2020 1.0
    Initial
#>

<#  
.SYNOPSIS  
  A script to programatically create an Azure Update Management Patch list object based on a pre-prod environment
  Pre-Prod --> PROD scenario
  
  Note  This script currently leverages the Az cmdlets
  
.DESCRIPTION  
  This script meant to help you automate the creating of a producation Azure Update Management Deployment Schedule
  based on KBIDs needed in a pre-prod environment.  You take a source subscription / Azure Automation Account / Linked Log Analytics
  Workspace and query for existing needed updates according to your classification requirements as well as 
  the target operating system (Windows or Linux).  The Prouction configuration contains only the KBIDs of the source
  pre-prod environment that are required for the monthly patching.

.PARAMETER SourceSubscriptionId
    The subscriptionID of the Azure Subscription where your reference Azure Update Configuration is located

.PARAMETER TargetSubscriptionId
    The subscriptionID of the Azure Subscription where your target Azure Update Configuration is to be created

.PARAMETER AAAcountName
    The Azure Automation Account Name to be referenced in the source subscription that supports Azure Update Management

.PARAMETER AAResourceGroupName
    The Azure Automation ResourceGroupName in the source subscription that supports Azure Update Management

.PARAMETER WSID
    The log Analytics Workspace ID (CustomerID) in the Source Subscription used to gather your needed KBIDs

.PARAMETER queryScope
    Array of scopes to include in the scope for the query based update management object option
    Ex:  -queryScope  "/subscriptions/22e2445a-0984-4fa5-86a4-0280d76c4b2c/resourceGroups/resourceGroupName,/subscriptions/32e2445a-0984-4fa5-86a4-0280d76c4b2d/"
    Note: Defaults to target subscription if no value is provided on parameter

.PARAMETER queryLocation
    What region(s) include in the scope for the query based update management object option
    Ex: "eastasia","southeastasia","centralus","eastus","eastus2","westus","northcentralus"

.PARAMETER tags
    Tags levered for query based on tags in target subscription to deploy the patches to
    Ex: @{PatchWindow = "SaturdayMorning";ENVIRONMENT = "PROD"}

.PARAMETER RebootOptions
    Parameter leveraged to determine reboot behavior for the updates (validated parameter set)

.PARAMETER ApplicablePatchesQuery
    Log Analytics Search Query to scope reference set of machines to build a KBLIST from
    Note: Needs to be in one line instead of multiple!
    Example: 'Update | where OSType=="Linux" and Optional==false | where  Classification has "Unclassified" or Classification has "Critical" or Classification has "Security" or Classification has "Other" | summarize arg_max(TimeGenerated, *) by Computer,SourceComputerId,UpdateID, ApprovalSource, KBID | summarize hint.strategy=partitioned arg_max(TimeGenerated, *) by KBID| where UpdateState=~"Needed" and Approved!=false| project KBID, Title'

.PARAMETER KBLIST
    The list of approved (certified) KBIDs that you want to include in your target Azure Update Configuration Object
    Ex: "KB12345, KB21234"

.PARAMETER SavedSearchID
    A saved search ID from Log Analytics that you can use to run a saved query (pulls the query details from the SavedSearchID)
    Example Script to leverage for aquiring the saved Search IDs: https://www.powershellgallery.com/packages/Invoke-AzOperationalInsightsQueryExport 

.PARAMETER DaysOfWeek
    What days of the week you want to execute the patch on. Defaults to every day
    Ex: "Monday,"Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"

.PARAMETER SoftwareUpdateSchedName
    Name of the Software Update Schedule in target subscription you will create

.PARAMETER SoftwareUpdateScheduleDescr
    Description for the Software Update Schedule in target subscription

.PARAMETER PreScript
    Prescript to run during the patch run (leveraged for the target Azure Update Configuration object)

.PARAMETER PreScriptParams
    PreScript parameters to run during the patch run (leveraged for the target Azure Update Configuration object)
    Needs to be in the form of a hashtable
    Ex: @{Drive = "C";LOG = "Results.txt"}

.PARAMETER PostScript
    Postscript to run during the patch run (leveraged for the target Azure Update Configuration object)

.PARAMETER PostScriptParams
    PostScript parameters to run during the patch run (leveraged for the target Azure Update Configuration object)
    Needs to be in the form of a hashtable
    Ex: @{Drive = "C";LOG = "Results.txt"}

.PARAMETER ClassificationList
    List of Classifications of updates to include
    Ex: "Critical,Security,UpdateRollup"

.PARAMETER duration
    The number of minutes you want the update to run related to timespan (Default is 120 mins)

.PARAMETER TargetOS
    Determines which OS is update configuration is meant for in the Target subscription.(Windows or Linux)

.PARAMETER StartTime
    When should the Azure Update Management Schedule be intially created to start 
    (needs to be at least 5 mins later than current run time of script)

.PARAMETER ExpiryTime
    When should the schedule expire for the Azure Update Management configuration

.PARAMETER Force
    When provided, this will allow the script to run silently without prompting 
    All Parameters need to have proper values to succeed

.EXAMPLE
.\Create-azUpdatePatchDeploymentList.ps1 -SoftwareUpdateScheduleName "Windows Update" `
    -TargetOS Linux `
    -StartTime '03/15/2020' `
    -AAAcountName AzureAutoEast `
    -AAResourceGroupName OI-Default-East-US `
    -WSID b571a98c-6828-4045-bb5f-857543f2a9e3 `
    -queryFilterOperator any `
    -DaysOfWeek "Sunday","Monday" `
    -duration (New-TimeSpan -Hours 4) `
    -WeekInterval 3 
  Will use resource group and workspace name as your target workspace within specified subscription and will prompt for other details.
  
.EXAMPLE
.\Create-AzUpdatePatchDeploymentList.ps1 -SoftwareUpdateScheduleName "Windows Update" `
    -TargetOS Windows `
    -StartTime '4/15/2020' `
    -AAAcountName AzureAutoEast `
    -AAResourceGroupName OI-Default-East-US `
    -WSID b571a98c-6828-4045-bb5f-857543f2a9e3 `
    -queryFilterOperator all `
    -DaysOfWeek "Sunday","Monday" `
    -duration (New-TimeSpan -Hours 4) `
    -WeekInterval 3 `
    -SourceSubscriptionID c627c0bd-814f-4671-9bda-c8476ccb6abc `
    -TargetSubscriptionID c627c0bd-814f-4671-9bda-c8476ccb6abc `
    -ExpiryTime 5/1/2020 `
    -KBLIST "KB12345","KB34567" `
    -queryLocation "eastasia","southeastasia","centralus","eastus","eastus2","westus" `
    -ClassificationList "Unclassified" `
    -force
  This example has all needed details to run silently (including force switch).  Some details are assumed such as scope for the deployment coverage
  This example also shows an expiration date (default is no expiration)

.EXAMPLE
.\Create-AzUpdatePatchDeploymentList.ps1 -SoftwareUpdateScheduleName "Windows Update" `
    -TargetOS Windows `
    -StartTime '4/15/2020' `
    -AAAcountName AzureAutoEast `
    -AAResourceGroupName OI-Default-East-US `
    -WSID b571a98c-6828-4045-bb5f-857543f2a9e3 `
    -queryFilterOperator all `
    -DaysOfWeek "Sunday","Monday" `
    -duration (New-TimeSpan -Hours 4) `
    -WeekInterval 3 `
    -SourceSubscriptionID c627c0bd-814f-4671-9bda-c8476ccb6abc `
    -TargetSubscriptionID c627c0bd-814f-4671-9bda-c8476ccb6abc `
    -ExpiryTime 5/1/2020 `
    -KBLIST "KB12345","KB34567" `
    -queryLocation "eastasia","southeastasia","centralus","eastus","eastus2","westus" `
    -ClassificationList "Unclassified" `
    -PreScript "UpdateManagement-TurnOnVMs" `
    -PostScript "UpdateManagement-TurnOffVMs" `
    -force
  This example provides the additional option of a pre and post script from Azure Automation.
  This example assumes these runbooks have already been downloaded from the Script Center and installed in yoru Azure Automation Account
  See: https://gallery.technet.microsoft.com/scriptcenter/Update-Management-Turn-On-ffadfc26 and
  https://docs.microsoft.com/en-us/azure/automation/pre-post-scripts for more information.


.NOTES
   AUTHOR: Jim Britt Senior Program Manager - Azure CXP API
   LASTEDIT: March 20, 2020
   Initial

.LINK
    This script posted to and discussed at the following locations:PowerShell Gallery    	
    https://aka.ms/ExportAzLALogs
#>

#[cmdletbinding(
#    DefaultParameterSetName='Default'
#)]
param
(
    # SubscriptionId of where your SOURCELog Analytics Workspace is to get saved SearchID or leveraging query param (optional)
    [guid]$SourceSubscriptionID,

    [guid]$TargetSubscriptionID,

    # Resource Group name for Azure Automation Account
    [string]$AAResourceGroupName,

    [string]$AAAcountName,

    # List of Classifications of updates to include
    # Example values
    # -Classifications "Critical,Security,UpdateRollup"
    [array]$ClassificationList,

    # List of approved KBs (if not collected from reference workspace)
    ## NEED TO ADD LOGIC FOR THIS if provided
    # Example values
    # -KBLIST "KB12345, KB21234"
    [array]$KBLIST,

    # Array of scopes to include in the scope for the update management object
    # Example values
    # -queryScope  "/subscriptions/22e2445a-0984-4fa5-86a4-0280d76c4b2c/resourceGroups/resourceGroupName,/subscriptions/32e2445a-0984-4fa5-86a4-0280d76c4b2d/"
    [array]$queryScope,

    # Regions to narrow in the scope for resources to update
    # example values
    # -querylocation "EastUS", "WestUS""
    [array]$queryLocation,

    # Used for the Azure Query Logic to determine if all or any of the filters will evaluate as true if met
    [Parameter()]
    [ValidateSet('Any','All')]
    [string[]]
    $queryFilterOperator= 'All',

    # How you want to reboot.  note: reboot only conincides with undefined in Linux classification option.
    [Parameter()]
    [ValidateSet('IfRequired','Never', 'Always', 'RebootOnly')]
    [string[]]
    $RebootOptions = 'IfRequired',

    # Hashtable for tag based query
    # Needs to be in the format of 
    # example: -tags @{PatchWindow = "SaturdayMorning";ADMIN = "JIM"}
    [hashtable]$tags = @{PatchWindow = "SaturdayMorning";ADMIN = "JIM"},

#    Workspace ID (optional)
    # This is the actual Workspace ID (client ID) of the Log Analytics workspace
    # If ommitted, you will be promted to select a workspace in the source subscription
    [string]$WSID,
    
    # Log Analytics SavedSearchID (use ad hoc query if preferred)
    # Example Script to leverage for aquiring the saved Search IDs: https://www.powershellgallery.com/packages/Invoke-AzOperationalInsightsQueryExport 
    [string]$SavedSearchID,
    
    # Ad hoc query in lieu of SavedSearchID
    [string]$ApplicablePatchesQuery,

    # Defaults to 5 days from now but can be overridden from cmdline
    [Parameter(Mandatory=$false)]
    [System.DateTimeOffset]$StartTime= ((Get-Date) + (5d)),

    # When do you want to patch according to set schedule
    # Array set of days for example
    # -DaysOfWeek "Sunday,Monday,Tuesday,Wednesday,Thursday,Friday,Saturday"
    [array]$DaysOfWeek=('Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'),

    # Defaults to every week for interval - can override from cmdline
    [string]$WeekInterval = 1,

    # How long will the script run 
    # Defaults to 2 hours
    [System.TimeSpan]$duration = (New-TimeSpan -Hours 2),

    # Software Update Schedule Name default - use parameter to define
    [string]$SoftwareUpdateScheduleName = "SoftwareUpdateSchedule",

    # Description of Software Update schedule - defaults to "Software Update".  Use parameter to override
    [string]$SoftwareUpdateScheduleDescr = "Software Update",

    # Which OS to target - Windows is default
    [Parameter()]
    [ValidateSet('Windows', 'Linux')]
    [string[]]
    $TargetOS = 'Windows',

    # Pre and Post Scripts for Azure Update Management Configuration
    # Example -PreScript "UpdateManagement-TurnOnVMs"
    [string]$PreScript,

    # Hashtable for prescript parameters
    # Needs to be in the format of 
    # example: -PreScriptParams @{Drive = "C";LOG = "Results.txt"}
    [hashtable]$PreScriptParams,

    # Example -PostScript "UpdateManagement-TurnOffVMs"
    [string]$PostScript,

    # Hashtable for prescript parameters
    # Needs to be in the format of 
    # example: -PostScriptParams @{Drive = "C";LOG = "Results.txt"}
    [hashtable]$PostScriptParams,

    # Expiration of the Azure Update Management Schedule
    [Parameter(Mandatory=$false)]
    [System.DateTimeOffset]$ExpiryTime,

    [switch]$force = $false
)
function Add-IndexNumberToArray (
    [Parameter(Mandatory=$True)]
    [array]$array
    )
{
    for($i=0; $i -lt $array.Count; $i++) 
    { 
        Add-Member -InputObject $array[$i] -Name "#" -Value ($i+1) -MemberType NoteProperty 
    }
    $array
}
If($force)
{
    Write-HOST "Force switch is $Force.  Running silently if all parameters are provided" -ForegroundColor Magenta
}
write-host "We are working with the $TargetOS operating system" -ForegroundColor Yellow
#Target OS Variable init 
# NotOS is used in LA query to indicate what OS to leave out of results for patch query
$OSQueryString = $Null

if($TargetOS -eq 'Windows')
{
    $OSQueryString = "!=""Linux"""
}
if($TargetOS -eq 'Linux')
{
    $OSQueryString = "==""Linux"""
}

# Login to Azure - if already logged in, use existing credentials.
Write-Host "Authenticating to Azure..." -ForegroundColor Cyan
try
{
    $AzureLogin = Get-AzSubscription
}
catch
{
    $null = Login-AzAccount
    $AzureLogin = Get-AzSubscription
}

# Select Source Azure Subscription for Log Analytics AUM query
If($AzureLogin -and !($SourceSubscriptionID))
{
    [array]$SubscriptionArray = Add-IndexNumberToArray (Get-AzSubscription) 
    [int]$SelectedSub = 0

    # use the current subscription if there is only one subscription available
    if ($SubscriptionArray.Count -eq 1) 
    {
        $SelectedSub = 1
    }
    # Get SubscriptionID if one isn't provided
    while($SelectedSub -gt $SubscriptionArray.Count -or $SelectedSub -lt 1)
    {
        Write-host "Please select a SOURCE subscription from the list below for the refrence Update Management Details" -NoNewline
        $SubscriptionArray | Select-Object "#", Name, ID | Format-Table
        try
        {
            $SelectedSub = Read-Host "Please enter a selection from 1 to $($SubscriptionArray.count) for the SOURCE subscription for Query of Updates"
        }
        catch
        {
            Write-Warning -Message 'Invalid option, please try again.'
        }
    }
    if($($SubscriptionArray[$SelectedSub - 1].Name))
    {$SubscriptionName = $($SubscriptionArray[$SelectedSub - 1].Name)
    }
    elseif($($SubscriptionArray[$SelectedSub - 1].SubscriptionName))
    {
        $SubscriptionName = $($SubscriptionArray[$SelectedSub - 1].SubscriptionName)
    }
    write-verbose "You Selected Azure Subscription: $SubscriptionName as your SOURCE subscription"
    
    if($($SubscriptionArray[$SelectedSub - 1].SubscriptionID))
    {
        [guid]$SourceSubscriptionID = $($SubscriptionArray[$SelectedSub - 1].SubscriptionID)
    }
    if($($SubscriptionArray[$SelectedSub - 1].ID))
    {
        [guid]$SourceSubscriptionID = $($SubscriptionArray[$SelectedSub - 1].ID)
    }
    #$SubscriptionID = $SubscriptionID.Guid
}
Write-Host "Selecting the Source Azure Subscription: $($SourceSubscriptionID)..." -ForegroundColor Cyan
$Null = Select-AzSubscription -SubscriptionId $SourceSubscriptionID

# Use workspacename and resourcegroup if that is provided as parameters and validate it is a workspace that can be accessed
if($WSID -and $SourceSubscriptionID)
{
    try {
        $Workspaces = Get-AzOperationalInsightsWorkspace
        foreach($WS in $Workspaces)
        {
            if($WS.CustomerID -match $WSID)
            {
                $WorkspaceName = $WS.Name
                $WorkspaceRG = $WS.ResourceGroupName
            }
        }
        Write-Host "You Selected Workspace: " -nonewline -ForegroundColor Cyan
        Write-Host $WorkspaceName -ForegroundColor Yellow        
    }
    catch {
        Write-Warning -Message 'No Workspace found'
        break
    }
}

# Build a list of workspaces to choose from.  If workspace is in another subscription
# provide the resourceID of that workspace as a parameter
elseif(!($WSID))
{
    [array]$Workspaces=@()
    try
    {
        $Workspaces = Add-IndexNumberToArray (Get-AzOperationalInsightsWorkspace) 
        Write-Host "Generating a list of workspaces from Azure Subscription Selected..." -ForegroundColor Cyan

        [int]$SelectedWS = 0
        if ($Workspaces.Count -eq 1)
        {
            $SelectedWS = 1
        }

        # Get WS Resource ID if one isn't provided
        while($SelectedWS -gt $Workspaces.Count -or $SelectedWS -lt 1 -and $Null -ne $Workspaces)
        {
            Write-Host "Please select a workspace from the list below"
            $Workspaces| Select-Object "#", Name, Location, ResourceGroupName, ResourceId | Format-Table
            if($Workspaces.count -ne 0)
            {
                try
                {
                    $SelectedWS = Read-Host "Please enter a selection from 1 to $($Workspaces.count)"
                }
                catch
                {
                    Write-Warning -Message 'Invalid option, please try again.'
                }
            }
        }
    }
    catch
    {
        Write-Warning -Message 'No Workspace found - try specifying workspacename, resourcegroup and subscriptionID parameters'
    }
    If($Workspaces)
    {
        Write-Host "You Selected Workspace: " -nonewline -ForegroundColor Cyan
        Write-Host "$($Workspaces[$SelectedWS - 1].Name)" -ForegroundColor Yellow
        $WorkspaceName = $($Workspaces[$SelectedWS - 1].Name)
        $WSID = $($Workspaces[$SelectedWS - 1].CustomerId.Guid)
        $WorkspaceRG = $($Workspaces[$SelectedWS - 1].ResourceGroupName)
    }
    else
    {
        Throw "No OMS workspaces available in selected subscription $SubscriptionID"
        break
    }
}

# Establish a list of approved classifications available for the OS target
If($TargetOS -eq 'Windows')
{
    $Classifications = @('Unclassified','Critical','Security','UpdateRollup','FeaturePack','ServicePack','Definition','Tools','Updates')
}
If($TargetOS -eq 'Linux')
{
    $Classifications = @('Unclassified','Critical','Security','Other')
}

# If classifications were not provided via parameter, let's prompt for them (unless we have a query already given via parameter)
if(!($ClassificationList))
{
    While(!($ClassificationsChosen))
    {
        $CAnalysis=@()

        foreach($Classification in $Classifications)
        {
            $cObject = New-Object -TypeName PSObject -Property @{'Name' = $Classification}
            $CAnalysis += $CObject
        }
        # Build the menu and prompt for a selection
        $Canalysis = Add-IndexNumberToArray ($CAnalysis) 
        Write-Host "The following Classifications are available for $TargetOS"
        $CAnalysis|Select-Object "#",Name|Format-Table
        [array]$ClassificationCategories =@()
                
        [array]$ClassificationsChosen = (Read-host "Please provide # of classification(s) to process (separated by a comma) Note: Unclassified Reboots Only!").ToUpper()
                
        if($ClassificationsChosen -and (($ClassificationsChosen[0] -in 1..($ClassificationCategories.count -1))-or ($ClassificationsChosen[0].contains(","))))
        {
            # Trim spaces out
            $ClassificationsChosen = $ClassificationsChosen.replace(" ","")
                
            [array]$ClassificationsChosen = ($ClassificationsChosen -split ",")
                    
            foreach($Class in $ClassificationsChosen)
            {
                $ClassificationCategories = $ClassificationCategories + $($CAnalysis[$Class-1].Name)
            }
        }
        else
        {
            $ClassificationsChosen = $Null
        }
    }
}
else {
    [array]$ClassificationCategories = $ClassificationList    
}
If($ClassificationCategories)
{
    Write-Host "You Chose the following patch classifications" -ForegroundColor Cyan
    write-host $ClassificationCategories -ForegroundColor Yellow
    foreach($Line in $ClassificationCategories)
    {
        if($Line -eq "Unclassified")
        {
            write-host "You've chosen Unclassified! RebootOnly will be set." -ForegroundColor Red
            $RebootOptions = 'RebootOnly'
        }
    }
} 

if((!($ApplicablePatchesQuery) -and (!($KBLIST)-and (!($SavedSearchID)))))
{
    # Building a custom string for query to support a variable set of classifications
    $ClassificationsQueryString = "| where  "
    $Count = 1

    # Establish classifcations query string appropriate for Target OS according to those selected
    # Only used if a query was not provided through $ApplicablePatchesQuery
    foreach($Cat in $ClassificationCategories)
    {
        if($Count -lt $ClassificationCategories.Count)
        {
            $ClassificationsQueryString += "Classification has ""$Cat"" or "
        }
        else {
            $ClassificationsQueryString += "Classification has ""$Cat"""
        }
        $Count++
    }
    # Applicable Patches to Build against
    # This would include things such as classification, as well as Update State and OS
    $ApplicablePatchesQuery  = 'Update 
        | where OSType' + $OSQueryString + ' and Optional==false
        ' + $ClassificationsQueryString + '
        | summarize arg_max(TimeGenerated, *) by Computer,SourceComputerId,UpdateID, ApprovalSource, KBID
        | summarize hint.strategy=partitioned arg_max(TimeGenerated, *) by KBID
        | where UpdateState=~"Needed" and Approved!=false
        | project KBID, Title
        
        '

Write-Host "Leveraging the following query for applicable patches for target OS"
write-host "$ApplicablePatchesQuery" -ForegroundColor Cyan
}

if(!($KBLIST)-and !($RebootOptions -eq "RebootOnly"))
{
    $KBLIST=@()
    if($SavedSearchID)
    {
        $SavedSearch = Get-AzOperationalInsightsSavedSearch -ResourceGroupName $WorkspaceRG -WorkspaceName $WorkspaceName -SavedSearchId $SavedSearchID
        $ApplicablePatchesQuery = $($SavedSearch.Properties.Query) 
        Write-Host "Leveraging the following query for applicable patches for target OS"
        write-host "$ApplicablePatchesQuery" -ForegroundColor Cyan
    }
    # Search against Log Analytics to determine applicable patches to present as initial approved KBs for target Update Management Object
    $Value = Invoke-AzOperationalInsightsQuery -WorkspaceId $WSID -Query $ApplicablePatchesQuery
    foreach($Val in $Value.Results){$KBLIST += $Val.Kbid}

    write-host "Leveraging the following KBs for Target Update List" -ForegroundColor Cyan
    write-host $KBLIST -ForegroundColor Yellow
}
elseif($KBLIST-and !($RebootOptions -eq "RebootOnly"))
{
    write-host "Leveraging the following KBs for Target Update List" -ForegroundColor Cyan
    write-host $KBLIST -ForegroundColor Yellow
}

# Target subscription for Update Management Azure Automation Account
If($AzureLogin -and !($TargetSubscriptionID))
{
    if(!($SubscriptionArray))
    {
        [array]$SubscriptionArray = Add-IndexNumberToArray (Get-AzSubscription) 
        [int]$SelectedSub = 0
    }
    elseif ($SubscriptionArray.Count -eq 1)
    # use the current subscription if there is only one subscription available
    {
        [int]$SelectedSub = 1
    }
    else 
    {
        [int]$SelectedSub = 0
        # Get SubscriptionID if one isn't provided
        while($SelectedSub -gt $SubscriptionArray.Count -or $SelectedSub -lt 1)
        {
            Write-host "Please select a TARGET subscription from the list below for the Azure Update Configuration Package" -NoNewline
            $SubscriptionArray | Select-Object "#", Name, ID | Format-Table
            try
            {
                $SelectedSub = Read-Host "Please enter a selection from 1 to $($SubscriptionArray.count) for the TARGET subscription for Update Management Configuration"
            }
            catch
            {
                Write-Warning -Message 'Invalid option, please try again.'
            }
        }
        if($($SubscriptionArray[$SelectedSub - 1].Name))
        {
            $SubscriptionName = $($SubscriptionArray[$SelectedSub - 1].Name)
        }
        elseif($($SubscriptionArray[$SelectedSub - 1].SubscriptionName))
        {
            $SubscriptionName = $($SubscriptionArray[$SelectedSub - 1].SubscriptionName)
        }
        write-verbose "You Selected Azure Subscription: $SubscriptionName as your TARGET subscription"
        
        if($($SubscriptionArray[$SelectedSub - 1].SubscriptionID))
        {
            [guid]$TargetSubscriptionID = $($SubscriptionArray[$SelectedSub - 1].SubscriptionID)
        }
        if($($SubscriptionArray[$SelectedSub - 1].ID))
        {
            [guid]$TargetSubscriptionID = $($SubscriptionArray[$SelectedSub - 1].ID)
        }
        #$SubscriptionID = $SubscriptionID.Guid
    }
}
Write-Host "Selecting Target Azure Subscription: $($TargetSubscriptionID) ..." -ForegroundColor Cyan
$Null = Select-AzSubscription -SubscriptionId $TargetSubscriptionID

# Build a list of automation accounts to choose from.if Account and RG are not provided
if(!($AAAcountName -and $AAResourceGroupName))
{
    [array]$AAAcounts=@()
    try
    {
        $AAAcounts = Add-IndexNumberToArray (Get-AzAutomationAccount) 
        Write-Host "Generating a list of automation accounts from target Azure Subscription Selected..." -ForegroundColor Cyan
        [int]$SelectedAAA = 0
        if ($AAAcounts.Count -eq 1)
        {
            $SelectedAAA = 1
        }

        # Get AutomationAccount if one isn't provided
        while($SelectedAAA -gt $AAAcounts.Count -or $SelectedAAA -lt 1 -and $Null -ne $AAAcounts)
        {
            Write-Host "Please select an Automation Account from the list below"
            $AAAcounts| Select-Object "#", AutomationAccountName, Location, ResourceGroupName, SubscriptionIDId | Format-Table
            if($AAAcounts.count -ne 0)
            {
                try
                {
                    $SelectedAAA = Read-Host "Please enter a selection from 1 to $($AAAcounts.count)"
                }
                catch
                {
                    Write-Warning -Message 'Invalid option, please try again.'
                }
            }
        }
    }
    catch
    {
        Write-Warning -Message 'No Automation Account found - try specifying AAAcountName, AAResourceGroupName and TargetSubscriptionID parameters'
    }
    If($AAAcounts)
    {
        Write-Host "You Selected Automation Account: " -nonewline -ForegroundColor Cyan
        Write-Host "$($AAAcounts[$SelectedAAA - 1].AutomationAccountName)" -ForegroundColor Yellow
        $AAAcountName = $($AAAcounts[$SelectedAAA - 1].AutomationAccountName)
        $AAResourceGroupName = $($AAAcounts[$SelectedAAA - 1].ResourceGroupName)

    }
    else
    {
        Throw "No Automation Accounts available in selected subscription $TargetSubscriptionID"
        break
    }
}

# Use workspacename and resourcegroup if that is provided as parameters and validate it is a workspace that can be accessed
else
{
    try {
        $AAAcounts = Get-AzAutomationAccount
        foreach($AAA in $AAAcounts)
        {
            if($AAA.AutomationAccountName -match $AAAcountName)
            {
                Write-Host "Automation Account $AAAcountName exists" -ForegroundColor Cyan
            }
        }

        Write-Host "Selecting Azure Automation Account: " -nonewline -ForegroundColor Cyan
        Write-Host $AAAcountName -ForegroundColor Yellow        
    }
    catch {
        Write-Warning -Message 'No Azure Automation Accounts found'
        break
    }
}

# Use parameter to target more than one subscription / broader scope
if(!($queryScope))
{
    $queryScope = @("/subscriptions/$($TargetSubscriptionID)")
    write-host "No target scope provided.  Using target subscription as scope" -ForegroundColor Cyan
}

# If queryLocation is not provided, prompt for region(s)
if(!($queryLocation))
{
    $RAnalysis=@()

    $Regions = (Get-AzLocation).Location
    
    foreach($Region in $Regions)
    {
        $RObject = New-Object -TypeName PSObject -Property @{'Location' = $Region}
        $RAnalysis += $RObject
    }
    
    $Ranalysis = Add-IndexNumberToArray ($RAnalysis) 
    Write-Host "The following Regions are available for $OSTarget"
    $RAnalysis|Select-Object "#",Location|Format-Table
                
    [array]$RegionsChosen = (Read-host "Please provide # of region(s) to process (separated by a comma) or type ALL").ToUpper()
            
    if($RegionsChosen[0] -eq "ALL")
    {
        foreach($Reg in $RAnalysis)
        {
            $queryLocation = $queryLocation + $($Reg.Location)
        }
    }
    Write-Host "You chose the following location(s)" -ForegroundColor Cyan
    foreach($Line in $queryLocation)
    {
        write-host $Line -ForegroundColor Yellow
    }
    write-host ""
}
elseif($queryLocation)
{
    Write-Host "You've selected the following regions" -ForegroundColor Cyan
    write-host $queryLocation -ForegroundColor Yellow
    write-host ""
}
# Define the Azure Query for Scoping the Reference Machine set
$azq = New-AzAutomationUpdateManagementAzureQuery -ResourceGroupName $AAResourceGroupName `
    -AutomationAccountName $AAAcountName `
    -Scope $queryScope `
    -Location $queryLocation `
    -Tag $tags `
    -FilterOperator $queryFilterOperator

#NEXT TO BE DONE PRE-POST Scripts and PARAMS: https://docs.microsoft.com/en-us/azure/automation/pre-post-scripts
# Validate customer wants to continue to create the target schedule and Azure Update Management Configuration Patch List
# If Force used, will update without prompting
if ($Force -OR $PSCmdlet.ShouldContinue("This operation will create an Azure Update Management Deployment Schedule called ""$($SoftwareUpdateScheduleName)"" in your selected target subscription. Continue?","Creating Target Schedule named ""$SoftwareUpdateScheduleName""") )
{
    # BUG - Description doesn't populate : https://msazure.visualstudio.com/One/_workitems/edit/6524083
    if($ExpiryTime)
    {
        $Schedule = New-AzAutomationSchedule -Name $SoftwareUpdateScheduleName -AutomationAccountName $AAAcountName `
        -ResourceGroupName $AAResourceGroupName `
        -StartTime $StartTime `
        -Description $SoftwareUpdateScheduleDescr `
        -DaysOfWeek $DaysOfWeek `
        -WeekInterval $WeekInterval `
        -ForUpdateConfiguration `
        -ExpiryTime $ExpiryTime
        write-host "Creating / Updating the Target Azure Update Management Schedule ""$SoftwareUpdateScheduleName"" with expiration of $ExpiryTime" -ForegroundColor Cyan
    }
    else {
        $Schedule = New-AzAutomationSchedule -Name $SoftwareUpdateScheduleName -AutomationAccountName $AAAcountName `
        -ResourceGroupName $AAResourceGroupName `
        -StartTime $StartTime `
        -Description $SoftwareUpdateScheduleDescr `
        -DaysOfWeek $DaysOfWeek `
        -WeekInterval $WeekInterval `
        -ForUpdateConfiguration 
        write-host "Creating / Updating the Target Azure Update Management Schedule ""$SoftwareUpdateScheduleName"" with no expiration" -ForegroundColor Cyan
    }
    if($TargetOS -eq "Windows")
    {
        $Null = New-AzAutomationSoftwareUpdateConfiguration -ResourceGroupName $AAResourceGroupName `
        -AutomationAccountName $AAAcountName `
        -Schedule $Schedule `
        -Windows `
        -Duration $duration `
        -IncludedUpdateClassification $ClassificationCategories `
        -IncludedKbNumber $KBLIST `
        -AzureQuery $azq `
        -PreTaskRunbookName $PreScript `
        -PreTaskRunbookParameter $PreScriptParams `
        -PostTaskRunbookName $PostScript `
        -PostTaskRunbookParameter $PostScriptParams `
        -RebootSetting $RebootOptions
        write-host "Creating / Updating the Target Azure Update Management Deployment Schedule based on ""$SoftwareUpdateScheduleName"" for Windows" -ForegroundColor Cyan
    }
    # BUG - Linux Classification list does not match UI when sent via cmdlet (pending bug or backlog item - under review)
    elseif ($TargetOS -eq "Linux") {
        $Null = New-AzAutomationSoftwareUpdateConfiguration -ResourceGroupName $AAResourceGroupName `
        -AutomationAccountName $AAAcountName `
        -Schedule $Schedule `
        -Linux `
        -Duration $duration `
        -IncludedPackageClassification $ClassificationCategories `
        -IncludedPackageNameMask $KBLIST `
        -AzureQuery $azq `
        -PreTaskRunbookName $PreScript `
        -PreTaskRunbookParameter $PreScriptParams `
        -PostTaskRunbookName $PostScript `
        -PostTaskRunbookParameter $PostScriptParams `
        -RebootSetting $RebootOptions
        write-host "Creating / Updating the Target Azure Update Management Deployment Schedule based on ""$SoftwareUpdateScheduleName"" for Linux" -ForegroundColor Cyan
    }
    Write-Host "Complete!" -ForegroundColor Green
}
else
{
        Write-Host "You selected No - exiting"
        Write-Host "Complete" -ForegroundColor Cyan
}