function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $TeamName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $User,

        [Parameter()]
        [System.String]
        [ValidateSet("Guest", "Member", "Owner")]
        $Role = "Member",

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $GlobalAdminAccount
    )

    Write-Verbose -Message "Getting configuration of member $User to Team $TeamName"

    Test-MSCloudLogin -O365Credential $GlobalAdminAccount `
        -Platform MicrosoftTeams

    $nullReturn = @{
        User               = $User
        Role               = $Role
        TeamName           = $TeamName
        Ensure             = "Absent"
        GlobalAdminAccount = $GlobalAdminAccount
    }

    Write-Verbose -Message "Checking for existance of Team User $User"
    $team = Get-TeamByName $TeamName -ErrorAction SilentlyContinue
    if ($null -eq $team)
    {
        return $nullReturn
    }

    Write-Verbose -Message "Retrieve team GroupId: $($team.GroupId)"

    #region Telemetry
    $data = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $data.Add("Resource", $MyInvocation.MyCommand.ModuleName)
    $data.Add("Method", $MyInvocation.MyCommand)
    Add-O365DSCTelemetryEvent -Data $data
    #endregion

    try
    {
        Write-Verbose "Retrieving user without a specific Role specified"
        $allMembers = Get-TeamUser -GroupId $team.GroupId -ErrorAction SilentlyContinue
    }
    catch
    {
        Write-Warning "The current user doesn't have the rights to access the list of members for Team {$($TeamName)}."
        Write-Verbose $_
        return $nullReturn
    }

    if ($null -eq $allMembers)
    {
        Write-Verbose -Message "Failed to get Team's users for Team $TeamName"
        return $nullReturn
    }

    $myUser = $allMembers | Where-Object -FilterScript { $_.User -eq $User }
    Write-Verbose -Message "Found team user $($myUser.User) with role:$($myUser.Role)"
    return @{
        User               = $myUser.User
        Role               = $myUser.Role
        TeamName           = $TeamName
        Ensure             = "Present"
        GlobalAdminAccount = $GlobalAdminAccount
    }

}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $TeamName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $User,

        [Parameter()]
        [System.String]
        [ValidateSet("Guest", "Member", "Owner")]
        $Role = "Member",

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $GlobalAdminAccount
    )

    Write-Verbose -Message "Setting configuration of member $User to Team $TeamName"

    #region Telemetry
    $data = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $data.Add("Resource", $MyInvocation.MyCommand.ModuleName)
    $data.Add("Method", $MyInvocation.MyCommand)
    Add-O365DSCTelemetryEvent -Data $data
    #endregion

    Test-MSCloudLogin -O365Credential $GlobalAdminAccount `
        -Platform MicrosoftTeams

    $team = Get-TeamByName $TeamName

    Write-Verbose -Message "Retrieve team GroupId: $($team.GroupId)"

    $CurrentParameters = $PSBoundParameters
    $CurrentParameters.Remove("TeamName")
    $CurrentParameters.Add("GroupId", $team.GroupId)
    $CurrentParameters.Remove("GlobalAdminAccount")
    $CurrentParameters.Remove("Ensure")

    if ($Ensure -eq "Present")
    {
        Write-Verbose -Message "Adding team user $User with role:$Role"
        Add-TeamUser @CurrentParameters
    }
    else
    {
        if ($Role -eq "Member" -and $CurrentParameters.ContainsKey("Role"))
        {
            $CurrentParameters.Remove("Role")
            Write-Verbose -Message "Removed role parameter"
        }
        Remove-TeamUser @CurrentParameters
        Write-Verbose -Message "Removing team user $User"
    }
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $TeamName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $User,

        [Parameter()]
        [System.String]
        [ValidateSet("Guest", "Member", "Owner")]
        $Role = "Member",

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $GlobalAdminAccount
    )

    Write-Verbose -Message "Testing configuration of member $User to Team $TeamName"

    $CurrentValues = Get-TargetResource @PSBoundParameters

    if ($null -eq $Role)
    {
        $CurrentValues.Remove("Role")
    }

    Write-Verbose -Message "Current Values: $(Convert-O365DscHashtableToString -Hashtable $CurrentValues)"
    Write-Verbose -Message "Target Values: $(Convert-O365DscHashtableToString -Hashtable $PSBoundParameters)"

    $TestResult = Test-Office365DSCParameterState -CurrentValues $CurrentValues `
        -Source $($MyInvocation.MyCommand.Source) `
        -DesiredValues $PSBoundParameters `
        -ValuesToCheck @("Ensure", `
            "User", `
            "Role")

    Write-Verbose -Message "Test-TargetResource returned $TestResult"

    return $TestResult
}

function Export-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter()]
        [ValidateRange(1, 100)]
        $MaxProcesses,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $GlobalAdminAccount
    )
    $InformationPreference ='Continue'

    #region Telemetry
    $data = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $data.Add("Resource", $MyInvocation.MyCommand.ModuleName)
    $data.Add("Method", $MyInvocation.MyCommand)
    Add-O365DSCTelemetryEvent -Data $data
    #endregion

    $result = ""

    # Get all Site Collections in tenant;
    $instances = Get-Team
    if ($instances.Length -ge $MaxProcesses)
    {
        $instances = Split-ArrayByParts -Array $instances -Parts $MaxProcesses
        $batchSize = $instances[0].Length
    }
    else
    {
        $MaxProcesses = $instances.Length
        $batchSize = 1
    }

    # Define the Path of the Util module. This is due to the fact that inside the Start-Job
    # the module is not imported and simply doing Import-Module Office365DSC doesn't work.
    # Therefore, in order to be able to call into Invoke-O365DSCCommand we need to implicitly
    # load the module.
    $UtilModulePath = $PSScriptRoot + "\..\..\Modules\Office365DSCUtil.psm1"

    # For each batch of 8 items, start and asynchronous background PowerShell job. Each
    # job will be given the name of the current resource followed by its ID;
    $i = 1
    foreach ($batch in $instances)
    {
        Start-Job -Name "TeamsUser$i" -ScriptBlock {
            Param(
                [Parameter(Mandatory = $true)]
                [System.Object[]]
                $Instances,

                [Parameter(Mandatory = $true)]
                [System.String]
                $ScriptRoot,

                [Parameter(Mandatory = $true)]
                [System.String]
                $UtilModulePath,

                [Parameter(Mandatory = $true)]
                [System.Management.Automation.PSCredential]
                $GlobalAdminAccount
            )
            # Implicitly load the Office365DSCUtil.psm1 module in order to be able to call
            # into the Invoke-O36DSCCommand cmdlet;
            Import-Module $UtilModulePath -Force

            # Invoke the logic that extracts the all the Property Bag values of the current site using the
            # the invokation wrapper that handles throttling;
            $returnValue = ""
            $returnValue += Invoke-O365DSCCommand -Arguments $PSBoundParameters -InvokationPath $ScriptRoot -ScriptBlock {
                $params = $args[0]
                $content = ""
                $j = 1
                Test-MSCloudLogin -CloudCredential $params.GlobalAdminAccount `
                    -Platform MicrosoftTeams

                $principal = "" # Principal represents the "NetBios" name of the tenant (e.g. the O365DSC part of O365DSC.onmicrosoft.com)
                if ($GlobalAdminAccount.UserName.Contains("@"))
                {
                    $organization = $GlobalAdminAccount.UserName.Split("@")[1]

                    if ($organization.IndexOf(".") -gt 0)
                    {
                        $principal = $organization.Split(".")[0]
                    }
                }
                $InformationPreference = 'Continue'
                foreach ($item in $params.Instances)
                {
                    foreach ($team in $item)
                    {
                        try
                        {
                            $users = Get-TeamUser -GroupId $team.GroupId
                            $i = 1
                            $totalCount = $item.Count
                            if ($null -eq $totalCount)
                            {
                                $totalCount = 1
                            }
                            Write-Information "    > [$j/$totalCount] Team {$($team.DisplayName)}"
                            foreach ($user in $users)
                            {
                                Write-Information "        - [$i/$($users.Length)] $($user.User)"
                                $getParams = @{
                                    TeamName           = $team.DisplayName
                                    User               = $user.User
                                    GlobalAdminAccount = $params.GlobalAdminAccount
                                }
                                $CurrentModulePath = $params.ScriptRoot + "\MSFT_TeamsUser.psm1"
                                Import-Module $CurrentModulePath -Force
                                $result = Get-TargetResource @getParams
                                $result.GlobalAdminAccount = Resolve-Credentials -UserName "globaladmin"
                                $partialContent = "        TeamsUser " + (New-GUID).ToString() + "`r`n"
                                $partialContent += "        {`r`n"
                                $currentDSCBlock = Get-DSCBlock -Params $result -ModulePath $params.ScriptRoot
                                $partialContent += Convert-DSCStringParamToVariable -DSCBlock $currentDSCBlock -ParameterName "GlobalAdminAccount"
                                $partialContent += "        }`r`n"
                                if ($partialContent.ToLower().Contains($organization.ToLower()))
                                {
                                    $partialContent = $partialContent -ireplace [regex]::Escape($organization), "`$OrganizationName"
                                }
                                $content += $partialContent
                                $i++
                            }
                        }
                        catch
                        {
                            Write-Information $_
                            Write-Information "The current User doesn't have the required permissions to extract Users for Team {$($team.DisplayName)}."
                        }
                        $j++
                    }
                }
                return $content
            }
            return $returnValue
        } -ArgumentList @($batch, $PSScriptRoot, $UtilModulePath, $GlobalAdminAccount) | Out-Null
        $i++
    }


    Write-Information "    Broke extraction process down into {$MaxProcesses} jobs of {$($instances[0].Length)} item(s) each"
    $totalJobs = $MaxProcesses
    $jobsCompleted = 0
    $status = "Running..."
    $elapsedTime = 0
    do
    {
        $jobs = Get-Job | Where-Object -FilterScript { $_.Name -like '*TeamsUser*' }
        $count = $jobs.Length
        foreach ($job in $jobs)
        {
            if ($job.JobStateInfo.State -eq "Complete")
            {
                $partialResult = Receive-Job -name $job.name
                $result += $partialResult
                Remove-Job -name $job.name
                $jobsCompleted++
            }
            elseif ($job.JobStateInfo.State -eq 'Failed')
            {
                Remove-Job -name $job.name
                Write-Warning "{$($job.name)} failed"
                break
            }

            $status = "Completed $jobsCompleted/$totalJobs jobs in $elapsedTime seconds"
            $percentCompleted = $jobsCompleted / $totalJobs * 100
            Write-Progress -Activity "TeamsUser Extraction" -PercentComplete $percentCompleted -Status $status
        }
        $elapsedTime ++
        Start-Sleep -Seconds 1
    } while ($count -ne 0)
    Write-Progress -Activity "TeamsUser Extraction" -PercentComplete 100 -Status "Completed" -Completed
    return $result
}

Export-ModuleMember -Function *-TargetResource
