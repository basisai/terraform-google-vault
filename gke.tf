locals {
  gke_pool_create = var.gke_pool_create

  gke_service_account_roles = [
    "roles/logging.logWriter",       # Write logs
    "roles/monitoring.metricWriter", # Write metrics
  ]

  api_services = toset([
    "cloudkms.googleapis.com",
    "storage-api.googleapis.com",
  ])
}

resource "google_container_node_pool" "vault" {
  provider = google-beta
  count    = local.gke_pool_create ? 1 : 0

  depends_on = [
    google_project_iam_member.vault_nodes,
    google_project_service.services,
  ]

  name     = var.gke_pool_name
  location = var.gke_pool_location
  cluster  = var.gke_cluster
  project  = var.project_id

  autoscaling {
    min_node_count = 0
    max_node_count = var.gke_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    disk_size_gb = var.gke_node_size_gb
    disk_type    = var.gke_disk_type
    machine_type = var.gke_machine_type

    labels   = var.gke_labels
    metadata = var.gke_metadata
    tags     = var.gke_tags

    dynamic "taint" {
      for_each = var.gke_taints
      content {
        effect = taint.value.effect
        key    = taint.value.key
        value  = taint.value.value
      }
    }

    service_account = local.node_service_account

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/devstorage.read_write",
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # See https://cloud.google.com/kubernetes-engine/docs/how-to/protecting-cluster-metadata#concealment
    workload_metadata_config {
      node_metadata = var.workload_identity_enable ? "GKE_METADATA_SERVER" : "SECURE"
    }
  }

  dynamic "upgrade_settings" {
    for_each = var.gke_node_upgrade_settings_enabled ? list(var.gke_node_upgrade_settings) : []

    content {
      max_surge       = upgrade_settings.value.max_surge
      max_unavailable = upgrade_settings.value.max_unavailable
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# We need to enable the KMS and GCS APIs on the GKE cluster project
resource "google_project_service" "services" {
  provider = google-beta
  for_each = local.gke_pool_create ? local.api_services : []

  project = var.project_id
  service = each.key

  disable_on_destroy = false
}
