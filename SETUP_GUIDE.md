# End-to-End Setup Guide: webMethods.io Integration CI/CD Framework

This guide provides complete step-by-step instructions to set up and run the `webmethods-io-int-cicd` project from scratch.

---

## 📋 Prerequisites

Before starting, ensure you have:

### Accounts & Access
- **Azure DevOps Organization**: Access to an organization where you can create projects
- **GitHub Account**: For source control (user and Personal Access Token with `repo`, `workflow` scopes)
- **webMethods.io Integration Account**: At least two environments:
  - **Play/Build** (for initial testing)
  - **DEV** (for first promotion)
  - **QA** (optional, for testing promotion)
  - **PROD** (optional, for final deployment)
- **Azure Subscription** (optional but recommended): For Azure Key Vault secret storage

### Local Tools
- **Git** (command line)
- **PowerShell** v5.1+ (Windows) or **Bash** (Linux/macOS)
- Optional but recommended:
  - `yq` (YAML query)
  - `jq` (JSON processor)
  - `curl` (HTTP client)
  - `perl` (URI encoding)

---

## 🔧 Part 1: Prepare Your GitHub Repository

### Step 1.1: Fork or Clone the Framework

Option A: Fork the repo on GitHub (recommended for contributions)
```bash
# Go to https://github.com/IBM/webmethods-io-int-cicd and click "Fork"
# Then clone your fork locally
git clone https://github.com/<your-github-username>/webmethods-io-int-cicd.git
cd webmethods-io-int-cicd
```

Option B: Clone directly (for testing)
```bash
git clone https://github.com/IBM/webmethods-io-int-cicd.git
cd webmethods-io-int-cicd
```

### Step 1.2: Create a New Repository for Your Project

```bash
# In your GitHub account, create a new empty repository
# Name it: <your-project-name> (e.g., "my-wmio-integration")
# Do NOT initialize with README, .gitignore, or license

# Then, in your local framework clone, create a new branch and push to your project repo:
git remote add project https://github.com/<your-github-username>/<your-project-name>.git
git checkout -b main
git push -u project main
```

This creates the base repo where your project assets will live.

### Step 1.3: Generate GitHub Personal Access Token (PAT)

