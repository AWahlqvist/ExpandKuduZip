function GetKuduApiRequestSplattingHash
{
    <#
    .SYNOPSIS
    This helper function creates a hashtable containing the basic properties needed
    to use the REST-api for Kudu.

    .DESCRIPTION
    This helper function creates a hashtable containing the basic properties needed
    to use the REST-api for Kudu. Other properties will need to be added for
    most calls but that will be handled in the respective functions for those methods.

    #>

    [cmdletbinding()]
    [OutputType([System.Collections.Hashtable])]
    Param(
        [Parameter(Mandatory=$True)]
        [System.Management.Automation.PSCredential] $Credential,

        [Parameter(Mandatory=$True)]
        [string] $SiteName,

        [Parameter(Mandatory=$True)]
        [string] $UriEnding,

        [Parameter(Mandatory=$false)]
        [string] $OutFile,

        [Parameter(Mandatory=$false)]
        [string] $InFile
    )

    BEGIN {
    
    }

    PROCESS {

        $BaseURI = "https://$SiteName.scm.azurewebsites.net/api/"

        $Base64AuthString = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("$($Credential.UserName):$($Credential.GetNetworkCredential().Password)")))

        $HashToReturn = @{
            'Headers' = @{
                'Authorization' = "Basic $Base64AuthString"
            }
            'Uri' = $BaseURI + $UriEnding
            'ContentType' = 'multipart/form-data'
        }

        if ($OutFile) {
            $HashToReturn.Add('OutFile',$OutFile)
        }

        if ($InFile) {
            $HashToReturn.Add('InFile',$InFile)
        }

        return $HashToReturn
    }

    END { }
}


function InvokeKuduApiRequest
{
    <#
    .SYNOPSIS
    This helper function does the actual API call to the Kudu service.

    .DESCRIPTION
    This helper function performs the actual API call to Kudu

    #>

    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$True)]
        [hashtable] $RequestSplattingHash,
        [Parameter(Mandatory=$false)]
        [hashtable] $RequestPayload,
        [Parameter(Mandatory=$false)]
        [switch] $UseWebClientDownload
    )

    if ($RequestPayload) {
        try {
            $JsonPayload = $RequestPayload | ConvertTo-Json -ErrorAction Stop
        }
        catch {
            throw "Failed to convert the request payload to Json-format. The error was: $($_.ToString())"
        }

        $RequestSplattingHash.Add('Body', $JsonPayload)

        # Change content type for json payloads
        $RequestSplattingHash.Remove('ContentType')
        $RequestSplattingHash.Add('ContentType', 'application/json')
    }

    if ($UseWebClientDownload.IsPresent) {
        $WebClient = New-Object System.Net.WebClient
        $WebClient.Headers.Add('Authorization', $RequestSplattingHash.Headers['Authorization'])
        $WebClient.Headers.Add('ContentType', $RequestSplattingHash.ContentType)

        $WebClient.DownloadFile($RequestSplattingHash.Uri, $RequestSplattingHash.OutFile)
    }
    else {
        try {
            $Response = Invoke-RestMethod @RequestSplattingHash -ErrorAction Stop -Verbose:$false
        }
        catch {
            throw "API call failed! The error was: $($_.ToString())"
        }
    }

    return $Response
}


function Expand-KuduSiteArchive
{

    <#
    .SYNOPSIS
    Uploades and expands the specified zip file to the specified site

    .DESCRIPTION
    This function will upload and expand the specified zip-file on 
    a azure site to the path you specify

    .EXAMPLE
    Expand-KuduSiteArchive -Credential $KuduCred -SiteName MySite -SlotName staging -SitePath site\wwwroot -InFile C:\MySite\wwwroot.zip

    Will upload and expand the file wwwroot.zip to the wwwroot folder on the web app

    .PARAMETER Credential
    The credential to choose when connecting to the Kudu API.

    .PARAMETER  SiteName
    The site name

    .PARAMETER SlotName
    The slot name (optional)

    .PARAMETER  SitePath
    The path to the (remote) folder where the zipfile should be expanded

    .PARAMETER  InFile
    The local path for the zip-file you wish to upload

    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [System.Management.Automation.PSCredential] $Credential,

        [Parameter(Mandatory=$True, ValueFromPipelineByPropertyName=$true)]
        [string] $SiteName,

        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string] $SlotName,

        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string] $SitePath,

        [parameter(Mandatory=$True, ValueFromPipelineByPropertyName=$true)]
        [string] $InFile
    )


    BEGIN { }

    PROCESS {

        if ($SlotName -AND $SlotName -ne 'Production') {
            $SiteURL = "$SiteName-$SlotName"
        }
        else {
            $SiteURL = "$SiteName"
        }

        if ($SitePath -notmatch "/$") {
            $SitePath = "$($SitePath)/"
        }


        $URIEnding  = "zip/$SitePath" -replace "//$","/"

        $RequestHash = GetKuduApiRequestSplattingHash -Credential $Credential -SiteName $SiteURL -UriEnding $URIEnding -InFile $InFile

        $RequestHash.Add('Method','Put')

        InvokeKuduApiRequest -RequestSplattingHash $RequestHash
    }

    END { }
}


