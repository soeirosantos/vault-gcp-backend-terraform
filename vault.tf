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