1. Go to GitHub → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)**
2. Click **Generate new token**
3. Name: `Azure_DevOps_Pipeline`
4. Scopes: Check `repo` and `workflow`
5. Click **Generate token** and copy it (you'll need it later)

---

## 🏗️ Part 2: Set Up Azure DevOps

### Step 2.1: Create an Azure DevOps Project

1. Sign in to your Azure DevOps organization: `https://dev.azure.com/<your-org>`
2. Click **+ New project**
3. **Project name**: `webMethodsIO_Integration` (or your preferred name)
4. **Visibility**: Private (recommended)
5. Click **Create**

### Step 2.2: Create GitHub Service Connection

1. Go to **Project Settings** (bottom left gear icon)
2. Select **Service connections**
3. Click **Create service connection**
4. Choose **GitHub**
5. Select **Personal access token (PAT)** as authentication method
6. Paste your GitHub PAT from Step 1.3
7. **Connection name**: `github` (must match pipelines)
8. Click **Save**

### Step 2.3: Create Variable Groups

Variable groups store credentials and configuration centrally.

#### Variable Group 1: `webMethodsIO_group`

1. Go to **Pipelines** → **Library** → **Variable groups**
2. Click **+ Variable group**
3. **Name**: `webMethodsIO_group`
4. Add variables:
   - `admin_password` (Secret) — webMethods.io admin password for Play/Build environment

5. Click **Save**

#### Variable Group 2: `github_group`

1. Click **+ Variable group**
2. **Name**: `github_group`
3. Add variables:
   - `gitOwner` (String) — Your GitHub username/organization
   - `repoName` (String) — Your project repo name (from Step 1.2)
   - `PAT` (Secret) — Your GitHub Personal Access Token
   - `devUser` (String) — Your GitHub username (for commits)
4. Click **Save**

#### Variable Group 3: `azure_group` (Optional but Recommended)

1. Click **+ Variable group**
2. **Name**: `azure_group`
3. Add variables:
   - `AZURE_VAULT_NAME` (String) — Your Azure Key Vault name (if using)
   - `AZURE_RESOURCE_GROUP` (String) — Your Azure resource group
   - `AZURE_LOCATION` (String) — Azure region (e.g., `westeurope`)
   - `AZURE_TENANT_ID` (Secret) — Your Azure AD tenant ID
   - `AZURE_CLIENT_ID` (Secret) — Service Principal app ID
   - `AZURE_CLIENT_SECRET` (Secret) — Service Principal password
   - `AZURE_ACCESS_OBJECT_ID` (String) — Service Principal object ID
   - `AZURE_TOKEN` (Secret) — Azure DevOps Personal Access Token
4. Click **Save**

If you don't have Azure Key Vault, skip this for now and use GitHub Secrets (see Part 4).

---

## ⚙️ Part 3: Configure Your Project Repository

### Step 3.1: Update Configuration Files

In your local framework clone, update files in the `configs/` directory:

#### Update `configs/repo.yml`

```yaml
repo:
  user: "<your-github-username>"
  security_provider: "Azure"  # or "github" if not using Azure
```

#### Update `configs/env/play.yml` (or create if missing)

```yaml
tenant:
  hostname: "<your-play-environment-hostname>"  # e.g., "psdev.int-aws-de.webmethods.io"
  port: "443"
  admin_username: "<admin-username>"            # webMethods.io admin user
  type: "play"
```

#### Update `configs/env/dev.yml` (or create if missing)

```yaml
tenant:
  hostname: "<your-dev-environment-hostname>"   # e.g., "dev.int-az-eu.webmethods.io"
  port: "443"
  admin_username: "<admin-username>"
  type: "dev"
```

#### Create `configs/env/qa.yml` (Optional)

```yaml
tenant:
  hostname: "<your-qa-environment-hostname>"
  port: "443"
  admin_username: "<admin-username>"
  type: "qa"
```

#### Create `configs/env/prod.yml` (Optional)

```yaml
tenant:
  hostname: "<your-prod-environment-hostname>"
  port: "443"
  admin_username: "<admin-username>"
  type: "prod"
```

### Step 3.2: Add Sample Test Assets (Optional)

If you want to test with sample assets:

1. In `assets/workflows/`, add a sample workflow ZIP or JSON export
2. In `assets/flowservices/`, add a sample flowservice
3. In `resources/test/environments/`, add a Postman environment JSON for your test environment

For now, you can leave these directories empty or with placeholder files.

### Step 3.3: Commit Configuration Changes

```bash
git add configs/
git commit -m "Update configuration for project environments"
git push project main
```

---

## 🚀 Part 4: Import and Configure Pipelines

### Step 4.1: Import Pipelines from the Framework

1. In Azure DevOps, go to **Pipelines** → **Create Pipeline**
2. Select **GitHub** as source
3. Authorize and select your **webmethods-io-int-cicd** framework repository (from Step 1.1)
4. Choose **Existing Azure Pipelines YAML file**
5. Import each of these pipelines:
   - `pipelines/initialize_pipeline.yml`
   - `pipelines/synchronizeDEV_pipeline.yml`
   - `pipelines/sychronizeToQA_pipeline.yml` (optional)
   - `pipelines/sychronizeFeatureBranch_pipeline.yml`
   - `pipelines/InitiateTesting.yml` (optional)

For each pipeline:
- Rename the pipeline to something descriptive (e.g., "Initialize Project")
- Set **Trigger**: None (manual execution)
- Verify variable groups are linked

### Step 4.2: Verify Pipeline Configuration

For each imported pipeline, go to **Edit**:
1. Ensure the pool is set to `vmImage: ubuntu-latest` (Microsoft-hosted)
2. Verify variable groups appear in the YAML
3. Save

---

## 🔐 Part 5: Set Up Secrets

### Option A: Using Azure Key Vault (Recommended)

1. Create an Azure Key Vault (if you don't have one):
   ```bash
   az group create --name <resource-group> --location westeurope
   az keyvault create --resource-group <resource-group> --name <vault-name> --location westeurope --sku standard
   ```

2. Store the webMethods.io admin password:
   ```bash
   az keyvault secret set --vault-name <vault-name> --name "wmio-admin-password" --value "<password>"
   ```

3. Grant your Service Principal access:
   ```bash
   az keyvault set-policy --name <vault-name> \
     --object-id <service-principal-object-id> \
     --secret-permissions get list set delete
   ```

4. Update the `azure_group` variable group with your vault details (done in Part 2.3)

### Option B: Using GitHub Secrets (Simpler Alternative)

1. Go to your project repository on GitHub → **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Add:
   - `WMIO_ADMIN_PASSWORD` — webMethods.io admin password
   - Any other credentials your scripts need

Update `configs/repo.yml`:
```yaml
security_provider: "github"
```

---

## 🏃 Part 6: Run Your First Pipeline (Initialize Project)

### Step 6.1: Queue the Initialize Pipeline

1. Go to **Pipelines** → **Initialize Project** (or your chosen pipeline name)
2. Click **Run pipeline**
3. Enter parameters:
   - **repoName**: Your project name (must match `repoName` in `github_group`)
   - **featureBranchName**: `feature/initial-setup` (or your preferred name)
   - **synchProject**: `true` (to sync entire project)
   - **devUser**: Your GitHub username
4. Click **Run**

### Step 6.2: Monitor Pipeline Execution

1. Watch the pipeline run in real time
2. Check **Logs** for any errors
3. The pipeline will:
   - Initialize your GitHub project repository
   - Create required branches (`main`, `dev`, `qa`, your feature branch)
   - Create a project in webMethods.io Play/Build environment
   - Commit project configuration to your repo

### Step 6.3: Verify Success

After the pipeline completes:

1. Check your GitHub project repository — you should see:
   - New branches created
   - `project-config.yml` committed with project details
   - Assets directory structure

2. Check webMethods.io Play/Build environment — you should see:
   - New project created with your project name

---

## 📦 Part 7: Add Your First Asset

### Step 7.1: Develop in webMethods.io

1. Log into your webMethods.io Play/Build environment
2. Open the project created by the Initialize pipeline
3. Create or import a workflow or flowservice
4. Test it and save

### Step 7.2: Export Asset (Synchronize Feature Branch Pipeline)

1. Go to **Pipelines** → **Synchronize Feature Branch** (or similar name)
2. Click **Run pipeline**
3. Enter parameters:
   - **repoName**: Same as before
   - **featureBranchName**: Your feature branch name
   - **synchProject**: `false` (to sync only specific assets)
   - **assetIDList**: Asset IDs to export (optional; leave empty to export all)
   - **assetTypeList**: Asset types (`workflow`, `flowservice`, etc.)
   - **assetNameList**: Asset types (`SampleWorkFlow`, `SampleFlowservice`, etc.)
   - **devUser**: Your webMethods.io username
   - **includeAllReferenceData**: Add Reference Data
4. Click **Run**

The pipeline will:
- Export assets from webMethods.io
- Commit them to your feature branch in GitHub
- Create a Pull Request to `main` (if configured)

### Step 7.3: Review and Merge

1. Go to your GitHub project repository
2. Review the exported assets in your feature branch
3. Merge to `main` (or `dev` if your branching strategy requires)

---

## 🎯 Part 8: Promote to DEV Environment

### Step 8.1: Prepare DEV Environment

Ensure you have a DEV environment in webMethods.io and `configs/env/dev.yml` is configured (done in Part 3.1).

### Step 8.2: Run Synchronize DEV Pipeline

1. Go to **Pipelines** → **Synchronize DEV**
2. Click **Run pipeline**
3. Enter parameters:
   - **repoName**: Your project name
   - **synchProject**: `true` (to import entire project) or `false` (specific assets)
   - **assetIDList**: (if synchProject is false) Asset IDs to import
   - **assetTypeList**: (if synchProject is false) Asset types
   - **assetNameList**: Asset types (`SampleWorkFlow`, `SampleFlowservice`, etc.)
   - **devUser**: Your webMethods.io username
   - **projectHasAPIs**: `true` (project conatins Rest or Soap API's) or `false`
4. Click **Run**

The pipeline will:
- Checkout the `dev` branch from GitHub
- Create/verify the project in DEV environment
- Import assets with secret injection from Azure Key Vault or GitHub Secrets
- Trigger automated tests (if configured)

### Step 8.3: Verify in DEV

1. Log into your webMethods.io DEV environment
2. Verify the project and imported assets are present and working

---

## ✅ Troubleshooting

### Pipeline Fails: "Missing template parameter"
**Cause**: Variable not defined in variable group
**Solution**: 
1. Go to **Pipelines** → **Library** → **Variable groups**
2. Verify all required variables are present
3. Check variable names match exactly (case-sensitive)

### Pipeline Fails: "Project does not exist" or "Authentication failed"
**Cause**: Incorrect tenant hostname or credentials
**Solution**:
1. Verify `configs/env/play.yml` and `configs/env/dev.yml` have correct hostnames and ports
2. Test connectivity: 
   ```bash
   curl -u <admin>:<password> https://<hostname>:443/apis/v1/rest/projects
   ```
3. Check admin password in variable group

### Pipeline Fails: "Git authentication failed"
**Cause**: Invalid or expired GitHub PAT
**Solution**:
1. Regenerate GitHub PAT (Part 1.3)
2. Update in `github_group` variable group
3. Ensure PAT has `repo` and `workflow` scopes

### Pipeline Fails: "yq: command not found"
**Cause**: `yq` not installed on agent
**Solution**: 
- Pipelines will auto-install tools on `ubuntu-latest` agents
- If using custom agents, manually install: `sudo apt-get install -y jq curl perl` + download `yq`

---

## 📚 Next Steps

Once your first pipeline run succeeds:

1. **Promote to QA** (optional): Repeat Part 8 with QA environment
2. **Set up automated testing**: Configure Postman/Newman tests in `resources/test/`
3. **Enable code review**: Uncomment or enable `execute_codereview.yml` (requires IBM ISCCR license)
4. **Implement promotion workflow**: Create pull request triggers and approval gates
5. **Document your assets**: Add README files in `assets/` describing each asset

---

## 📖 Additional Resources

- **Full Setup Guide**: See `AZURE_DEVOPS_PIPELINE_SETUP.md` for detailed configuration
- **Framework Overview**: See `webmethods_framework_phase-1.md` for architecture and concepts
- **IBM webMethods API Docs**: https://www.ibm.com/docs/en/wm-integration/
- **Azure DevOps Documentation**: https://docs.microsoft.com/en-us/azure/devops/

---

## 🆘 Getting Help

If you encounter issues:

1. Check pipeline logs: **Pipelines** → **Runs** → Select run → **Logs**
2. Enable debug mode: Add `debug=true` parameter to pipeline runs (if supported)
3. Test scripts manually in a shell
4. Refer to script documentation in `pipelines/scripts/` directory
5. Check GitHub repository for issues: https://github.com/IBM/webmethods-io-int-cicd/issues

---

## 📝 Summary Checklist

- [ ] GitHub PAT generated (Part 1.3)
- [ ] Azure DevOps project created (Part 2.1)
- [ ] GitHub service connection created (Part 2.2)
- [ ] Variable groups created: `webMethodsIO_group`, `github_group`, `azure_group` (Part 2.3)
- [ ] Configuration files updated: `repo.yml`, `play.yml`, `dev.yml` (Part 3.1)
- [ ] Pipelines imported into Azure DevOps (Part 4.1)
- [ ] Secrets configured: Azure Key Vault OR GitHub Secrets (Part 5)
- [ ] Initialize pipeline run successful (Part 6)
- [ ] First asset exported to feature branch (Part 7)
- [ ] Asset promoted to DEV environment (Part 8)
- [ ] Verified in DEV environment (Part 8.3)

Once all items are checked, you have a working CI/CD pipeline for webMethods.io Integration! 🎉
