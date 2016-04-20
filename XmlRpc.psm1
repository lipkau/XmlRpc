#Requires -Version 2.0
<#
    .Synopsis
        This is a compilation of functions for XML RPC requests

    .Description


    .Notes
        Author   : Oliver Lipkau <oliver@lipkau.net>
        2014-06-05 Initial release
#>

Add-Type -AssemblyName System.Web

function ConvertTo-XmlRpcType
{
    <#
        .SYNOPSIS
            Convert Data into XML declared datatype string

        .DESCRIPTION
            Convert Data into XML declared datatype string

        .OUTPUTS
            string

        .PARAMETER InputObject
            Object to be converted to XML string

        .PARAMETER CustomTypes
            Array of custom Object Types to be considered when converting

        .EXAMPLE
            ConvertTo-XmlRpcType "Hello World"
            --------
            Returns
            <value><string>Hello World</string></value>

        .EXAMPLE
            ConvertTo-XmlRpcType 42
            --------
            Returns
            <value><int32>42</int32></value>
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [AllowNull()]
        [Parameter(
            Position=1,
            Mandatory=$true
        )]
        $InputObject,

        [Parameter()]
        [Array]$CustomTypes
    )

    Begin
    {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Function started"
        $Objects = @('Object')
        $objects += $CustomTypes
    }

    Process
    {
        if ($null -ne $inputObject)
        {
            [string]$Type=$inputObject.GetType().Name
            # [string]$BaseType=$inputObject.GetType().BaseType
        }
        else
        {
            return "<value></value>"
        }

        # Return simple Types
        if (('Double','Int32','Boolean','False') -contains $Type)
        {
            return "<value><$($Type)>$($inputObject)</$($Type)></value>"
        }

        # Encode string to HTML
        if ($Type -eq 'String')
        {
            return "<value><$Type>$([System.Web.HttpUtility]::HtmlEncode($inputObject))</$Type></value>"
        }

        # Int32 must be casted as Int
        if ($Type -eq 'Int16')
        {
            return "<value><int>$inputObject</int></value>"
        }

        if ($type -eq "SwitchParameter")
        {
            return "<value><boolean>$inputObject.IsPresent</boolean></value>"
        }

        # Return In64 as Double
        if (('Int64') -contains $Type)
        {
            return "<value><Double>$inputObject</Double></value>"
        }

        # DateTime
        if('DateTime' -eq $Type)
        {
            return "<value><dateTime.iso8601>$($inputObject.ToString(
            'yyyyMMddTHH:mm:ss'))</dateTime.iso8601></value>"
        }

        # Loop though Array
        if(($inputObject -is [Array]) -or ($Type -eq "List``1"))
        {
            try
            {
                return "<value><array><data>$(
                    [string]::Join(
                        '',
                        ($inputObject | ForEach-Object  {
                            if ($null -ne $_) {
                                ConvertTo-XmlRpcType $_ -CustomTypes $CustomTypes
                            } else {}
                        } )
                    )
                )</data></array></value>"
            }
            catch
            {
                throw
            }
        }

        # Loop though HashTable Keys
        if('Hashtable' -eq $Type)
        {
            return "<value><struct>$(
                [string]::Join(
                    '',
                    ($inputObject.Keys|  Foreach-Object {
                        "<member><name>$($_)</name>$(
                            if ($null -ne $inputObject[$_]) {
                                ConvertTo-XmlRpcType $inputObject[$_] -CustomTypes $CustomTypes
                            } else {
                                ConvertTo-XmlRpcType $null
                            })</member>"
                    } )
                )
            )</struct></value>"
        }

        # Loop though Object Properties
        if(($Objects -contains $Type) -and ($inputObject))
        {
            return "<value><struct>$(
                [string]::Join(
                    '',
                    (
                        ($inputObject | Get-Member -MemberType Properties).Name | Foreach-Object {
                            if ($null -ne $inputObject.$_) {
                                "<member><name>$($_)</name>$(
                                    ConvertTo-XmlRpcType $inputObject.$_ -CustomTypes $CustomTypes
                                )</member>"
                            }
                        }
                    )
                )
            )</struct></value>"
        }

        # XML
        if ('XmlElement','XmlDocument' -contains $Type)
        {
            return $inputObject.InnerXml.ToString()
        }

        # XML
        if ($inputObject -match "<([^<>]+)>([^<>]+)</\\1>")
        {
            return $inputObject
        }
    }

    End
        { Write-Verbose "$($MyInvocation.MyCommand.Name):: Function Ended" }
}

