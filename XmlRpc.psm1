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
    [CmdletBinding()]
    [OutputType(
        [String]
    )]
    param(
        [Parameter(Position=0)]
        $InputObject,

        [Parameter()]
        [Array]$CustomTypes
    )

    Begin {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Function started"
        $Objects = @('Object')
        $objects += $CustomTypes
    }

    Process {
        if($inputObject -ne $null)
        {
            [string]$Type=$inputObject.GetType().Name
            # [string]$BaseType=$inputObject.GetType().BaseType
        } else {
            return "<value></value>"
        }

        # Return simple Types
        if(('Double','Int32','Boolean','False') -contains $Type)
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
        if('DateTime' -eq $Type){
            return "<value><dateTime.iso8601>$($inputObject.ToString(
            'yyyyMMddTHH:mm:ss'))</dateTime.iso8601></value>"
        }

        # Loop though Array
        if($inputObject -is [Array])
        {
            return "<value><array><data>$([string]::Join('',($inputObject|
            %{ConvertTo-XmlRpcType $_})))</data></array></value>"
        }

        # Loop though HashTable Keys
        if('Hashtable' -eq $Type)
        {
            return "<value><struct>$([string]::Join('',($inputObject.Keys|  % {
                '<member><name>'+$_+'</name>' + (ConvertTo-XmlRpcType $inputObject[$_]) + '</member>'
            })))</struct></value>"
        }

        # Loop though Object Properties
        if($Objects -contains $Type)
        {
            return "<value><struct>$([string]::Join('', (($inputObject | Get-Member -MemberType Properties).Name | % { "<member><name>$_</name>$(ConvertTo-XmlRpcType $inputObject.$_)</member>" } ) ) )</struct></value>"
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
        { Write-Verbose "$($MyInvocation.MyCommand.Name):: Function ended" }

}

function ConvertTo-XmlRpcMethodCall {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]$Name,

        [Parameter()]
        [Object]$Params,

        [Parameter()]
        [Array]$CustomTypes
    )


    Process {
        $out = [String]((&{
            "<?xml version=""1.0""?><methodCall><methodName>$($Name)</methodName><params>"
            if($Params) {
                $Params | %{ "<param>$(&{ConvertTo-XmlRpcType $_ -CustomTypes $CustomTypes})</param>" } }
            else { "$(ConvertTo-XmlRpcType $NULL)" }
            "</params></methodCall>"
        }) -join(''))

        $out
    }
}

function Send-XmlRpcRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [String]$Url,
        [Parameter(Mandatory = $true)]
        [String]$MethodName,
        [Parameter()]
        [Object]$Params,
        [Parameter()]
        [Array]$CustomTypes
    )

    try{
        ($doc=New-Object Xml.XmlDocument).LoadXml(
            (New-Object Net.WebClient).UploadString(
                $Url,
                ($global:z = ConvertTo-XmlRpcMethodCall $MethodName $Params -CustomTypes $CustomTypes)
            )
        )
        [Xml.XmlDocument]$doc
    }
    catch [System.Net.WebException],[System.IO.IOException] {'WebClient Error'}
    catch {'Unhandle Error',$error[0]}
    finally {}
}

function ConvertFrom-Xml {
    [CmdletBinding()]
    param(
        # Array node
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlDocument]$InputObject
    )

    Begin {
        $o = @()
        $endFormats = @('Int32','Double','Boolean','String','False','dateTime.iso8601')

        function ConvertFrom-XmlNode {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                $InputNode
            )

            Begin {
                $o = @()
                $endFormats = @('Int32','Double','Boolean','String','False','dateTime.iso8601')
            }

            Process {
                switch (($InputNode | gm -MemberType Properties).Name) {
                    'struct' {
                        $properties = @{}
                        foreach ($member in ($InputNode.struct.member)) {
                            if (!($member.value.gettype().name -in ("XmlElement","Object[]"))) {
                                $properties[$member.name] = $member.value
                            } else {
                                $properties[$member.name] = ConvertFrom-XmlNode $member.value
                            }
                        }

                        $o += $properties
                        break
                    }
                    'array' {
                        $properties = @()
                        if ($InputNode.array.data) {
                            foreach ($member in ($InputNode.array.data)) {
                                if (!($member.value.gettype().name -in ("XmlElement","Object[]"))) {
                                    $properties += $member.value
                                } else {
                                    $member.value | % {$properties += ConvertFrom-XmlNode $_}
                                }
                            }
                        }

                        $o += $properties
                        break
                    }
                    'boolean' {
                        $InputNode.boolean
                        break
                    }
                    'dateTime.iso8601' {
                        $string = $InputNode.'dateTime.iso8601'
                        [datetime]::ParseExact($string,”yyyyMMddTHH:mm:ss”,$null)
                        break
                    }
                    Default {
                        $o += $InputNode
                        break
                    }


                }
            }

            End {
                Write-Output $o
            }
        }
    }

    Process {
        $global:u = $InputObject
        foreach ($param in ($InputObject.methodResponse.params.param)) {
            foreach ($value in $param.value) {
                #if (!($endFormats -contains $value.gettype().name)) {
                    $o += ConvertFrom-XmlNode $value
                #} else {
                    #$o += $value
                #}
            }
        }
    }

    End {$o}
}