# IntuneStack 🔥

> **Modern Intune Configuration Management with with progressive deployment rings and automated success gates**

IntuneStack is a foundation to provide CI/CD orchestration. IntuneStack focuses purely on deployment orchestration of policy - adding progressive group deployment, automated success criteria evaluation, and OIDC-enabled CI/CD pipeline to operationalize through deployment rings (dev → test → prod).

🚧 **Beginning of a Series**: This is the foundation of IntuneStack's deployment orchestration capabilities. As with all development, this is a living project that will continue to evolve and improve based on real-world usage and community feedback.

## 🎯 Key Features

- **Progressive Deployment Groups**: Automated dev → test → production group promotion with configurable success gates
- **Automated Group Promotion**: Automatic promotion based on predefined success criteria from device counts, success rates, and error thresholds
- **OIDC Authentication**: Secure GitHub Actions integration with Azure App Registration (no stored credentials)
- **Code Quality Enforcement**: PSScriptAnalyzer integration with pre-commit hooks and quality gates
- **GitHub Actions**: Fully automated CI/CD pipeline with environment protection and approval gates

## 🏗️ Project Structure

```
IntuneStack/
├── README.md
│
├── .github/                            # GitHub Actions CI/CD
│   └── workflows/
│       ├── policy-promotion.yml         # Main CI/CD pipeline
│       └── pr-validation.yml            # PR quality gates
│
├── .vscode/                            # VS Code integration
│   ├── extensions.json                 # Recommended extensions
│   ├── settings.json                   # PowerShell formatting rules
│   └── tasks.json                      # Quality check tasks
│
├── config/                             # Configuration files
│   ├── .editorconfig                   # Code formatting rules
│   ├── .pre-commit-config.yaml         # Pre-commit hooks
│   └── PSScriptAnalyzerSettings.psd1   # Custom analyzer rules
│
├── src/
│   ├── Get-DeviceConfigPolicies.ps1
│   ├── Invoke-CodeQuality.ps1
│   └── PolicyPromotion.ps1
│
├── output/                             # Generated deployment artifacts
│   └── reports/                        # Success and promotion reports
│
└── tests/                              # Pester tests
    ├── Configuration.Tests.ps1
    └── PolicyPromotion.Tests.ps1
```


## 🚀 Quick Start

### Prerequisites

1. **Azure App Registration** with OIDC configured for GitHub Actions
2. **PowerShell 7+** (for local development)
3. **Microsoft Graph PowerShell SDK** (automatically installed)
4. **GitHub repository** with appropriate secrets and variables


### 1. Azure App Registration Setup

Create an Azure App Registration with the following Graph API permissions:

```bash
# Required Microsoft Graph API permissions:
- DeviceManagementConfiguration.Read.All
- DeviceManagementConfiguration.ReadWrite.All  # For automated promotion
- Directory.Read.All                           # For group lookups
- Policy.Read.All
- Policy.ReadWrite.ConditionalAccess           # If managing CA policies
```

### 2. Configure OIDC for GitHub Actions

In your Azure App Registration:

1. Go to **Certificates & secrets** → **Federated credentials**
2. Add credential for **GitHub Actions deploying Azure resources**
3. Set:
   - **Organization**: Your GitHub username/org
   - **Repository**: Your repository name
   - **Entity type**: Branch
   - **GitHub branch name**: main

### 3. Set GitHub Secrets

In your GitHub repository settings (Settings → Secrets and variables → Actions):

**Secrets** (sensitive):
```bash
AZURE_TENANT_ID=your-tenant-id
AZURE_CLIENT_ID=your-application-client-id
```

**Variables** (optional, for custom group names):
```bash
INTUNESTACK_DEV_GROUP=Your-Dev-Group-Name
INTUNESTACK_TEST_GROUP=Your-Test-Group-Name
INTUNESTACK_PROD_GROUP=Your-Prod-Group-Name
```

> If variables are not set, IntuneStack uses default group names: `Intune-Dev-Users`, `Intune-Test-Users`, `Intune-Prod-Users`


### 4. Create Deployment Ring Groups in Entra ID

Create three Entra ID groups for your deployment rings:
- **Dev Group**: Initial deployment and testing
- **Test Group**: Broader testing before production
- **Prod Group**: Production deployment

These groups can be any Entra ID groups - no special configuration needed.

## 📋 Usage

### Manual Policy Promotion (GitHub Actions)

