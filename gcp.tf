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

resource "google_service_account_key" "vault_gcp_secret_backend_sa_key" {
  service_account_id = google_service_account.vault_gcp_secret_backend_sa.name
}