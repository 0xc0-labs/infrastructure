# argocd

Argo CD, installed by RKE2's helm-controller from a `HelmChart` this role
writes into the servers' manifests directory. The interface is
`meta/argument_specs.yml`; the chart's values are `argocd_values` in
`vars/main.yml`.

## Signing in

The UI is at `https://argocd.int.0xc0.cc`, over WARP only.

- **People**: choose "Log in via Cloudflare Access" and are administrators
  (`role:admin`). Cloudflare Access is the OIDC provider (`oidc.config`); its
  application for Argo CD admits only the team `0xc0-labs/admins` and the
  operator's emails, so every user that signs in is an admin and admission is
  decided there, once. `argocd login --sso` works too, through
  `http://localhost:8085/auth/callback`. Dex is off.
- **Break-glass**: the local `admin` account stays enabled, with the password
  from Vault (`platform/argocd/admin`, `password_bcrypt`).

## The OIDC client's secret

The client ID and secret of Cloudflare's application for Argo CD (callback
`https://argocd.int.0xc0.cc/auth/callback`) live in Vault at
`platform/argocd/oidc`, keys `client_id` and `client_secret`. gitops delivers
them as the Secret `argocd-oidc` in the namespace `argocd`, labelled
`app.kubernetes.io/part-of: argocd`, which is the only kind of Secret Argo CD
resolves `$<secret>:<key>` from in `oidc.config`. Nothing in this repo holds
either value. Writing them is in `vault`'s README.
