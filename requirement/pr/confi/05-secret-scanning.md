# Confi PR 05: Automated secret scanning

Depends on: Confi PR 01

## Objective

Prevent credentials from entering Git, builds, logs, test artifacts, and
deployment configuration.

## Work

- Add pre-commit and CI secret scanning with reviewed rules and allowlist.
- Scan tracked content, relevant Git history, generated artifacts, container
  build context, Render configuration, and sanitized test/log evidence.
- Detect private keys, provider tokens, OAuth secrets, database URLs,
  authorization headers, SMTP credentials, and project-specific known formats.
- Treat a detection as a security event requiring rotation, not merely deletion
  from the latest commit.
- Add `.gitignore` coverage for `.env`, OAuth token/code files, local Google
  credentials, database dumps, recovery codes, and test artifacts.
- Keep scanner output redacted and avoid uploading repository content to an
  unapproved external scanner.

## Acceptance

- CI blocks seeded test-secret fixtures that match protected patterns.
- Approved dummy fixtures remain clearly synthetic and narrowly allowlisted.
- Current repositories and build contexts pass.
- Detection/rotation/runbook path is tested without revealing the fixture.

## Out of scope

Treating scanning as a substitute for rotation or secret-manager controls.

