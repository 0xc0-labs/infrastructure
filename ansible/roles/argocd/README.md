# argocd

Argo CD, installed by RKE2's helm-controller from a `HelmChart` this role
writes into the servers' manifests directory. The interface is
`meta/argument_specs.yml`; the chart's values are `argocd_values` in
`vars/main.yml`.

## Signing in

The UI is at `https://argocd.int.0xc0.cc`, over WARP only.

- **Admins**: members of the GitHub team `0xc0-labs/admins` choose "Log in
  via GitHub" and are administrators (`role:admin`). Dex, the chart's, is
  the connector; RBAC maps the team `0xc0-labs:admins` to the role. The
  default policy is empty, so a GitHub user outside the team gets nothing.
- **Break-glass**: the local `admin` account stays enabled, with the password
  from Vault (`platform/argocd/admin`, `password_bcrypt`).

## The OAuth App's secret

The client ID and secret of the GitHub OAuth App (callback
`https://argocd.int.0xc0.cc/api/dex/callback`) live in Vault at
`platform/argocd/github-oauth`, keys `client_id` and `client_secret`. gitops
delivers them as the Secret `argocd-github-oauth` in the namespace `argocd`,
labelled `app.kubernetes.io/part-of: argocd`, which is the only kind of Secret
Argo CD resolves `$<secret>:<key>` from in `dex.config`. Nothing in this
repo holds either value. Writing them is in `vault`'s README.
