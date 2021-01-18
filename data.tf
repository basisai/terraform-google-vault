data "google_compute_zones" "raft" {
  provider = google-beta
  count    = var.raft_storage_enable ? 1 : 0

  project = var.project_id
  region  = var.raft_region
}

data "google_project" "this" {
  provider = google-beta

  project_id = var.project_id
}

data "google_client_config" "current" {
  provider = google-beta
}

data "google_storage_project_service_account" "vault" {
  provider = google-beta

  project = var.storage_bucket_project
}

locals {
  # cf. https://github.com/hashicorp/vault-helm/blob/1be24460f3e8b2fa5ac0fa4b1794eaa271246d2f/templates/_helpers.tpl#L7-L18
  fullname = trimsuffix(
    substr(
      var.fullname_override != "" ? var.fullname_override : (
        length(regexall("vault", var.release_name)) > 0 ? var.release_name : "${var.release_name}-vault"
      ),
      0, 63
    ),
    "-"
  )
}
