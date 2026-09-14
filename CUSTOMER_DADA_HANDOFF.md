# Customer DaDa Phase 1 handoff

## Objective

Complete backward-compatible imported-package support for both external-Git and internal-Git IwHI projects in the two CCEP repositories below. Do not commit or push.

## Repositories

1. Scripts and reusable plan fragments:
   `/Users/insrsa/Organize/Cx/Internal/PlatformArchitecture/Playground/GIT/Repos/CCEP_BITBUCKET/Master_EIP_IO/ccep-platformautomation`
2. Active Bamboo Specs:
   `/Users/insrsa/Organize/Cx/Internal/PlatformArchitecture/Playground/GIT/Repos/CCEP_BITBUCKET/AMATILIO/amatilio-platformautomation`
3. Reference implementation only:
   `/Users/insrsa/Organize/Cx/Internal/PlatformArchitecture/Playground/GIT/Repos/IBM Github/webmethods_io_int_cicd`

Only update active Specs. Never update files or plans containing `_Archived`.

## Agreed behaviour

- Initialize and Export must reconcile `project-config.yml`.
- Always write `.project.external-git.enabled` as `true` or `false`.
- When enabled, also write `repository`, `api-repository-path`, `branch`, and `account-alias`.
- When disabled, remove those four external-Git details.
- Remove legacy `.project.dada` metadata when reconciling.
- External-Git projects: copy product-owned scaffolding and `projectmapping.yml` verbatim. Never edit or synthesize either file.
- Internal-Git projects: do not create product scaffolding or `projectmapping.yml`.
- Internal-Git package metadata must be generated from the Configurations API in:
  `assets/dada/config/imported-package-metadata.yml`.
- Both modes must maintain:
  `assets/dada/config/imported-package-branches.yml`.
- Import packages before importing project assets.
- Package branch must be selected from the branch map for the target environment.
- Customer environment names are `development`, `qa`, `preprod`, and `production`.
- Common logic should match the Master design where possible; Bitbucket-specific repository access stays customer-specific.

## Naming rules

- Physical Bitbucket repository path:
  `scm/<projectKey>/<projectName>Project`
- IwHI API repository path requires the first project-name character and `Project` to be capitalized:
  `scm/<projectKey>/<CapitalizedProjectName>Project`
- Default external project branch is `development`.
- Repository names are effectively case-insensitive in Bitbucket, but the IwHI API path is case-sensitive in current product behaviour.

## Partial uncommitted changes already present

In `ccep-platformautomation`:

- `bamboo-specs/common/_EIP_Initialize_build_plan_tasks.yaml`
  - Project-config reconciliation now runs for both external and non-external projects.
  - It passes `externalGitEnabled` to the script.
- `scripts/io/saveExternalGitProjectConfig.sh`
  - Accepts `externalGitEnabled`.
  - Delegates YAML changes to the new shared helper.
  - Avoids claiming that an existing internal-Git project was converted.
- `scripts/io/updateProjectConfig.sh` is new.
  - Writes project identity and authoritative external-Git state.

Current status expected:

```text
 M bamboo-specs/common/_EIP_Initialize_build_plan_tasks.yaml
 M scripts/io/saveExternalGitProjectConfig.sh
?? scripts/io/updateProjectConfig.sh
```

In `amatilio-platformautomation`:

- `bamboo-specs/builds/common/_EIP_Initialize_build_plan_tasks.yaml`
  - Same active Initialize task-wiring adjustment.

Current status expected:

```text
 M bamboo-specs/builds/common/_EIP_Initialize_build_plan_tasks.yaml
```

Review these diffs before continuing; preserve them unless a defect is found.

## Remaining implementation

1. Adapt `scripts/io/exportDadaMetadata.sh` in `ccep-platformautomation` using the Master implementation as the behavioural reference while preserving the customer script signature.
2. Determine external-Git state in this order:
   - `.project.external-git.enabled` when present;
   - legacy `.project.dada.enabled` when present;
   - otherwise probe the conventional Bitbucket Project repository and product scaffolding.
3. For an old project with no conventional Project repository, classify it as internal-Git, not as an export failure.
4. For external-Git:
   - clone/read the Bitbucket Project repository and configured branch;
   - copy scaffolding and project mapping unchanged;
   - reconcile `project-config.yml` as enabled;
   - remove stale internal metadata;
   - generate/update the package branch map.
5. For internal-Git:
   - reconcile `project-config.yml` as disabled;
   - remove stale copied scaffolding/mapping from the automation repository;
   - generate `imported-package-metadata.yml` from Configurations API package data;
   - generate/update the package branch map.
6. If no imported packages exist, remove only imported-package metadata/map and stale scaffolding/mapping. Do not delete the whole `assets/dada` directory.
7. Adapt `scripts/io/importDadaPackages.sh` to read:
   - scaffolding for external-Git projects;
   - `imported-package-metadata.yml` for internal-Git projects.
8. Keep the package-import API payload and execution order identical to the proven Master implementation.
9. Review `scripts/io/updateImportedPackageBranchMap.sh`; retain deterministic environment ordering and prune mappings for packages no longer present.
10. Update only the active Export/Import Specs in both customer repositories if wiring changes are required.

## Bitbucket probing guidance

Use the existing customer Bitbucket credentials and host arguments. Prefer a Bitbucket REST check so these cases can be distinguished:

- repository/scaffolding exists: external-Git;
- repository or scaffolding returns 404: internal-Git;
- authentication, network, or server error: fail clearly instead of assuming internal-Git.

Do not infer external-Git merely because the conventional Project repository exists; initialization can create that repository for an internal-Git project.

## Verification

Run before handing back:

```bash
bash -n scripts/io/updateProjectConfig.sh
bash -n scripts/io/saveExternalGitProjectConfig.sh
bash -n scripts/io/exportDadaMetadata.sh
bash -n scripts/io/importDadaPackages.sh
bash -n scripts/io/updateImportedPackageBranchMap.sh
```

Then inspect both repositories with `git status --short` and `git diff --check`.

Test matrix in the customer Gen1 tenants:

1. New external-Git project: Initialize, Export, Import.
2. Existing external-Git project: Initialize and Export reconcile metadata without changing product scaffolding.
3. New internal-Git project with an imported package: Export creates internal metadata and branch map; Import installs the package first.
4. Old internal-Git project lacking external-Git metadata: Export enriches `project-config.yml` with `enabled: false` and succeeds.
5. Project with no imported packages: existing non-package DaDa assets are preserved.

## Safety constraints

- No functional changes to Master during this customer test cycle.
- No commits, pushes, tags, releases, or external mutations.
- Preserve existing non-external-Git behaviour.
- Keep secrets out of logs, including debug/trace output.
