# DevOps for webMethods.IO Integration

    This article shows how to design and setup an automated CI/CD process and framework for webMethods.io 
    using the inbuilt APIs (or CLI). Here we have used Azure DevOps as our orchestration platform, 
    GitHub as repository platform and Postman/Newman as test framework. 

# Use-case
When organizations start using webMethods.io Integration for business use-cases, the need for having a continuous integration and delivery process becomes very important. These processes will enable the business to have a "Faster release rate", "More Test reliability" & "Faster to Market".

This use-case will highlight a solution utilizing webMethods.io import & export APIs (or CLI) and Azure Devops to extract and store the code assets in repository (GitHub). By integrating repository workflows and azure pipelines, this process will automate the promotion of assets to different stages/environment as per the organizations promotion workflow. This will also showcase how to automate the test framework for respective stages/environments.

![](./images/markdown/delivery.png)  ![](./images/markdown/overview.png)

The automation around webMethods.io Integration APIs have been implemented using scripts, which will make customization easier if the organization chooses to adopt an alternative orchestration platform.

# Assumptions / Scope / Prerequisite
1. 4 Environments: Play/build, Dev, QA & Prod. 
2. Azure DevOps as Orchestration Platform
3. GitHub: as the code repository
4. GitHub Enterprise: For Pipelines/Scripts
5. Postman/Newman as test framework

# Git Workflow
We will assume that the organization is following the below GIT Workflows.

![](./images/markdown/SingleFeature.png)    ![](./images/markdown/MultiFeature.png)

# Steps
1. **Initialize**
   1. Developer starts by executing *Initialize Pipeline* (Automation)
   2. This checks if the request is for an existing asset or a new implementation
   3. If new, automation will 
      1. Initialize a repository
      2. Create standardized branches, including requested Feature Branch
      3. Create a project in Play/Build environment
   4. If existing, automation will
      1. Clone the Prod branch to Feature branch
      2. Import asset to Play/Build environment

![](./images/markdown/Initialize.png)

   &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;**API's Used** 
   *  /projects/{{*projectName*}}, 
   *  /projects/{{*projectName*}}/workflow-import, 
   *  /projects/{{*projectName*}}/flow-import, 
   *  /ut-flow/referencedata/{{*projectUID*}}/{{*referenceDataName*}}, 
   *  /ut-flow/referencedata/create/{{*projectUID*}}, 
   *  /ut-flow/referencedata/update/{{*projectUID*}}/{{*referenceDataName*}}, 
   *  /projects/{{*projectName*}}/params/{{*parameterUID*}}, 
   *  /projects/{{*projectName*}}/params
<br> 
<br> 
<br> 


2. **Develop & Commit**
   1. Developer starts developing
   2. After completion they will execute synchronizeToFeature Pipeline (Automation)
   3. Automation will 
      1. Export the asset
      2. Commit the asset to Feature Branch

![](,/../images/markdown/synchronizeToFeature.png)

   &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;**API's Used**
   * /projects/{{*projectName*}}/workflows/{{*assetID*}}/export, 
   * /projects/{{*projectName*}}/flows/{{*assetID*}}/export, 
   * /projects/{{*projectName*}}/assets, 
   * /projects/{{*projectName*}}/accounts, 
   * /ut-flow/referencedata/{{*projectUID*}}, 
   * /ut-flow/referencedata/{{*projectUID*}}/{{*referenceDataName*}}, 
   * /projects/{{*projectName*}}/params/{{*parameterUID*}}, 
   * /projects/{{*projectName*}}/params
<br> 
<br> 
<br> 

3. **Deliver / Promote to DEV**
   1. Once the implementation is finished, developer manually creates a Pull Request from Feature Branch to DEV
   2. This will trigger the synchronizeToDev pipeline (Automation)
   3. Automation will 
      1. Checkout the DEV branch
      2. Import the asset to DEV environment
      3. And then kicks off automated test for the associated project/repo with data/assertions specific to DEV
   4. On failure, developer needs to fix/re-develop the asset (Step 2).

![](./images/markdown/synchronizeToDev.png)

   &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;**API's Used** 
   *  /projects/{{*projectName*}}, 
   *  /projects/{{*projectName*}}/workflow-import, 
   *  /projects/{{*projectName*}}/flow-import, 
   *  /ut-flow/referencedata/{{*projectUID*}}/{{*referenceDataName*}}, 
   *  /ut-flow/referencedata/create/{{*projectUID*}}, 
   *  /ut-flow/referencedata/update/{{*projectUID*}}/{{*referenceDataName*}}, 
   *  /projects/{{*projectName*}}/params/{{*parameterUID*}}, 
   *  /projects/{{*projectName*}}/params
   *  /projects/{{*projectName*}}/workflows/{{*assetID*}}/run
   *  /projects/{{*projectName*}}/flows/{{*assetName*}}/run
<br> 
<br> 
<br> 

4. **Deliver / Promote to QA**
   1. After Dev cycle is complete, developer manually creates a Pull Request from Feature Branch to QA.  
   2. This will trigger the synchronizeToQA pipeline (Automation)
   3. Automation will 
      1. Checkout the QA branch
      2. Import the asset to QA environment
      3. And then kicks off automated test for the associated project/repo with data/assertions specific to QA
   4. On failure, developer needs to fix/re-develop the asset (Step 2).

![](./images/markdown/synchronizeToQA.png)

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;**API's Used:** ***SAME AS STEP 3***
<br> 
<br> 
<br> 

