<# This method creates a new error log file for each session,
   whenever an error is encountered, and appends valuable
   troubleshooting information to the file;
#>
function New-Office365DSCLogEntry
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Error,

        [Parameter()]
        [System.String]
        $Message
    )

    # Obtain the ID of the current PowerShell session. While this may
    # not be unique, it will;
    $SessionID = [System.Diagnostics.Process]::GetCurrentProcess().Id.ToString()

    # Generate the Error log file name based on the SessionID;
    $LogFileName = $SessionID + "-O365DSC-ErrorLog.log"

    # Build up the Error message to append to our log file;
    $LogContent = "[" + [System.DateTime]::Now.ToString("yyyy/MM/dd hh:mm:ss") + "]`r`n"
    $LogContent += "{" + $Error.CategoryInfo.Category.ToString() + "}`r`n"
    $LogContent += $Error.Exception.ToString() + "`r`n"
    $LogContent += "`"" + $Message + "`"`r`n"
    $LogContent += "`r`n`r`n"

    # Write the error content into the log file;
    $LogContent | Out-File $LogFileName -Append
}

function Add-O365DSCEvent
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.String]
        $Message,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Source = 'Generic',

        [Parameter()]
        [ValidateSet('Error', 'Information', 'FailureAudit', 'SuccessAudit', 'Warning')]
        [System.String]
        $EntryType = 'Information',

        [Parameter()]
        [System.UInt32]
        $EventID = 1
    )

    try
    {
        $CurrentLog = Get-EventLog -LogName 'Office365DSC' -Source $Source -ErrorAction SilentlyContinue
        if ($null -eq $CurrentLog)
        {
            $CurrentLog = New-EventLog -LogName 'Office365DSC' -Source $Source -ErrorAction SilentlyContinue
        }
        [System.Diagnostics.EventLog]::CreateEventSource($Source, "Office365DSC")
    }
    catch
    {
        Write-Verbose $_
    }

    try
    {
        Write-EventLog -LogName 'Office365DSC' -Source $Source `
            -EventID $EventID -Message $Message -EntryType $EntryType `
            -ErrorAction SilentlyContinue
    }
    catch
    {
        Write-Verbose $_
    }
}
