# Script to whitelist IP address to Azure Storage Account #
# It will also remove an existing IP if passed as a parameter, this is an optional step #
# Ensure that requirements.psd1 has "Az" module uncommented so Azure Function will first install it as dependency #
# We will need a Service Principal with Storage Account Contributer access #
# SP credentials are kept in an Azure Key Vault which is added to Azure Functions App settings and fetched in the script using $ENV variable #
# For testing locally, you will need to replace $AppSecret value with actual SP secret. Azure Key Vault won't work in local testing #

using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function initiated a request."

# Sample query parameter: 
# {"ResourceGroupName": "whitelistip", "StorageAccountName": "storageip", "RemoveIP": "75.67.234.101", "AddIP": "75.67.234.105"}

$TenantId = "72f988bf-86f1-41af-91ab-2d7cd011db47" # <Provide your Azure AD GUID> #
$ApplicationId = "6d9c734b-7fed-47ee-b3cc-e004595a9335" # <Provide Service Principal application or client ID> #

# $AppSecret = "_Re8Q~M12n2Dr8tUuSPR9w6Mx-VdIBMT2iYdOc2W"
$AppSecret = $ENV:AppSecret
$SecuredPassword = ConvertTo-SecureString -String $AppSecret -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ApplicationId, $SecuredPassword

# Interact with query parameters or the body of the request.
$ResourceGroupName = $Request.Query.ResourceGroupName #"whitelistip"
$StorageAccountName = $Request.Query.StorageAccountName #"storageip"
$RemoveIP = $Request.Query.RemoveIP #"75.67.234.100"
$AddIP = $Request.Query.AddIP #"75.67.234.101"

$body1 = "Pass a parameters in the query string or in the request body."

if (-not $ResourceGroupName) {
    $ResourceGroupName = $Request.Body.ResourceGroupName
}

if (-not $StorageAccountName) {
    $StorageAccountName = $Request.Body.StorageAccountName
}

if (-not $RemoveIP) {
    $RemoveIP = $Request.Body.RemoveIP
}

if (-not $AddIP) {
    $AddIP = $Request.Body.AddIP
}

try {

    if ($Credential) {

        $body2 = "Azure credentials found, now making connection to Azure account."

        Connect-AzAccount -ServicePrincipal -TenantId $TenantId -Credential $Credential


        $body3 = "Connected to Azure, now making changes to Azure storage IP whitelist."

        if ($ResourceGroupName -And $StorageAccountName) {
            
            # Get all the IPs currently added to Storage Account firewall
            $NetworkRuleSet = Get-AzStorageAccountNetworkRuleSet -ResourceGroupName $ResourceGroupName -Name $StorageAccountName

            # Iterate through all IPs in the list and see if $RemoveIP and $AddIP already exist (or not exist) to take proper action

            for (($i = 0); $i -lt $NetworkRuleSet.IpRules.Count; $i++) {

                    if($RemoveIP){ 
                        if($RemoveIP -eq $NetworkRuleSet.IpRules[$i].IPAddressOrRange){

                            # $RemoveIP found in the Storage Account firewall and it will be removed
                            Remove-AzStorageAccountNetworkRule -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -IPAddressOrRange $RemoveIP
                            Write-Output "IP address $RemoveIP found and removed from Storage Account firewall."
                            $body4 = "IP address $RemoveIP found and removed from Storage Account firewall."
                        } else{
                            Write-Output "IP address $RemoveIP not found in Storage Account firewall and cannot be removed."
                            $body4 = "IP address $RemoveIP not found in Storage Account firewall and cannot be removed."
                        }
                    }

                    if($AddIP){ 
                        if($AddIP -eq $NetworkRuleSet.IpRules[$i].IPAddressOrRange){
                            Write-Output "IP address $AddIP already found in Storage Account firewall and need not be added again."
                            $body5 = "IP address $AddIP already found in Storage Account firewall and need not be added again."
                        } else{
                            # $AddIP will be added to the Storage Account firewall
                            Add-AzStorageAccountNetworkRule -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -IPAddressOrRange $AddIP
                            Write-Output "IP address $AddIP added to Storage Account firewall."
                            $body5 = "IP address $AddIP added to Storage Account firewall."
                        }
                    }
                }
        }
    }    
}
catch {
    Write-Output "Something threw an exception"
    Write-Output $_
    $body = "Ran into an issue: $PSItem"
}

# Prepare http response
$body = $body1, $body2, $body3, $body4, $body5 -join "`r`n"

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $body
})
