# Choose Subscription

$subscriptionID="f0e6a708-6962-41b1-b2d3-a43615d7b4fb"

Select-AzSubscription -SubscriptionName 'CSR-CUSPOC-NMST-ashenparikh-sub02'
Set-AzContext -SubscriptionId $subscriptionID

# # Register Resource Providers
# if (Get-AzResourceProvider -ProviderNamespace Microsoft.VirtualMachineImages) {
#     Write-Output "Resource Provider VirtualMachineImages Already Registered"
# }
# else {
#     Register-AzResourceProvider -ProviderNamespace Microsoft.VirtualMachineImages
# }

# if (Get-AzResourceProvider -ProviderNamespace Microsoft.Storage)  {
#     Write-Output "Resource Provider Microsoft.Storage  Already Registered"
# }
# else {
#     Register-AzResourceProvider -ProviderNamespace Microsoft.Storage
# }

# if (Get-AzResourceProvider -ProviderNamespace Microsoft.Compute) {
#     Write-Output "Resource Provider Microsoft.Compute Already Registered"
# }
# else {
#     Register-AzResourceProvider -ProviderNamespace Microsoft.Compute
# }

# if (Get-AzResourceProvider -ProviderNamespace Microsoft.KeyVault) {
#     Write-Output "Resource Provider KeyVault Already Registered"
# }
# else {
#     Register-AzResourceProvider -ProviderNamespace Microsoft.KeyVault
# }

##Set up Env Variables 

# Step 1: Import module
Import-Module Az.Accounts

# destination image resource group
$imageResourceGroup="rsg-usw2-p-vditemplate-01"

# location (see possible locations in main docs)
$location="westus2"

# image template name
$imageTemplateName="armTemplateAIB"

# image definition name
$imageDefName = "win10avd"

# distribution properties object name (runOutput), i.e. this gives you the properties of the managed image on completion
$runOutputName="sigOutput"

# create resource group
#New-AzResourceGroup -Name $imageResourceGroup -Location $location

#specify compute gallery
$sigGalleryName= "NewmontEnterpriseComputeGallery"

## Create User Identity

# setup role def names, these need to be unique
$timeInt=$(get-date -format FileDateTime)
$imageRoleDefName="Azure Image Builder Image Def"+$timeInt
$identityName="aibIdentity"+$timeInt

## Add AZ PS modules to support AzUserAssignedIdentity and Az AIB
# Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted

# if (Get-Module -Name "Az.ImageBuilder") {
#     Write-Output "Az.ImageBuilder Already Installed"
# }
# else {
#     Install-Module -Name 'Az.ImageBuilder'
# }

# if (Get-Module -Name 'Az.ManagedServiceIdentity') {
#     Write-Output "Az.ManagedServiceIdentity Already Installed"
# }
# else {
#     Install-Module -Name 'Az.ManagedServiceIdentity'
# }

#Install-Module -Name 'Az.ImageBuilder'
#Install-Module -Name 'Az.ManagedServiceIdentity'  

# create identity
New-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName -Location  $location

$identityNameResourceId=$(Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName).Id
$identityNamePrincipalId=$(Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName).PrincipalId


## Create Role Definition for Identity
$aibRoleImageCreationUrl="https://raw.githubusercontent.com/azure/azvmimagebuilder/master/solutions/12_Creating_AIB_Security_Roles/aibRoleImageCreation.json"
$aibRoleImageCreationPath = "aibRoleImageCreation.json"

# download config
Invoke-WebRequest -Uri $aibRoleImageCreationUrl -OutFile $aibRoleImageCreationPath -UseBasicParsing

((Get-Content -path $aibRoleImageCreationPath -Raw) -replace '<subscriptionID>',$subscriptionID) | Set-Content -Path $aibRoleImageCreationPath
((Get-Content -path $aibRoleImageCreationPath -Raw) -replace '<rgName>', $imageResourceGroup) | Set-Content -Path $aibRoleImageCreationPath
((Get-Content -path $aibRoleImageCreationPath -Raw) -replace 'Azure Image Builder Service Image Creation Role', $imageRoleDefName) | Set-Content -Path $aibRoleImageCreationPath

# create role definition
New-AzRoleDefinition -InputFile  ./aibRoleImageCreation.json

# grant role definition to image builder service principal
New-AzRoleAssignment -ObjectId $identityNamePrincipalId -RoleDefinitionName $imageRoleDefName -Scope "/subscriptions/$subscriptionID/resourceGroups/$imageResourceGroup" -PrincipalType 'ServicePrincipal'

## Update Master Template with new variables

$templateUrl="https://raw.githubusercontent.com/azure/azvmimagebuilder/master/solutions/14_Building_Images_WVD/armTemplateWVD.json"
$templateFilePath = "armTemplateAIB.json"

Invoke-WebRequest -Uri $templateUrl -OutFile $templateFilePath -UseBasicParsing

((Get-Content -path $templateFilePath -Raw) -replace '<subscriptionID>',$subscriptionID) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<rgName>',$imageResourceGroup) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<region>',$location) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<runOutputName>',$runOutputName) | Set-Content -Path $templateFilePath

((Get-Content -path $templateFilePath -Raw) -replace '<imageDefName>',$imageDefName) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<sharedImageGalName>',$sigGalleryName) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<region1>',$location) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<imgBuilderId>',$identityNameResourceId) | Set-Content -Path $templateFilePath

#Submit the image
New-AzResourceGroupDeployment -ResourceGroupName $imageResourceGroup -TemplateFile $templateFilePath -imageTemplateName $imageTemplateName -svclocation $location
# Optional - if you have any errors running the above, run:
$getStatus=$(Get-AzImageBuilderTemplate -ResourceGroupName $imageResourceGroup -Name $imageTemplateName)
$getStatus.ProvisioningErrorCode 
$getStatus.ProvisioningErrorMessage

#Build the image
Start-AzImageBuilderTemplate -ResourceGroupName $imageResourceGroup -Name $imageTemplateName -NoWait

$getStatus=$(Get-AzImageBuilderTemplate -ResourceGroupName $imageResourceGroup -Name $imageTemplateName)

# this shows all the properties
$getStatus | Format-List -Property *

# these show the status the build
$getStatus.LastRunStatusRunState 
$getStatus.LastRunStatusMessage
$getStatus.LastRunStatusRunSubState

