# Deployment repository instructions

Manage Azure infrastructure declaratively with Terraform, including Entra identities, RBAC, sign-in settings, firewall rules, storage, and SQL access. Do not add Azure CLI/PowerShell/Bash infrastructure mutation scripts or local-exec provisioners. CLI login, read-only diagnostics, application package deployment, schema migrations, and data restore are separate operational tasks.

Preserve the reviewed free tiers and exact-IP SQL firewall scope. No paid-tier fallback, broad AllowAzureServices rule, or subscription-wide grant for the GitHub deployment identity. Run broader identity/RBAC/budget stacks as the owner.

Keep recipient addresses, client secret values, financial backups, private variable files, state, and plans out of Git and public logs. Bootstrap uses private local state to avoid a state-storage dependency cycle; other stacks use the existing private AzureAD-authenticated Blob backend. Back up all states privately before destructive work. Preserve live financial data; never destroy resources simply to test rebuilding.
