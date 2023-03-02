# DevOps for webMethods.IO Integration

    This article shows how to design and setup an automated CI/CD process and framework for webMethods IO using the inbuilt APIs (or CLI). Here we have used Azure DevOps as our orchestration platform, GitHub as repository platform and Postman/Newman as test framework. 

# Use-case
When organization start using webMethods.io Integration for business use-cases, the need of having a continuous integration and delivery  process becomes very important. Which will ensure the business to have "Faster release rate", "More Test reliability" & "Faster to Market".

This use-case will highlight a solution using import & export APIs (or CLI) and Azure Devops to extract and store the code assets in repository (GitHub). And by integrating repository workflows and azure pipelines, will automate the promotion of assets to different stages/environment as per organizations promotion workflow. This will also showcase how to automate the test framework for respective stages/environments.

![](./images/markdown/delivery.png)  ![](./images/markdown/overview.png)

The automation around webMethods.io Integration APIs are all done as scripts, which will make it easier to adopt any Orchestration platform of the choice.

# Assumptions / Scope / Prerequisite
1. 4 Environments: Play/build, Dev, QA & Prod. 
2. Azure DevOps as Orchestration Platform
3. GitHub: For code repository
4. GitHub Enterprise: For Pipelines/Scripts
5. Postman/Newman as test framework.

# Git Workflow
We will assume that, organization is following the below GIT Workflows.
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

2. **Develop & Commit**


# Downloads / Assets


## How to use/test


