# webMethods.io Integration DevOps Framework — Extension 2: DADA and Gen1/Gen2 Tenant Support


By Srinivasan Sabapathy

## Continuing the framework

The [original DevOps framework](https://community.ibm.com/community/user/integration/viewdocument/devops-for-webmethodsio-integratio?CommunityKey=82b75916-ed06-4a13-8eb6-0190da9f1bfa&tab=librarydocuments) introduced a reusable approach to automating the lifecycle of webMethods.io Integration assets. The [first extension, published in July 2025](https://community.ibm.com/community/user/viewdocument/webmethodsio-integration-devops-fr?CommunityKey=82b75916-ed06-4a13-8eb6-0190da9f1bfa&tab=librarydocuments), added broader asset promotion, connection configuration, vault integration, and a flow-service code review option.

As customers gradually move towards Gen2, their deployment environments may include both Gen1 and Gen2 tenants. The framework adds generation-aware authentication so the same automation scripts can serve both: Basic Auth for Gen1 and instance API key authentication for Gen2. Environment configuration selects the tenant generation, while a shared HTTP wrapper applies the corresponding authentication to tenant requests. This lets teams adopt Gen2 incrementally while retaining their existing Gen1 automation.

This second extension addresses the next deployment concern: a project can depend on custom packages and product-managed Git configuration as well as its exported integration assets. Promoting only the assets leaves part of that project's deployment context behind.

The framework now includes initial Develop Anywhere, Deploy Anywhere (DADA) support: initialization with external Git, export of package metadata, environment-specific package branch selection, and package import before dependent project assets. Existing projects using internal Git also have a package-metadata path.

The reference implementation remains available in the [IBM framework repository](https://github.com/IBM/webmethods-io-int-cicd). Its purpose is to provide a common starting point that teams can adapt to their source-control, pipeline, and secret-management platforms.

## What this extension adds

| Area | Addition |
| --- | --- |
| DADA Phase 1 | External-Git initialization and imported custom packages |
| Project metadata | Separate internal-Git and external-Git export paths |
| Package promotion | Target-environment branch mapping and dependency-first import |
| Gen1/Gen2 tenants | Shared authentication wrapper and generation-aware pipeline configuration |

The release brings together two related concerns: preserving the project's package and Git context, and adapting automation to the destination tenant generation. External Git and DADA are not substitutes for tenant authentication support.

## Why package-aware promotion matters

Consider an integration project that uses a shared custom package. Exporting its workflows or flow services does not, by itself, ensure that the corresponding package is installed in the destination project. A release needs to identify the package and choose the appropriate source branch for the destination environment.

The practical deployment sequence becomes:

1. Prepare the destination project.
2. Read the exported package metadata and target-environment branch mappings.
3. Import the required custom packages.
4. Import the integration assets that depend on those packages.
5. Apply the applicable environment configuration and run the configured validation steps.

This makes package dependencies part of the release review. A team can examine which package branches a deployment will use alongside the changes to the integration assets.

## Two Git responsibilities

The automation repository and the product-connected project repository serve different purposes.

| Repository | Responsibility |
| --- | --- |
| Automation repository | Exported assets, deployment configuration, and package promotion metadata |
| Product-connected project repository | Product-managed project content and scaffolding for an external-Git project |

The initialization convention derives a separate `<projectName>Project` repository for the product connection. Keeping that relationship explicit helps teams distinguish the configuration used by the deployment pipeline from the content managed through the product's Git integration.

External-Git initialization requires an accessible repository and an existing Git connection alias belonging to the initiating webMethods user. The pipeline does not replace that onboarding step by creating a shared alias. Repository preparation and connection permissions should be checked before initialization.

## Supporting external-Git and internal-Git projects

The framework records the project mode in `project-config.yml`, using `project.external-git.enabled`.

For external-Git projects, export preserves the product-owned scaffolding and `projectmapping.yml` rather than reconstructing them. These files describe product-managed relationships and should remain faithful to their source.

For internal-Git projects, the framework obtains imported-package information through the project Configurations API and writes a separate metadata file. It does not manufacture external-Git scaffolding for an internal-Git project.

| Exported information | External Git | Internal Git |
| --- | --- | --- |
| Project mode | Recorded explicitly | Recorded explicitly |
| Product scaffolding and project mapping | Copied from the connected repository | Not generated |
| Imported-package source | Product scaffolding | Configurations API metadata |
| Environment-specific package branch map | Maintained | Maintained |

This distinction allows the pipeline to handle projects without requiring every project to adopt external Git. Recording a mode in configuration does not convert an existing project between Git modes.

## Package branches as deployment configuration

The export flow maintains `assets/dada/config/imported-package-branches.yml`. For internal-Git projects, package metadata is stored in `assets/dada/config/imported-package-metadata.yml`; external-Git projects use the copied scaffolding under `assets/dada/config/scaffolding`.

The branch map separates the package branch used in a destination environment from the branch recorded in source metadata. Before promotion, teams should review the map and confirm that the selected branches correspond to their release policy.

Branch selection is not an immutable release identifier. Teams that require reproducible releases should also define how those branches are protected and how the exact deployed package revision is recorded.

## How the pipeline fits together

The reference implementation separates the main responsibilities into reusable scripts:

| Script | Responsibility |
| --- | --- |
| `prepareExternalGitProject.sh` | Prepare external-Git project initialization |
| `exportDadaMetadata.sh` | Reconcile project mode and export package metadata |
| `updateImportedPackageBranchMap.sh` | Maintain package branches for configured environments |
| `importDadaPackages.sh` | Import packages before the regular asset import |

This extends the existing export, review, and promotion workflow. The package steps add deployment context while the existing secret-management and asset-promotion mechanisms continue to serve their respective roles.

For older projects, missing external-Git configuration needs careful handling. An existing repository name alone does not prove that the project uses external Git. Where mode information is absent, the export logic checks for product scaffolding. Authentication or network failures must surface as errors rather than being interpreted as proof that the project uses internal Git.

## Adapting the common framework

The IBM repository is a reusable reference implementation. Customer adaptations can replace the orchestration and repository integration while preserving the core deployment responsibilities: identify project mode, preserve product-owned metadata, choose package branches explicitly, and install dependencies before importing assets.

For example, a team using Bitbucket and Bamboo needs repository access and pipeline bindings appropriate to those platforms. This does not require a different package-promotion model. It requires a deliberate adaptation of the common workflow to the team's environment.

## Adoption and validation

Before using the extension in a release pipeline, validate a new external-Git project, an existing external-Git project, an internal-Git project with imported packages, an older project without explicit mode metadata, and a project with no imported packages.

For each applicable case, verify the exported metadata, destination branch selection, import order, and the behavior of dependent assets after deployment. A project without packages should not lose unrelated DADA content during metadata reconciliation.

Keep connection credentials in the configured secret provider and review pipeline logging so credentials are not exposed. Product API authentication and access to the connected Git repository are separate concerns and need their own configuration.

## Gen1 and Gen2 tenant support

The second feature area is support for deployment environments spanning Gen1 and Gen2 tenants. Teams need a consistent promotion process while configuring authentication and API access for each destination tenant.

The intended deployment model keeps tenant-specific access configuration separate from exported integration assets. The pipeline should identify the destination tenant, obtain the required credentials from its configured secret provider, and use the appropriate authentication consistently for project discovery, creation, asset export/import, and imported-package operations.

### Shared HTTP authentication

The Gen1/Gen2 extension introduces `pipelines/scripts/http/curl`, a shared wrapper selected by placing its directory before the system curl in `PATH`. Existing scripts continue to call curl; authentication selection is centralized.

| Configuration | Behavior |
| --- | --- |
| `TENANT_GENERATION=gen1`, or omitted | Preserve original arguments, including Basic Auth |
| `TENANT_GENERATION=gen2` | For requests matching `IWHI_BASE_URL`, remove Basic Auth and add `x-instance-api-key` from the secret `INSTANCE_API_KEY` |
| Non-tenant URL | Preserve original request arguments |
| Unsupported generation or missing Gen2 key | Fail before sending the applicable request |

Pipelines read `.tenant.generation`, defaulting to `gen1`, export `TENANT_GENERATION` and `IWHI_BASE_URL`, and prepend the wrapper directory to `PATH`. Initialization, runtime registration, feature export, DEV import, and QA import include this wiring.

Set `tenant.generation: gen2` in the appropriate environment YAML. Keep the API key in a secret pipeline variable: DEV import maps `dev_instance_api_key` to `INSTANCE_API_KEY`, with corresponding bindings for other configured environments. Direct script callers must set up the wrapper path and environment variables too; the scripts alone do not activate generation selection.

API imports accept success responses using either `.output.message` or `.output.status`.

Nine offline tests pass, covering authentication selection, missing keys, invalid generations, non-tenant requests, pipeline wiring, and API response handling. These use a fake curl and source assertions; live tenant validation remains a separate release check.

## Releases and tags

This section is for repository users and can be omitted when publishing the community article. The technical content above describes both extensions; select the release appropriate to your environment.

| Technical release | Source branch | Scope | Public release |
| --- | --- | --- | --- |
| `2026.10-dada` | `main` | DADA Phase 1 and imported-package promotion with the existing Gen1 authentication path | [DADA Phase 1](https://github.com/IBM/webmethods-io-int-cicd/releases/tag/2026.10-dada) |
| `2026.10-gen1-gen2` | `feature/gen1-gen2-support` | DADA plus generation-aware Gen1/Gen2 authentication and additional export fixes | [DADA + Gen1/Gen2](https://github.com/IBM/webmethods-io-int-cicd/releases/tag/2026.10-gen1-gen2) |

Release links become available after the tags and GitHub releases are published. These are separate snapshots, not a merge of the two branch tips. The Gen1/Gen2 snapshot adds configuration-response validation, configuration reuse, empty-package normalization, and package-API fallback during metadata export. The main snapshot uses a dedicated `prepareImportProject.sh` helper; the Gen1/Gen2 snapshot handles API-export detection in its import pipelines.

Local validation is offline and does not establish live tenant deployment or universal cross-generation asset compatibility. Configure and validate the selected release against your own tenants before adoption.

## Resources

- [IBM framework repository](https://github.com/IBM/webmethods-io-int-cicd)
- [First extension: vault, APIs, and multi-asset promotion](https://community.ibm.com/community/user/viewdocument/webmethodsio-integration-devops-fr?CommunityKey=82b75916-ed06-4a13-8eb6-0190da9f1bfa&tab=librarydocuments)
- [Original DevOps framework](https://community.ibm.com/community/user/integration/viewdocument/devops-for-webmethodsio-integratio?CommunityKey=82b75916-ed06-4a13-8eb6-0190da9f1bfa&tab=librarydocuments)

