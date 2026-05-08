CI setup for infra
==================

This folder contains a GitHub Actions workflow that builds the platform by checking out the other repositories (contracts, services, apps) and building them.

Configuration steps
1. Create GitHub repositories for each project: `contracts-repo`, `services-repo`, `apps-repo`, and `infra` (if not already).
2. In the `infra` repository settings, add a repository secret named `PERSONAL_ACCESS_TOKEN` containing a personal access token (PAT) with `repo` read access to the other repos (if they are private). If all repos are under the same owner and the workflow has access, you may use the default `GITHUB_TOKEN` by modifying the workflow.
3. Edit `.github/workflows/ci.yml` and set the `CONTRACTS_REPO`, `SERVICES_REPO`, and `APPS_REPO` environment variables to the full repository names (e.g. `your-org/contracts-repo`).

How it works
- The workflow checks out `infra` (the current repo) then checks out the other repos into `contracts-repo`, `services-repo`, and `apps-repo` subdirectories.
- It sets up Go and builds the contracts package, user service, agent, chat client, and web UI, placing binaries under `infra/bin` and uploading them as artifacts.

Notes
- For private repos the PAT secret must have access; for public repos you can use the default `GITHUB_TOKEN` or no token.
- You can extend the workflow to run tests, publish Docker images, or deploy artifacts.