1. Go to **Actions** → **Policy Promotion Testing**
2. Click **Run workflow**
3. Enter parameters:
   - **Policy ID**: The GUID of the Intune policy to promote
   - **Current Stage**: `dev`, `test`, or `prod`
   - **Success Threshold**: Minimum success rate % for promotion (default: 80%)
   - **Auto Promote**: Enable to automatically promote if criteria met
   - **Output Level**: `Minimal`, `Normal`, or `Detailed`

### Local Development

```powershell
# Analyze a policy for promotion readiness
.\src\PolicyPromotion.ps1 -PolicyId "" -CurrentStage "dev"

# Automatically promote if success criteria met
.\src\PolicyPromotion.ps1 -PolicyId "" -CurrentStage "dev" -AutoPromote

# Use custom success threshold
.\src\PolicyPromotion.ps1 -PolicyId "" -CurrentStage "dev" -ComplianceThreshold 85

# Detailed output for debugging
.\src\PolicyPromotion.ps1 -PolicyId "" -CurrentStage "dev" -OutputLevel Detailed

# Custom output path
.\src\PolicyPromotion.ps1 -PolicyId "" -CurrentStage "dev" -OutputPath "./my-reports"
```

## 🔄 How It Works

### Deployment Ring Flow

```
┌─────────────────────────────────────────────────────────────┐
│  Policy Created in Intune (not assigned to any group)       │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Stage 1: DEV                                               │
│  ✓ Assign to Dev Group                                      │
│  ✓ Monitor success rate (target: 80%)                       │
│  ✓ Minimum devices & time requirements                      │
└────────────────────────┬────────────────────────────────────┘
                         │ Auto-promote if criteria met
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Stage 2: TEST                                              │
│  ✓ Assign to Test Group                                     │
│  ✓ Monitor success rate (target: 80%)                       │
│  ✓ Validate across larger user base                         │
└────────────────────────┬────────────────────────────────────┘
                         │ Auto-promote if criteria met
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Stage 3: PROD                                              │
│  ✓ Assign to Prod Group                                     │
│  ✓ Policy now in production                                 │
│  ✓ Continue monitoring for issues                           │
└─────────────────────────────────────────────────────────────┘
```

### Promotion Logic

The script analyzes each policy and determines:

1. **Current State**: Which groups is the policy currently assigned to?
2. **Target Stage**: Where should the policy go next?
3. **Success Metrics**:
   - Total devices receiving the policy
   - Success rate (% of devices with successful deployment)
   - Error rate (% of devices with errors)
   - Compliance with threshold requirements

4. **Action Decision**:
   - ✅ **Ready for promotion**: Success rate meets or exceeds threshold
   - ⏳ **Not ready**: Success rate below threshold
   - 🎉 **Complete**: Already deployed to all stages

### Example Output

```
🔥 IntuneStack Policy Promotion Analysis v1.0.0
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔐 Connecting to Microsoft Graph...
✓ Connected to Microsoft Graph

📋 Analysis Parameters:
   Policy ID:         12345678-1234-5678-9abc-def012345678
   Current Stage:     dev
   Success Threshold: 80%
   Auto Promote:      ✅ Enabled

🔍 Detecting policy type...
   ✓ Found: Skip User ESP
     Type: DeviceConfiguration

📋 Getting current policy assignments...
✅ Found 1 group assignment(s)
   - Intune-Dev-Users

📊 Analyzing policy deployment status...
📋 Current Policy Status:
   Policy Name: Skip User ESP
   Success Rate: 100%

🎯 Promotion Analysis:
   Ready for Promotion: ✅ YES
   Current Stage Assignment: ✅ YES
   Action: Promote to test
   Target Stage: test
   Target Group: Intune-Test-Users

🚀 Auto-deployment enabled - deploying to test...
🔍 Current assignments before deployment:
   - Intune-Dev-Users (aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee)

✅ Policy successfully deployed to test stage

🔍 Verifying updated assignments...
✅ Policy now assigned to 2 group(s):
   - Intune-Dev-Users (aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee)
   - Intune-Test-Users (ffffffff-gggg-hhhh-iiii-jjjjjjjjjjjj)

✅ Policy promotion analysis completed!
```

## 🧪 Testing

### Running Tests Locally

```powershell
# Run all Pester tests
Invoke-Pester -Path "./tests/PolicyPromotion.Tests.ps1"

# Run with code coverage
$config = New-PesterConfiguration
$config.Run.Path = "./tests/PolicyPromotion.Tests.ps1"
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = "./src/PolicyPromotion.ps1"
Invoke-Pester -Configuration $config
```

