# Vault as a GCP Broker Laboratory

The purpose of this lab is to show how we can use Vault acting as a broker to
manage GCP service accounts. We are going to use Terraform to keep the
configuration. It gives more visibility on our infrastrucutre and makes the
change management process clearer. Since we can have all the TF configuration
versioned in the VCS, changes can be rolled out through the CI/CD pipelines upon
aprovemnts. It also increases the visibility of the security definitions such as
existing roles and policies.

Before we proceed notice that I'll run Vault locally in dev mode to make this lab
more interactive. I'll also run the Terraform config and keep the state locally.
It's out of the scope of this guide to show how things should work in production.

## Run Vault

```bash
$ docker run --cap-add=IPC_LOCK --rm -it \
-p 8200:8200 \
-e ADV_HOST=127.0.0.1 \
vault
```

We are intentionally leaving the process run in foreground so we can easily
copy the root token and follow the logs.

After the configuration is applied we'll use the Vault CLI to generate a service
account key. If you don't have it installed you can use

```bash
$ docker run --rm -it -e VAULT_ADDR='http://localhost:8200' --net=host vault /bin/sh

$ vault login token=s.spqOs3rJ8ktgjcU16JBc7LPJ

Key                  Value
---                  -----
token                s.spqOs3rJ8ktgjcU16JBc7LPJ
token_accessor       J5TQZzDFFqYub7KCiyiYUmfn
token_duration       ∞
token_renewable      false
token_policies       ["root"]
identity_policies    []
policies             ["root"]
```

Lets get started with the Vault GCP backend configuration.
[This documentation](https://www.vaultproject.io/docs/secrets/gcp) has all the
details for the backend configuration and its features. I'll use most of it
directly, feel free to refer to this docs for more context.

We start with the GCP configuration, supposing we already have a GCP project
provisioned we start by configuring the service account that Vault is going to
use to manage other service accounts. We will:

* create a service account that is going to configure the backend
* create a custom role with the permissions needed by Vault
* bind the service account to the custom role and add it to the project's Policy

```ruby
// gcp.tf

variable "gcp_project_id" {
  type = string
}

variable "gcp_region" {
  type = string
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  version = "~> 2.5"
}

resource "google_service_account" "vault_gcp_secret_backend_sa" {
  account_id   = "vault-gcp-secret-backend"
  display_name = "Vault GCP Secret Backend"
}

resource "google_project_iam_custom_role" "vault_gcp_secret_backend_role" {
  role_id     = "VaultGcpSecretBackend"
  title       = "vault-gcp-secret-backend"
  description = "Allow Vault to manage service accounts"
  stage       = "GA"
  permissions = [
    "iam.serviceAccountKeys.create",
    "iam.serviceAccountKeys.delete",
    "iam.serviceAccountKeys.get",
    "iam.serviceAccountKeys.list",
    "iam.serviceAccounts.create",
    "iam.serviceAccounts.delete",
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.list",
    "iam.serviceAccounts.update",
    "resourcemanager.projects.getIamPolicy",
    "resourcemanager.projects.setIamPolicy",
  ]
}

resource "google_project_iam_member" "vault_gcp_secret_backend_member" {
  project = var.gcp_project_id
  role    = google_project_iam_custom_role.vault_gcp_secret_backend_role.id
  member  = "serviceAccount:${google_service_account.vault_gcp_secret_backend_sa.email}"
}

```

Notice that we are not providing credentials to the Google provider. We are using
the default credentials in your local environment.

Make sure you fill the `default.auto.tfvars` file with your values

```ruby
// default.auto.tfvars

gcp_project_id = "your-project-name"
gcp_region     = "a-region"
vault_token    = "vault-token"
vault_address  = "http://localhost:8200"
```

Run the Terraform plan to see how things are going so far:

```bash
$ terraform fmt -write
$ terraform init
$ terraform plan
```

The credential required by the `vault_gcp_secret_backend` is a service account
key. So we need to create one now:

```ruby
// gcp.tf

[...]

resource "google_service_account_key" "vault_gcp_secret_backend_sa_key" {
  service_account_id = google_service_account.vault_gcp_secret_backend_sa.name
}

```

Run the Terraform plan again and check how things look like

```bash
$ terraform plan
```

We don't need necessarily to do it now but lets apply the GCP changes before moving
to the Vault configuration.

```bash
$ terraform apply
# confirm yes
```

We start the Vault configuration with the GCP secret backend. Notice that we override
the default path to define some naming standard. Since this backend is project
specific we are adding the project id to the path.

```ruby
// vault.tf

variable "vault_address" {
  type = string
}

variable "vault_token" {
  type = string
}

provider "vault" {
  token   = var.vault_token
  address = var.vault_address
}

resource "vault_gcp_secret_backend" "gcp_secret_backend" {
  credentials               = base64decode(google_service_account_key.vault_gcp_secret_backend_sa_key.private_key)
  path                      = "gcp-broker/${var.gcp_project_id}-gcp-secret"
  default_lease_ttl_seconds = 120
  max_lease_ttl_seconds     = 3600
}
```

We are setting the `default_lease_ttl_seconds` to 2 minutes which means that the
secrets will not live longer than 2 minutes by default and we also setting the
`max_lease_ttl_seconds` to 1 hour.

You may want to run `terraform plan` at this point and check how things are going.

For this lab we are only interested about managing service accounts from Vault.
So we are going to configure the `roleset`

```ruby
// vault.tf

[...]

resource "vault_gcp_secret_roleset" "gcp_secret_backend_gke_admin" {
  backend     = vault_gcp_secret_backend.gcp_secret_backend.id
  roleset     = "gke-admin"
  secret_type = "service_account_key"
  project     = var.gcp_project_id

  binding {
    resource = "//cloudresourcemanager.googleapis.com/projects/${var.gcp_project_id}"

    roles = [
      "roles/container.admin",
    ]
  }
}

```

In this particular case, we are configuring a `roleset` that allows the service
account keys generated by Vault to manage GKE resources. This is a typical scenario
where you have you service account configured in one or multiple CI/CD pipelines
to manage your cluster and deploy your applications.

Just run a `terraform apply` and if everything looks fine confirm and apply it.

To test if it working fine we use the Vault CLI to generate a service account key.

```bash
$ vault read gcp-broker/your-project-name-gcp-secret/key/gke-admin

Key                 Value
---                 -----
lease_id            gcp-broker/your-project-name-gcp-secret/key/gke-admin/P5nIVGc961dmj0kLMtYf88BC
lease_duration      2m
lease_renewable     true
key_algorithm       KEY_ALG_RSA_2048
key_type            TYPE_GOOGLE_CREDENTIALS_FILE
private_key_data    ewogI...
```

The big win with this is that you don't need to have over granted service accounts
 spread across
many pipelines or create and hand service accounts to users (as long as they have
permission to access this roleset path). Additionally, there is total visibility
on which roles are being used.