function ConvertTo-XmlRpcMethodCall
{
    <#
        .SYNOPSIS
            Create a XML RPC Method Call string
        .DESCRIPTION
            Create a XML RPC Method Call string

        .INPUTS
            string
            array

        .OUTPUTS
            string

        .PARAMETER Name
            Name of the Method to be called

        .PARAMETER Params
            Parameters to be passed to the Method

        .PARAMETER CustomTypes
            Array of custom Object Types to be considered when converting

        .EXAMPLE
            ConvertTo-XmlRpcMethodCall -Name updateName -Params @('oldName', 'newName')
            ----------
            Returns (line split and indentation just for conveniance)
            <?xml version=""1.0""?>
            <methodCall>
              <methodName>updateName</methodName>
              <params>
                <param><value><string>oldName</string></value></param>
                <param><value><string>newName</string></value></param>
              </params>
            </methodCall>
    #>
    [CmdletBinding()]
    [OutputType(
        [string]
    )]
    param(
        [Parameter(Mandatory = $true)]
        [String]$Name,

        [Parameter()]
        [Array]$Params,

        [Parameter()]
        [Array]$CustomTypes
    )

    Begin {}

    Process
    {
        [String]((&{
            "<?xml version=""1.0""?><methodCall><methodName>$($Name)</methodName><params>"
            if($Params)
            {
                $Params | ForEach-Object {
                    "<param>$(&{ConvertTo-XmlRpcType $_ -CustomTypes $CustomTypes})</param>"
                }
            }
            else
            {
                "$(ConvertTo-XmlRpcType $NULL)"
            }
            "</params></methodCall>"
        }) -join(''))
    }

    End {}
}

function Send-XmlRpcRequest
{
    <#
        .SYNOPSIS
            Send a XML RPC Request

        .DESCRIPTION
            Send a XML RPC Request

        .INPUTS
            string
            array

        .OUTPUTS
            XML.XmlDocument

        .EXAMPLE
            Send-XmlRpcRequest -Url "example.com" -MethodName "updateName" -Params @('oldName', 'newName')
            ---------
            Description
            Calls a method "updateName("oldName", "newName")" on the server example.com
    #>
    [CmdletBinding()]
    [OutputType([Xml.XmlDocument])]
    param(
        [Parameter(Mandatory = $true)]
        [String]$Url,

        [Parameter(Mandatory = $true)]
        [String]$MethodName,

        [Parameter()]
        [Array]$Params,

        [Parameter()]
        [Array]$CustomTypes,

        $methodCall
    )

    Begin {}

    Process
    {
        if (!$methodCall) {
            $methodCall = ConvertTo-XmlRpcMethodCall $MethodName $Params -CustomTypes $CustomTypes
        }
        # $global:b = $MethodCall

        try
        {
            $client = New-Object Net.WebClient
            $client.Encoding = [System.Text.Encoding]::UTF8
            $response = $client.UploadString($Url, $methodCall)

            $doc = New-Object Xml.XmlDocument
            $doc.LoadXml($response)
            [Xml.XmlDocument]$doc
        }
        catch [System.Net.WebException],[System.IO.IOException]{
            $message = "WebClient Error"
            $itemNotFoundException = New-Object -TypeName System.Management.Automation.ItemNotFoundException -ArgumentList $message
            $errorRecord = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList $itemNotFoundException,$itemNotFoundException.GetType().Name,'ConnectionError',$client
            Throw $errorRecord
        }
        catch {
            Throw $_
        }
    }

    End {}
}

function ConvertFrom-Xml
{
    [CmdletBinding()]
    param(
        # Array node
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlDocument]$InputObject
    )

    Begin
    {
        $endFormats = @('Int32','Double','Boolean','String','False','dateTime.iso8601')

        function ConvertFrom-XmlNode
        {
            [CmdletBinding()]
            [OutputType(
                [System.Int32],
                [System.Double],
                [System.Boolean],
                [System.String],
                [System.Boolean],
                [System.Datetime]
            )]
            param(
                [Parameter(Mandatory = $true)]
                $InputNode
            )

            Begin
            {
                $endFormats = @('Int32','Double','Boolean','String','False','dateTime.iso8601')
            }

            Process
            {
                switch (($InputNode | Get-Member -MemberType Properties).Name)
                {
                    'struct' {
                        $properties = @{}
                        foreach ($member in ($InputNode.struct.member))
                        {
                            if (!($member.value.gettype().name -in ("XmlElement","Object[]")))
                            {
                                $properties[$member.name] = $member.value
                            }
                            else
                            {
                                $properties[$member.name] = ConvertFrom-XmlNode $member.value
                            }
                        }

                        $properties
                        break
                    }
                    'array' {
                        if ($InputNode.array.data)
                        {
                            foreach ($member in ($InputNode.array.data))
                            {
                                if (!($member.value.gettype().name -in ("XmlElement","Object[]")))
                                {
                                    $member.value
                                }
                                else
                                {
                                    $member.value | ForEach-Object {
                                        ConvertFrom-XmlNode $_
                                    }
                                }
                            }
                        }
                        break
                    }
                    'boolean' {
                        [bool]$InputNode.boolean
                        break
                    }
                    'dateTime.iso8601' {
                        $string = $InputNode.'dateTime.iso8601'
                        [datetime]::ParseExact($string,"yyyyMMddTHH:mm:ss",$null)
                        break
                    }
                    Default {
                        $InputNode
                        break
                    }
                }
            }

            End
            {}
        }
    }

    Process
    {
        foreach ($param in ($InputObject.methodResponse.params.param))
        {
            foreach ($value in $param.value)
            {
                ConvertFrom-XmlNode $value
            }
        }
    }

    End {}
}