### GitHub Actions Testing

Tests run automatically on:
- **Push to main/development**: Full test suite
- **Pull requests**: Full test suite with code quality checks
- **Manual workflow**: Policy promotion testing with live Graph API

### Test Coverage

- ✅ Script syntax validation
- ✅ Function parameter validation
- ✅ Ring progression logic (dev → test → prod)
- ✅ Code quality (PSScriptAnalyzer)

## 🔐 Authentication

### OIDC (GitHub Actions)

Automatically used in CI/CD - no secrets stored in code:

```yaml
- name: Request OIDC token
  id: oidc
  run: |
    OIDC_TOKEN="$(curl -s -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
      "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)"
```

### Interactive (Local Development)

For testing locally, the script automatically falls back to interactive authentication:

```powershell
# Interactive browser authentication
.\src\PolicyPromotion.ps1 -PolicyId "" -CurrentStage "dev"
```

## 📊 Reports and Artifacts

### Promotion Report

After each run, a JSON report is generated at `./output/reports/promotion-report.json`:

```json
{
  "Timestamp": "2024-01-15 10:30:00 UTC",
  "PolicyId": "12345678-1234-5678-9abc-def012345678",
  "PolicyType": "DeviceConfiguration",
  "PolicyName": "Skip User ESP",
  "CurrentStage": "dev",
  "NextStage": "test",
  "ReadyForPromotion": true,
  "PromotionExecuted": true,
  "PromotionTargetStage": "test",
  "PromotionTargetGroup": "Intune-Test-Users",
  "PromotionTimestamp": "2024-01-15 10:30:15 UTC",
  "Metrics": {
    "TotalDevices": 8,
    "SuccessfulDevices": 8,
    "SuccessRate": 100,
    "ErrorDevices": 0
  }
}
```

### Log Files

Detailed logs are written to `./output/reports/promotion.log`:

```
2024-01-15 10:30:00 - [Info] Policy ID: 12345678-1234-5678-9abc-def012345678, Stage: dev
2024-01-15 10:30:05 - [Success] Connected to Microsoft Graph
2024-01-15 10:30:10 - [Info] Policy found: Skip User ESP (DeviceConfiguration)
2024-01-15 10:30:12 - [Success] Policy ready for test stage
2024-01-15 10:30:15 - [Success] Successfully promoted to test stage
```

## ⚙️ Configuration

### Success Thresholds

Default success thresholds by stage:

| Stage | Default Threshold | Recommended |
|-------|-------------------|-------------|
| Dev   | 80%               | 70-80%      |
| Test  | 80%               | 80-85%      |
| Prod  | 80%               | 85-95%      |

Customize per-run with `-ComplianceThreshold`:

```powershell
# Require 90% success for production
.\src\PolicyPromotion.ps1 -PolicyId "" -CurrentStage "test" -ComplianceThreshold 90 -AutoPromote
```

### Deployment Ring Groups

Configure custom group names using GitHub repository variables:

```bash
# Default group names (if variables not set)
INTUNESTACK_DEV_GROUP=Intune-Dev-Users
INTUNESTACK_TEST_GROUP=Intune-Test-Users
INTUNESTACK_PROD_GROUP=Intune-Prod-Users

# Custom group names (set as repository variables)
INTUNESTACK_DEV_GROUP=IT-Pilot-Ring
INTUNESTACK_TEST_GROUP=Finance-Pilot-Ring
INTUNESTACK_PROD_GROUP=All-Company-Devices
```

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `Invoke-Pester -Path "./tests"`
5. Run code quality: `Invoke-ScriptAnalyzer -Path "./src" -Recurse`
6. Submit a pull request

## 📚 Resources

- **[Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/)** - Graph API interaction
- **[Maester Documentation](https://maester.dev/docs/)** - OIDC authentication patterns
- **[GitHub OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)** - Secure authentication
- **[Intune Graph API](https://learn.microsoft.com/en-us/graph/api/resources/intune-graph-overview)** - API documentation
- **[Pester](https://pester.dev/)** - PowerShell testing framework

## 📄 License

GPL - See LICENSE file for details

## 🙏 Acknowledgments

- **[Andrew Taylor](https://github.com/andrew-s-taylor/public)** - Intune management function foundation
- **[Maester Team](https://maester.dev/)** - OIDC and testing patterns inspiration
- **Microsoft Graph Team** - Comprehensive PowerShell SDK
