BeforeAll {
    # Load configuration for testing
    $config = Get-Content "./intunestack.yaml" -Raw | ConvertFrom-Yaml
}

Describe "IntuneStack Configuration Validation" -Tag "Configuration" {
    
    Context "YAML Configuration Structure" {
        It "Should have valid client configuration" {
            $config.client | Should -Not -BeNullOrEmpty
            $config.client.name | Should -Not -BeNullOrEmpty
            $config.client.tenantDomain | Should -Match "\.onmicrosoft\.com$|\.com$"
        }
        
        It "Should have valid authentication configuration" {
            $config.authentication.type | Should -Be "oidc"
            $config.authentication.clientId | Should -Not -BeNullOrEmpty
            $config.authentication.scopes | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Generated Configuration Files" {
        BeforeAll {
            # Generate configurations for testing
            if (Test-Path "./generated") {
                Remove-Item "./generated" -Recurse -Force
            }
            
            # Mock the generation process
            $clientName = $config.client.name
            $outputPath = "./generated/EUC-$clientName"
            New-Item -Path "$outputPath/configuration" -ItemType Directory -Force | Out-Null
            New-Item -Path "$outputPath/compliance" -ItemType Directory -Force | Out-Null
            New-Item -Path "$outputPath/scripts" -ItemType Directory -Force | Out-Null
        }
        
        It "Should create output directories" {
            $clientName = $config.client.name
            Test-Path "./generated/EUC-$clientName/configuration" | Should -Be $true
            Test-Path "./generated/EUC-$clientName/compliance" | Should -Be $true
            Test-Path "./generated/EUC-$clientName/scripts" | Should -Be $true
        }
    }
}

Describe "Template Validation" -Tag "Templates" {
    
    Context "JSON Template Files" {
        It "Should have valid BitLocker template" {
            $template = Get-Content "./templates/config-profiles/bitlocker.json" -Raw | ConvertFrom-Json
            $template.'@odata.type' | Should -Be "#microsoft.graph.windows10EndpointProtectionConfiguration"
            $template.bitLockerSystemDrivePolicy | Should -Not -BeNullOrEmpty
        }
        
        It "Should have valid compliance template" {
            $template = Get-Content "./templates/compliance-policies/bitlocker-compliance.json" -Raw | ConvertFrom-Json
            $template.'@odata.type' | Should -Be "#microsoft.graph.windows10CompliancePolicy"
            $template.storageRequireEncryption | Should -Not -BeNullOrEmpty
        }
    }
}
#endregion