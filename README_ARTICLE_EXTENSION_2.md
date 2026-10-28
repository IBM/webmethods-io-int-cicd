# 🚀 webMethods.io Integration DevOps Framework — Extension 2: DADA and Gen1/Gen2 Support

By Srinivasan Sabapathy

This article continues the [original DevOps framework for webMethods.io Integration](https://community.ibm.com/community/user/integration/viewdocument/devops-for-webmethodsio-integratio?CommunityKey=82b75916-ed06-4a13-8eb6-0190da9f1bfa&tab=librarydocuments) and the [first extension covering APIs, multi-asset promotion, code review, and vault integration](https://community.ibm.com/community/user/viewdocument/webmethodsio-integration-devops-fr?CommunityKey=82b75916-ed06-4a13-8eb6-0190da9f1bfa&tab=librarydocuments).

As customers gradually move towards Gen2, their environments may include both Gen1 and Gen2 tenants. This extension adds generation-aware authentication so the same automation scripts can support both. Environment configuration selects the tenant generation, and a shared HTTP wrapper handles Basic Auth for Gen1 or instance API key authentication for Gen2. Teams can adopt Gen2 incrementally while continuing to use their Gen1 environments.

The extension also introduces Develop Anywhere, Deploy Anywhere (DADA) Phase 1 support, including external-Git project initialization and imported custom-package promotion. Projects can depend on packages and product-managed Git configuration as well as exported integration assets; the framework brings that additional context into the promotion process.

The common framework uses GitHub and Azure DevOps as its reference setup and can be adapted to customer platforms such as Bitbucket and Bamboo.

---

## 📌 What's New

- ✅ **DADA Phase 1 — External-Git Project Support**  
  Initialize a project with an external Git repository and an existing Git connection alias belonging to the initiating webMethods user. The product-connected project repository is separate from the automation repository.

- ✅ **Imported Custom-Package Support**  
  Export imported-package metadata and import the required packages before the integration assets that depend on them.

- ✅ **Internal-Git and External-Git Project Handling**  
  Preserve product-owned scaffolding and project mapping for external-Git projects. For internal-Git projects, capture package metadata through product APIs without creating external-Git scaffolding.

- ✅ **Environment-Specific Package Branches**  
  Maintain package branch mappings for destination environments, allowing teams to review and control which package branch each promotion uses.

- ✅ **Gen1 and Gen2 Authentication Support**  
  Use a shared curl wrapper to select authentication for tenant requests. Gen1 retains Basic Auth; Gen2 uses the secret instance API key through the `x-instance-api-key` header. Requests to other services retain their original authentication.

- ✅ **Gradual Gen2 Adoption**  
  Select the generation per environment, with Gen1 as the default when the setting is omitted. Existing Gen1 configurations can continue while teams configure individual environments for Gen2.

- ✅ **Promotion and Export Fixes**  
  Improve REST/SOAP API import response handling, propagate SOAP import failures, and detect API exports before explicit project creation. Additional configuration-export fixes validate responses, preserve valid exports, and handle empty package configuration and package-API fallback.

---

## 📈 Extended Promotion Flow

1. **Initialize** — Prepare the project and its Git connection where external Git is enabled.
2. **Export and Review** — Capture integration assets, package metadata, and environment-specific package branch mappings for version control and review.
3. **Promote** — Prepare the destination, import custom packages, and then import the dependent integration assets using the destination tenant's authentication scheme.
4. **Validate** — Run the configured checks and confirm the deployed assets and package dependencies behave as expected.

Vault integration, connection configuration, and the existing asset-promotion capabilities continue to form the foundation of this workflow. DADA adds package and Git context; generation-aware authentication adapts tenant access as environments evolve.

---

## 📘 Resources

- [Framework repository](https://github.com/IBM/webmethods-io-int-cicd)
- [First framework extension](https://community.ibm.com/community/user/viewdocument/webmethodsio-integration-devops-fr?CommunityKey=82b75916-ed06-4a13-8eb6-0190da9f1bfa&tab=librarydocuments)
- [Original DevOps framework](https://community.ibm.com/community/user/integration/viewdocument/devops-for-webmethodsio-integratio?CommunityKey=82b75916-ed06-4a13-8eb6-0190da9f1bfa&tab=librarydocuments)
