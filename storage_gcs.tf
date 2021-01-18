resource "google_storage_bucket" "vault" {
  provider = google-beta
  count    = var.gcs_storage_enable ? 1 : 0

  name = var.storage_bucket_name

  location = coalesce(
    var.storage_bucket_location,
    data.google_client_config.current.region,
  )

  project       = var.storage_bucket_project
  storage_class = var.storage_bucket_class

  labels = var.storage_bucket_labels

  bucket_policy_only = true

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key_iam_member.gcs[0].crypto_key_id
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_storage_bucket_iam_member" "storage" {
  provider = google-beta
  count    = var.gcs_storage_enable ? 1 : 0

  bucket = google_storage_bucket.vault[0].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${local.vault_server_service_account}"
}
