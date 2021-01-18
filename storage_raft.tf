resource "google_compute_disk" "raft" {
  provider = google-beta
  count    = var.raft_storage_enable && ! var.raft_disk_regional ? var.server_replicas : 0

  name = "${var.raft_persistent_disks_prefix}${count.index}"
  type = var.raft_disk_type
  size = var.raft_disk_size

  zone = element(coalescelist(var.raft_disk_zones, data.google_compute_zones.raft[0].names), count.index)

  description = "Vault server data disks replica ${count.index}"

  labels  = coalesce(var.raft_disk_labels, var.labels)
  project = var.project_id

  disk_encryption_key {
    kms_key_self_link = google_kms_crypto_key_iam_member.disk[0].crypto_key_id
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_compute_region_disk" "raft" {
  provider = google-beta
  count    = var.raft_storage_enable && var.raft_disk_regional ? var.server_replicas : 0

  name = "${var.raft_persistent_disks_prefix}${count.index}"
  type = var.raft_disk_type
  size = var.raft_disk_size

  region = var.raft_region
  replica_zones = coalescelist(
    element(var.raft_replica_zones, count.index),
    [element(data.google_compute_zones.raft[0].names, count.index), element(data.google_compute_zones.raft[0].names, count.index + 1)]
  )

  description = "Vault server data disks replica ${count.index}"

  labels  = coalesce(var.raft_disk_labels, var.labels)
  project = var.project_id

  disk_encryption_key {
    kms_key_name = google_kms_crypto_key.storage.self_link
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_compute_resource_policy" "raft_backup" {
  provider = google-beta
  count    = var.raft_storage_enable && var.raft_snapshot_enable ? 1 : 0

  name    = var.raft_backup_policy
  region  = var.raft_region
  project = var.project_id

  snapshot_schedule_policy {
    schedule {
      dynamic "hourly_schedule" {
        for_each = var.raft_snapshot_hourly ? [{}] : []
        content {
          hours_in_cycle = var.raft_snapshot_hours_in_cycle
          start_time     = var.raft_snapshot_start_time
        }
      }

      dynamic "daily_schedule" {
        for_each = var.raft_snapshot_daily ? [{}] : []
        content {
          days_in_cycle = var.raft_snapshot_days_in_cycle
          start_time    = var.raft_snapshot_start_time
        }
      }

      dynamic "weekly_schedule" {
        for_each = var.raft_snapshot_weekly ? [{}] : []
        content {
          dynamic "day_of_weeks" {
            for_each = var.raft_snapshot_day_of_weeks

            content {
              day        = day_of_weeks.key
              start_time = day_of_weeks.value
            }
          }
        }
      }
    }

    retention_policy {
      max_retention_days    = var.raft_backup_max_retention_days
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }

    snapshot_properties {
      labels            = coalesce(var.raft_disk_snapshot_labels, var.labels)
      storage_locations = [var.raft_region]
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_disk_resource_policy_attachment" "raft_backup" {
  provider = google-beta
  count    = var.raft_storage_enable && var.raft_snapshot_enable && ! var.raft_disk_regional ? var.server_replicas : 0

  name = google_compute_resource_policy.raft_backup[0].name
  disk = google_compute_disk.raft[count.index].name
  zone = google_compute_disk.raft[count.index].zone

  project = var.project_id
}

resource "google_compute_region_disk_resource_policy_attachment" "raft_backup" {
  provider = google-beta
  count    = var.raft_storage_enable && var.raft_snapshot_enable && var.raft_disk_regional ? var.server_replicas : 0

  name   = google_compute_resource_policy.raft_backup[0].name
  disk   = google_compute_region_disk.raft[count.index].name
  region = google_compute_region_disk.raft[count.index].region

  project = var.project_id
}

locals {
  volume_name_prefix = "data-${local.fullname}-"
}

resource "kubernetes_storage_class" "raft" {
  count = var.raft_storage_enable ? 1 : 0

  metadata {
    name = "${local.fullname}-raft"

    annotations = var.kubernetes_annotations
    labels      = var.kubernetes_labels
  }

  storage_provisioner    = "pd.csi.storage.gke.io"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true

  parameters = {
    type                    = var.raft_disk_type
    replication-type        = var.raft_disk_regional ? "regional-pd" : "none"
    disk-encryption-kms-key = google_kms_crypto_key.storage.id
  }
}

resource "kubernetes_persistent_volume" "raft" {
  count = var.raft_storage_enable ? var.server_replicas : 0

  metadata {
    name = "${local.volume_name_prefix}${count.index}"

    annotations = var.kubernetes_annotations
    labels      = var.kubernetes_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class.raft[0].metadata[0].name

    capacity = {
      storage = "${var.raft_disk_size}G"
    }

    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "topology.gke.io/zone"
            operator = "In"
            values = var.raft_disk_regional ? coalescelist(
              element(var.raft_replica_zones, count.index),
              [element(data.google_compute_zones.raft[0].names, count.index), element(data.google_compute_zones.raft[0].names, count.index + 1)]
            ) : [google_compute_disk.raft[count.index].zone]
          }
        }
      }
    }

    persistent_volume_source {
      csi {
        driver        = "pd.csi.storage.gke.io"
        volume_handle = var.raft_disk_regional ? google_compute_region_disk.raft[count.index].id : google_compute_disk.raft[count.index].id
        fs_type       = "ext4"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "raft" {
  count = var.raft_storage_enable ? var.server_replicas : 0

  metadata {
    name = "${local.volume_name_prefix}${count.index}"

    annotations = var.kubernetes_annotations
    labels      = var.kubernetes_labels

    namespace = var.kubernetes_namespace
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    volume_name  = kubernetes_persistent_volume.raft[count.index].metadata[0].name

    storage_class_name = kubernetes_storage_class.raft[0].metadata[0].name

    resources {
      requests = {
        storage = "${var.raft_disk_size}G"
      }
    }
  }
}
