# Azure Sentinel Deployment Script
param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$WorkspaceName,
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "sentinel-deployment.config",
    
    [Parameter(Mandatory=$false)]
    [string]$WorkspaceId,
    
    [Parameter(Mandatory=$false)]
    [string]$ContentTypes,
    
    [Parameter(Mandatory=$false)]
    [string]$SourceControlId,
    
    [Parameter(Mandatory=$false)]
    [string]$Branch = "master"
)

# Import required modules
Import-Module Az.Resources
Import-Module Az.OperationalInsights

# Function to validate JSON content
function Test-JsonContent {
    param (
        [string]$FilePath
    )
    try {
        $content = Get-Content $FilePath -Raw
        $null = $content | ConvertFrom-Json
        return $true
    }
    catch {
        Write-Error "JSON validation failed for $FilePath : $_"
        return $false
    }
}

# Function to get content type from file
function Get-ContentType {
    param (
        [string]$FilePath
    )
    $content = Get-Content $FilePath -Raw
    $jsonContent = $content | ConvertFrom-Json
    
    # Check for content type in the file
    if ($jsonContent.PSObject.Properties.Name -contains "ContentType") {
        return $jsonContent.ContentType
    }
    
    # Determine content type based on file location
    $directory = Split-Path $FilePath -Parent
    $directoryName = Split-Path $directory -Leaf
    
    switch ($directoryName) {
        "Workbooks" { return "Workbook" }
        "Playbooks" { return "Playbook" }
        "Detections" { return "AnalyticsRule" }
        "Hunting Queries" { return "HuntingQuery" }
        "Parsers" { return "Parser" }
        "AutomationRules" { return "AutomationRule" }
        default { return $null }
    }
}

# Load deployment configuration
try {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    
    # Override config with command line parameters if provided
    if ($ResourceGroupName) { $config.workspaceSettings.resourceGroupName = $ResourceGroupName }
    if ($WorkspaceName) { $config.workspaceSettings.workspaceName = $WorkspaceName }
    if ($WorkspaceId) { $config.workspaceSettings.workspaceId = $WorkspaceId }
    if ($ContentTypes) { $config.contentTypes = $ContentTypes.Split(',') }
    if ($SourceControlId) { $config.deploymentSettings.sourceControlId = $SourceControlId }
    if ($Branch) { $config.deploymentSettings.branch = $Branch }
}
catch {
    Write-Error "Failed to load deployment configuration: $_"
    exit 1
}

# Get all JSON files recursively
$jsonFiles = Get-ChildItem -Path . -Filter "*.json" -Recurse -File

foreach ($file in $jsonFiles) {
    Write-Host "Processing file: $($file.FullName)"
    
    # Skip the deployment config file
    if ($file.Name -eq "sentinel-deployment.config") {
        continue
    }
    
    # Validate JSON content
    if (-not (Test-JsonContent -FilePath $file.FullName)) {
        Write-Warning "Skipping invalid JSON file: $($file.FullName)"
        continue
    }
    
    # Get content type
    $contentType = Get-ContentType -FilePath $file.FullName
    
    if (-not $contentType) {
        Write-Warning "Could not determine content type for: $($file.FullName)"
        continue
    }
    
    # Check if content type is in allowed list
    if ($contentType -notin $config.contentTypes) {
        Write-Warning "Content type '$contentType' not in allowed list for: $($file.FullName)"
        continue
    }
    
    # Deploy based on content type
    try {
        $deploymentName = "Deploy_$($file.BaseName)_$(Get-Date -Format 'yyyyMMddHHmmss')"
        
        switch ($contentType) {
            "Workbook" {
                New-AzResourceGroupDeployment -ResourceGroupName $config.workspaceSettings.resourceGroupName `
                    -TemplateFile $file.FullName `
                    -Name $deploymentName `
                    -Verbose
            }
            "Playbook" {
                New-AzResourceGroupDeployment -ResourceGroupName $config.workspaceSettings.resourceGroupName `
                    -TemplateFile $file.FullName `
                    -Name $deploymentName `
                    -Verbose
            }
            "AnalyticsRule" {
                $ruleContent = Get-Content $file.FullName -Raw | ConvertFrom-Json
                $ruleContent | ConvertTo-Json -Depth 10 | Set-Content "$($file.FullName).temp"
                
                New-AzResourceGroupDeployment -ResourceGroupName $config.workspaceSettings.resourceGroupName `
                    -TemplateFile "$($file.FullName).temp" `
                    -Name $deploymentName `
                    -Verbose
                
                Remove-Item "$($file.FullName).temp"
            }
            "HuntingQuery" {
                New-AzResourceGroupDeployment -ResourceGroupName $config.workspaceSettings.resourceGroupName `
                    -TemplateFile $file.FullName `
                    -Name $deploymentName `
                    -Verbose
            }
            "Parser" {
                New-AzResourceGroupDeployment -ResourceGroupName $config.workspaceSettings.resourceGroupName `
                    -TemplateFile $file.FullName `
                    -Name $deploymentName `
                    -Verbose
            }
            "AutomationRule" {
                New-AzResourceGroupDeployment -ResourceGroupName $config.workspaceSettings.resourceGroupName `
                    -TemplateFile $file.FullName `
                    -Name $deploymentName `
                    -Verbose
            }
            default {
                Write-Host "Deployment not implemented for content type: $contentType"
            }
        }
    }
    catch {
        Write-Error "Failed to deploy $($file.FullName): $_"
    }
}

Write-Host "Deployment completed" 