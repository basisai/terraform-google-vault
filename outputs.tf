output "release_name" {
  description = "Release name of the Helm chart"
  value       = helm_release.vault.metadata[0].name
}

output "key_ring_self_link" {
  description = "Self-link of the KMS Keyring created for Vault"
  value       = google_kms_key_ring.vault.self_link
}

output "unseal_key_self_link" {
  description = "Self-link of the KMS Key for unseal"
  value       = google_kms_crypto_key.unseal.id
}

output "storage_key_self_link" {
  description = "Self-link of the KMS Key for storage"
  value       = google_kms_crypto_key.storage.id
}

output "node_pool_service_account" {
  description = "Email ID of the GKE node pool service account if created"
  value       = local.node_service_account
}

output "vault_server_service_account" {
  description = "Email ID of the Vault server Service Account if created"
  value       = local.vault_server_service_account
}
