resource "google_kms_key_ring" "vault" {
  provider = google-beta

  name     = var.key_ring_name
  location = var.kms_location
  project  = var.kms_project

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key" "unseal" {
  provider = google-beta

  name     = var.unseal_key_name
  key_ring = google_kms_key_ring.vault.self_link

  rotation_period = var.unseal_key_rotation_period

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key" "storage" {
  provider = google-beta

  name     = var.storage_key_name
  key_ring = google_kms_key_ring.vault.self_link

  rotation_period = var.storage_key_rotation_period

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key_iam_member" "gcs" {
  provider = google-beta
  count    = var.gcs_storage_enable ? 1 : 0

  crypto_key_id = google_kms_crypto_key.storage.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.vault.email_address}"
}


resource "google_kms_crypto_key_iam_member" "disk" {
  provider = google-beta
  count    = var.raft_storage_enable ? 1 : 0

  crypto_key_id = google_kms_crypto_key.storage.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.this.number}@compute-system.iam.gserviceaccount.com"
}

resource "google_kms_crypto_key_iam_member" "auto_unseal" {
  provider = google-beta

  crypto_key_id = google_kms_crypto_key.unseal.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${local.vault_server_service_account}"
}