5. **Deliver / Promote to PROD**
   1. Once the automated test and UAT is successfully finished, developer manually creates a Pull Request from Feature Branch to PROD.  PROD deployment may have different approval cycle.
   2. Respective operations team will manually trigger the synchronizeToPROD pipeline (Automation)
   3. Automation will 
      1. Checkout the PROD branch
      2. Create a release
      3. Import the asset to PROD environment
      4. And then kicks off automated Smoke test, if any for PROD.
   4. On failure, developer needs to fix/re-develop the asset (Step 2). And release will be rolled back.

![](./images/markdown/synchronizeToPROD.png)

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;**API's Used:** ***SAME AS STEP 3***
<br> 
<br> 
<br> 

# Downloads / Assets / References
1. Repository for automation, scripts & sample assets. Github: https://github.com/IBM/webmethods-io-int-cicd
2. Presentation: https://github.com/IBM/webmethods-io-int-cicd/blob/main/presentation/webMethodsIO_Integration_CICD.pptx 
3. Demo recording: 
4. API Documentation: https://www.ibm.com/docs/en/wm-integration/11.0.11?topic=reference-webmethods-integration-apis
5. CLI Repository: https://github.com/SoftwareAG/webmethods-io-integration-apicli (Being Migrated)

# Next Steps
1. Incorporate design for Hybrid use-case
2. Extend testing framework
3. Incorporate design for code review

## Azure DevOps Pipeline Setup

A comprehensive setup guide with step-by-step instructions, variable group configuration, agent pool setup (Microsoft-hosted), pipeline workflows, scripts overview, and troubleshooting is available. Use the guide to configure Azure Pipelines, variable groups, secrets (Azure Key Vault or GitHub), and to understand how the provided scripts in `pipelines/scripts/` are used by each YAML pipeline.


## End-to-End Setup Guide

For a complete step-by-step walkthrough from scratch, including GitHub repository setup, Azure DevOps project creation, variable group configuration, secrets management, pipeline import, and your first pipeline run, refer to the comprehensive setup guide.

**📖 Complete Setup:** [End-to-End Setup Guide](./SETUP_GUIDE.md)

## How to use/test
1. Clone / Fork the automation repo
2. Adjust the environment configs
3. Configure your Azure DevOps tenant 
   1. Create Project 
   2. Link automation repo to get the pipelines
   3. In project settings, create Service Connections for Automation repository and Code Repository
4. Start the "*Initialize*" pipeline
5. Check that the respective repo and webMethods.io project is created
6. Import sample assets from automation repo
7. Start "*synchronizeToFeature*" pipeline
8. Check whether new assets have been committed to feature branch
9. Adjust the test cases for each environment from automation repo and commit it code repo feature branch created above. *Note: Follow the folder structure documented*
10. Create a Pull Request in code repository from Feature Branch to DEV
11. Start "*synchronizeToDev*" pipeline. (This has been automated for Github, please refer to Github automation document).
12. Check code has been Imported/Promoted to Dev environment
13. Check whether Test has been automatically triggered.

# Useful links   

📘 Explore the Knowledge Base    
Dive into a wealth of webMethods tutorials and articles in our [Tech Community Knowledge Base](https://community.ibm.com/community/user/integration/communities/community-home/all-news?communitykey=82b75916-ed06-4a13-8eb6-0190da9f1bfa&LibraryFolderKey=&DefaultView=&8e5b3238-cf51-4036-aa29-601a6cd3e1b3=eyJ2aWV3dHlwZSI6ImNhcmQifQ%3D%3D).  

💡 Get Expert Answers    
Stuck or just curious? Ask the webMethods experts directly on our [Forum](https://community.ibm.com/community/user/integration/communities/community-home?communitykey=82b75916-ed06-4a13-8eb6-0190da9f1bfa).  

🚀 Try webMethods    
See webMethods in action with a [Free Trial IPaaS](https://www.ibm.com/products/webmethods-integration).[Free Trial On Premise](https://community.ibm.com/community/user/integration/viewdocument/guide-to-downloading-and-installing?CommunityKey=82b75916-ed06-4a13-8eb6-0190da9f1bfa&tab=librarydocuments).  


More to discover
* [DevOps for webMethods.io Integration](https://community.ibm.com/community/user/integration/viewdocument/devops-for-webmethodsio-integratio?CommunityKey=82b75916-ed06-4a13-8eb6-0190da9f1bfa&tab=librarydocuments)
* [webMethods DevOps](https://tech.forums.softwareag.com/t/recording-webmethods-virtual-meetup-may-19th-2023-webmethods-devops/278975)  

# Contribution

## How to Contribute
This is an open-source project and requires community contributions to remain useful. Anyone can contribute to the project in the following ways:
1. Fork this repository.
2. Make your enhancements/ changes.
3. Create a Pull Request.
4. Finally, development team will evaluate the Pull Request and merge it to the source code.

## Raising Issues / Bugs

In case of Bugs, please create an issue with following details
1. Version
2. Detailed description (with images if needed)
3. Error stacktace (log snippets)

# Disclaimer
## IBM Public Repository Disclosure
All content in these repositories including code has been provided by IBM under the associated open source software license and IBM is under no obligation to provide enhancements, updates, or support. IBM developers produced this code as an open source project (not as an IBM product), and IBM makes no assertions as to the level of quality nor security, and will not be maintaining this code going forward.
