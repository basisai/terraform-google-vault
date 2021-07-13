# Vault

Deploys a [Vault](https://www.vaultproject.io/) cluster on Kubernetes running on GCP in an
opinionated fashion.

This module makes use of the
[official Vault Helm Chart](https://github.com/hashicorp/vault-helm).

You should be familiar with various [concepts](https://www.vaultproject.io/docs/concepts/) for Vault
first before continuing

## Requirements

You will need to have the following resources available:

- A Kubernetes cluster, managed by GKE, or not
- [Helm](https://helm.sh/) with Tiller running on the Cluster or you can opt to run
    [Tiller locally](https://docs.helm.sh/using_helm/#running-tiller-locally)
- If you are planning to use the Raft storage for Vault, you will need to have the
    [Google Compute Engine Persistent Disk CSI Driver](https://github.com/kubernetes-sigs/gcp-compute-persistent-disk-csi-driver)
    installed on your cluster. GKE users can
    [enable this](https://cloud.google.com/kubernetes-engine/docs/how-to/gce-pd-csi-driver) in their
    cluster.

You will need to have the following configured on your machine:

- Credentials for GCP
- Credentials for Kubernetes configured for `kubectl`

### GKE RBAC

If you are using GKE and have configured `kuebctl` with credentials using
`gcloud container clusters get-credentials [CLUSTER_NAME]` only, your account in Kubernetes might
not have the necessary rights to deploy this Helm chart. You can
[give](https://cloud.google.com/kubernetes-engine/docs/how-to/role-based-access-control#prerequisites_for_using_role-based_access_control)
yourself the necessary rights by running

```bash
kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole cluster-admin --user [USER_ACCOUNT]
```

where `[USER_ACCOUNT]` is your email address.

## Usage

This module uses the [Helm Chart](https://github.com/helm/charts/tree/master/incubator/vault) for
Vault to deploy Vault running on a Kubernetes Cluster.

In addition, for (opinionated) operational reasons, this module additionally provisions the
following additional resources:

Either
- A Google Cloud Storage (GCS) Bucket for storing Vault State and to provide High Availability
- GCE disks for storage of raft state

and
- A Google KMS keyring with keys for auto unsealing Vault and encrypting storage
- (Optional) A separate GKE Node pool purely for running Vault

This module makes use of both the `google-beta` provider. See the documentation on
GCP [provider versions](https://www.terraform.io/docs/providers/google/provider_versions.html).

### Operational Considerations

It might be useful to refer to Hashicorp's
[guide](https://learn.hashicorp.com/vault/operations/production-hardening) on how to harden your
Vault cluster.

The sections below would detail additional considerations that are specific to the setup
that this module provides.

#### Separate GCP Project

The most granular permissions that you can assign to most GCP resources is at the project level.
Therefore, you should provision the resources for Vault, wherever possible, in their own separate
GCP project. You could use Google's
[Project Factory module](https://github.com/terraform-google-modules/terraform-google-project-factory)
to Terraform a new project specifically for Vault.

#### High Availability Mode (HA)

HA is enabled "for free" by our use of the GCS bucket for storage. Optionally, you can choose to use
a [Consul](https://www.consul.io/)) cluster, running on the Kubernetes Cluster or not for
HashiCorp HA only. If you choose to do so, remember to set `storage_ha_enabled` to `"false"`.

#### TLS

You need to generate a set of self-signed certificates for Vault to communicate. Refer to the
[CA Guide](../../utils/ca) for more information.

Remember to encrypt the private key before checking it into your repository. You can use the
[`google_kms_secret`](https://www.terraform.io/docs/providers/google/d/google_kms_secret.html) data
source to decrypt during apply time.

You must provide the unencrypted PEM encoded certificate and key in the variables `tls_cert_pem`
and `tls_cert_key` respectively.

#### Kubernetes

You should run Vault in a separate
[namespace](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)
and provision all the Kubernetes resources in this namespace. Then, you can make use of
[RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) to control access to resources
in this namespace.

You should also consider running Vault on a separate nodes from the rest of your workload. You
should also make use of
[taints and tolerations](https://kubernetes.io/docs/concepts/configuration/taint-and-toleration/) to
make sure that these nodes run Vault exclusively.

In addition, you should configure various
[Admission Controllers](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)
to control access to pod tolerations using
[`PodTolerationRestriction`](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#podtolerationrestriction)
and nodes from modifying their own taints using
[`NodeRestriction`](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#noderestriction).

### Vault Configuration

The basic configuration provided in this module configures the following:

- [`listener` stanza](https://www.vaultproject.io/docs/configuration/listener/index.html)
- [`seal` stanza](https://www.vaultproject.io/docs/configuration/seal/gcpckms.html) for auto-unsealing
    via GCP KMS.
- [`storage` stanza](https://www.vaultproject.io/docs/configuration/storage/index.html) using the
    GCS bucket or Raft storage.
- [`service_registration` stanza](https://www.vaultproject.io/docs/configuration/service-registration/kubernetes)
    for Kubernetes.

Not all required parameters are automatically configured. For example, the
[`api_addr`](https://www.vaultproject.io/docs/configuration/#api_addr) field is not automatically
configured.

You should refer to [Vault's documentation](https://www.vaultproject.io/docs/configuration/) on
the additional options available and provide them in the `vault_config` variable.

### Vault Initialisation

The first time you deploy Vault, you need to initialise Vault. You can do this by `kubectl exec`
into one of the pods.

Assuming you have deployed the Helm chart using the release name `vault` in the `default` namespace,
you can find the list of pods using

```bash
kubectl get pods --namespace default --selector=release=vault
```

Choose one of the pods and `exec` into the pod:

```bash
kubectl exec --namespace default -it vault-xxxx-xxxx -c vault sh

# Once inside the pod, we can run
vault operator init -tls-skip-verify
```

**Make sure you take note of the recovery keys and the intial root token!**

If you lose the recovery key, you will lose all your data.

You should then `exec` into the remaining pods and force a restart of the container

```bash
kill -15 1
```

You will only need to do this for the first time.

### Vault Unsealing

Vault is set up to [auto unseal](https://www.vaultproject.io/docs/concepts/seal.html#auto-unseal)
using the KMS key provisioned by this module. You will generally not have to worry about manually
unsealing Vault if the nodes have access to the keys.

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 0.14 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | >= 3.70 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google-beta"></a> [google-beta](#provider\_google-beta) | >= 3.70 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 2.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.0 |
| <a name="provider_local"></a> [local](#provider\_local) | n/a |
| <a name="provider_null"></a> [null](#provider\_null) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google-beta_google_compute_disk.raft](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_compute_disk) | resource |
| [google-beta_google_compute_disk_resource_policy_attachment.raft_backup](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_compute_disk_resource_policy_attachment) | resource |
| [google-beta_google_compute_region_disk.raft](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_compute_region_disk) | resource |
| [google-beta_google_compute_region_disk_resource_policy_attachment.raft_backup](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_compute_region_disk_resource_policy_attachment) | resource |
| [google-beta_google_compute_resource_policy.raft_backup](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_compute_resource_policy) | resource |
| [google-beta_google_container_node_pool.vault](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_container_node_pool) | resource |
| [google-beta_google_kms_crypto_key.storage](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_kms_crypto_key) | resource |
| [google-beta_google_kms_crypto_key.unseal](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_kms_crypto_key) | resource |
| [google-beta_google_kms_crypto_key_iam_member.auto_unseal](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_kms_crypto_key_iam_member) | resource |
| [google-beta_google_kms_crypto_key_iam_member.disk](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_kms_crypto_key_iam_member) | resource |
| [google-beta_google_kms_crypto_key_iam_member.gcs](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_kms_crypto_key_iam_member) | resource |
| [google-beta_google_kms_key_ring.vault](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_kms_key_ring) | resource |
| [google-beta_google_project_iam_member.vault_nodes](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_project_iam_member) | resource |
| [google-beta_google_project_service.services](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_project_service) | resource |
| [google-beta_google_service_account.vault_gke_pool](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_service_account) | resource |
| [google-beta_google_service_account.vault_server](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_service_account) | resource |
| [google-beta_google_service_account_iam_member.vault_workload_identity](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_service_account_iam_member) | resource |
| [google-beta_google_storage_bucket.vault](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_storage_bucket) | resource |
| [google-beta_google_storage_bucket_iam_member.storage](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_storage_bucket_iam_member) | resource |
| [helm_release.vault](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_persistent_volume.raft](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/persistent_volume) | resource |
| [kubernetes_persistent_volume_claim.raft](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/persistent_volume_claim) | resource |
| [kubernetes_secret.tls_cert](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret) | resource |
| [kubernetes_storage_class.raft](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/storage_class) | resource |
| [local_file.values](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [null_resource.vault_values](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [google-beta_google_client_config.current](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/data-sources/google_client_config) | data source |
| [google-beta_google_compute_zones.raft](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/data-sources/google_compute_zones) | data source |
| [google-beta_google_project.this](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/data-sources/google_project) | data source |
| [google-beta_google_storage_project_service_account.vault](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/data-sources/google_storage_project_service_account) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_agent_default_cpu_limit"></a> [agent\_default\_cpu\_limit](#input\_agent\_default\_cpu\_limit) | Default CPU Limit for injected agent containers | `string` | `"500m"` | no |
| <a name="input_agent_default_cpu_request"></a> [agent\_default\_cpu\_request](#input\_agent\_default\_cpu\_request) | Default CPU request for injected agent containers | `string` | `"250m"` | no |
| <a name="input_agent_default_memory_limit"></a> [agent\_default\_memory\_limit](#input\_agent\_default\_memory\_limit) | Default memory Limit for injected agent containers | `string` | `"128Mi"` | no |
| <a name="input_agent_default_memory_request"></a> [agent\_default\_memory\_request](#input\_agent\_default\_memory\_request) | Default memory request for injected agent containers | `string` | `"128Mi"` | no |
| <a name="input_agent_default_template_type"></a> [agent\_default\_template\_type](#input\_agent\_default\_template\_type) | Default template type for secrets when no custom template is specified. Possible values include: "json" and "map". | `string` | `"map"` | no |
| <a name="input_agent_image_repository"></a> [agent\_image\_repository](#input\_agent\_image\_repository) | Image repository for the Vault agent that is injected | `string` | `"vault"` | no |
| <a name="input_agent_image_tag"></a> [agent\_image\_tag](#input\_agent\_image\_tag) | Image tag for the Vault agent that is injected | `string` | `"1.7.3"` | no |
| <a name="input_api_addr"></a> [api\_addr](#input\_api\_addr) | Set the api\_addr configuration for Vault HA. See https://www.vaultproject.io/docs/configuration#api_addr If set to null, this will be set to the Pod IP Address | `any` | `null` | no |
| <a name="input_auth_path"></a> [auth\_path](#input\_auth\_path) | Mount path of the Kubernetes Auth Engine that the injector will use | `string` | `"auth/kubernetes"` | no |
| <a name="input_chart_name"></a> [chart\_name](#input\_chart\_name) | Helm chart name to provision | `string` | `"vault"` | no |
| <a name="input_chart_repository"></a> [chart\_repository](#input\_chart\_repository) | Helm repository for the chart | `string` | `"https://helm.releases.hashicorp.com"` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Version of Chart to install. Set to empty to install the latest version | `string` | `"0.13.0"` | no |
| <a name="input_enable_auth_delegator"></a> [enable\_auth\_delegator](#input\_enable\_auth\_delegator) | uthDelegator enables a cluster role binding to be attached to the service account.  This cluster role binding can be used to setup Kubernetes auth method. https://www.vaultproject.io/docs/auth/kubernetes.html | `bool` | `true` | no |
| <a name="input_external_vault_addr"></a> [external\_vault\_addr](#input\_external\_vault\_addr) | External vault server address for the injector to use. Setting this will disable deployment of a vault server along with the injector. | `string` | `""` | no |
| <a name="input_fullname_override"></a> [fullname\_override](#input\_fullname\_override) | Helm resources full name override | `string` | `""` | no |
| <a name="input_gcs_extra_parameters"></a> [gcs\_extra\_parameters](#input\_gcs\_extra\_parameters) | Additional paramaters for GCS storage in HCL. See https://www.vaultproject.io/docs/configuration/storage/google-cloud-storage | `string` | `""` | no |
| <a name="input_gcs_storage_enable"></a> [gcs\_storage\_enable](#input\_gcs\_storage\_enable) | Enable the use of GCS Storage | `any` | n/a | yes |
| <a name="input_gcs_storage_use"></a> [gcs\_storage\_use](#input\_gcs\_storage\_use) | Use GCS storage in Vault configuration. Setting this to false allows GCS storage resouces to be created but not used with Vault | `bool` | `true` | no |
| <a name="input_gke_boot_disk_kms_key"></a> [gke\_boot\_disk\_kms\_key](#input\_gke\_boot\_disk\_kms\_key) | KMS Key to encrypt the boot disk. Set to `null` to not use any | `string` | `null` | no |
| <a name="input_gke_cluster"></a> [gke\_cluster](#input\_gke\_cluster) | Cluster to create node pool for | `string` | `"<REQUIRED if gke_pool_create is true>"` | no |
| <a name="input_gke_disk_type"></a> [gke\_disk\_type](#input\_gke\_disk\_type) | Disk type for the nodes | `string` | `"pd-standard"` | no |
| <a name="input_gke_enable_integrity_monitoring"></a> [gke\_enable\_integrity\_monitoring](#input\_gke\_enable\_integrity\_monitoring) | Enable integrity monitoring of nodes | `bool` | `false` | no |
| <a name="input_gke_enable_secure_boot"></a> [gke\_enable\_secure\_boot](#input\_gke\_enable\_secure\_boot) | Enable secure boot for GKE nodes | `bool` | `false` | no |
| <a name="input_gke_image_type"></a> [gke\_image\_type](#input\_gke\_image\_type) | Type of image for GKE nodes | `string` | `"COS_CONTAINERD"` | no |
| <a name="input_gke_labels"></a> [gke\_labels](#input\_gke\_labels) | Labels for the GKE nodes | `map` | `{}` | no |
| <a name="input_gke_machine_type"></a> [gke\_machine\_type](#input\_gke\_machine\_type) | Machine type for the GKE nodes. Make sure this matches the resources you are requesting | `string` | `"n1-standard-2"` | no |
| <a name="input_gke_metadata"></a> [gke\_metadata](#input\_gke\_metadata) | Metadata for the GKE nodes | `map` | `{}` | no |
| <a name="input_gke_node_count"></a> [gke\_node\_count](#input\_gke\_node\_count) | Initial Node count. If regional, remember to divide the desired node count by the number of zones | `number` | `3` | no |
| <a name="input_gke_node_size_gb"></a> [gke\_node\_size\_gb](#input\_gke\_node\_size\_gb) | Disk size for the nodes in GB | `string` | `"20"` | no |
| <a name="input_gke_node_upgrade_settings"></a> [gke\_node\_upgrade\_settings](#input\_gke\_node\_upgrade\_settings) | Surge upgrade settings as per https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-upgrades#surge | `object({ max_surge = number, max_unavailable = number })` | <pre>{<br>  "max_surge": 1,<br>  "max_unavailable": 0<br>}</pre> | no |
| <a name="input_gke_node_upgrade_settings_enabled"></a> [gke\_node\_upgrade\_settings\_enabled](#input\_gke\_node\_upgrade\_settings\_enabled) | Enable/disable gke node pool surge upgrade settings | `bool` | `false` | no |
| <a name="input_gke_pool_create"></a> [gke\_pool\_create](#input\_gke\_pool\_create) | Whether to create the GKE node pool or not | `bool` | `false` | no |
| <a name="input_gke_pool_location"></a> [gke\_pool\_location](#input\_gke\_pool\_location) | Location for the node pool | `string` | `"<REQUIRED if gke_pool_create is true>"` | no |
| <a name="input_gke_pool_name"></a> [gke\_pool\_name](#input\_gke\_pool\_name) | Name of the GKE Pool name to create | `string` | `"vault"` | no |
| <a name="input_gke_tags"></a> [gke\_tags](#input\_gke\_tags) | Network tags for the GKE nodes | `list` | `[]` | no |
| <a name="input_gke_taints"></a> [gke\_taints](#input\_gke\_taints) | List of map of taints for GKE nodes. It is highly recommended you do set this alongside the pods toleration. See https://www.terraform.io/docs/providers/google/r/container_cluster.html#key for the keys and the README for more information | `list` | `[]` | no |
| <a name="input_global_enabled"></a> [global\_enabled](#input\_global\_enabled) | Globally enable or disable chart resources | `bool` | `true` | no |
| <a name="input_ingress_annotations"></a> [ingress\_annotations](#input\_ingress\_annotations) | Annotations for server ingress | `map` | `{}` | no |
| <a name="input_ingress_enabled"></a> [ingress\_enabled](#input\_ingress\_enabled) | Enable ingress for the server | `bool` | `false` | no |
| <a name="input_ingress_hosts"></a> [ingress\_hosts](#input\_ingress\_hosts) | Hosts for server ingress | `list` | <pre>[<br>  {<br>    "host": "chart-example.local",<br>    "paths": []<br>  }<br>]</pre> | no |
| <a name="input_ingress_labels"></a> [ingress\_labels](#input\_ingress\_labels) | Labels for server ingress | `map` | `{}` | no |
| <a name="input_ingress_tls"></a> [ingress\_tls](#input\_ingress\_tls) | Configuration for server ingress | `list` | `[]` | no |
| <a name="input_injector_affinity"></a> [injector\_affinity](#input\_injector\_affinity) | YAML string for injector pod affinity | `string` | `"podAntiAffinity:\n  requiredDuringSchedulingIgnoredDuringExecution:\n    - labelSelector:\n        matchLabels:\n          app.kubernetes.io/name: {{ template \"vault.name\" . }}-agent-injector\n          app.kubernetes.io/instance: \"{{ .Release.Name }}\"\n          component: webhook\n      topologyKey: kubernetes.io/hostname\n"` | no |
| <a name="input_injector_enabled"></a> [injector\_enabled](#input\_injector\_enabled) | Enable Vault Injector | `bool` | `true` | no |
| <a name="input_injector_env"></a> [injector\_env](#input\_injector\_env) | Extra environment variable for the injector pods | `map` | `{}` | no |
| <a name="input_injector_failure_policy"></a> [injector\_failure\_policy](#input\_injector\_failure\_policy) | Configures failurePolicy of the webhook. Default behaviour depends on the admission webhook version. See https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/#failure-policy | `string` | `"Ignore"` | no |
| <a name="input_injector_image_repository"></a> [injector\_image\_repository](#input\_injector\_image\_repository) | Image repository for Vault Injector | `string` | `"hashicorp/vault-k8s"` | no |
| <a name="input_injector_image_tag"></a> [injector\_image\_tag](#input\_injector\_image\_tag) | Image tag for Vault Injector | `string` | `"0.10.2"` | no |
| <a name="input_injector_leader_elector_enabled"></a> [injector\_leader\_elector\_enabled](#input\_injector\_leader\_elector\_enabled) | Enable leader elector for Injector if > 1 replicas | `bool` | `true` | no |
| <a name="input_injector_leader_elector_image"></a> [injector\_leader\_elector\_image](#input\_injector\_leader\_elector\_image) | Image for Injector leader elector | `string` | `"gcr.io/google_containers/leader-elector"` | no |
| <a name="input_injector_leader_elector_tag"></a> [injector\_leader\_elector\_tag](#input\_injector\_leader\_elector\_tag) | Image tag for Injector leader elector | `string` | `"0.4"` | no |
| <a name="input_injector_leader_ttl"></a> [injector\_leader\_ttl](#input\_injector\_leader\_ttl) | TTL for a injector leader | `string` | `"60s"` | no |
| <a name="input_injector_log_format"></a> [injector\_log\_format](#input\_injector\_log\_format) | Log format for the injector. standard or json | `string` | `"standard"` | no |
| <a name="input_injector_log_level"></a> [injector\_log\_level](#input\_injector\_log\_level) | Log level for the injector. Supported log levels: trace, debug, error, warn, info | `string` | `"info"` | no |
| <a name="input_injector_metrics_enabled"></a> [injector\_metrics\_enabled](#input\_injector\_metrics\_enabled) | enable a node exporter metrics endpoint at /metrics | `bool` | `false` | no |
| <a name="input_injector_priority_class_name"></a> [injector\_priority\_class\_name](#input\_injector\_priority\_class\_name) | Priority class name for injector pods | `string` | `""` | no |
| <a name="input_injector_replicas"></a> [injector\_replicas](#input\_injector\_replicas) | Number of injector replicas | `number` | `1` | no |
| <a name="input_injector_resources"></a> [injector\_resources](#input\_injector\_resources) | Resources for the injector | `map` | <pre>{<br>  "limits": {<br>    "cpu": "250m",<br>    "memory": "256Mi"<br>  },<br>  "requests": {<br>    "cpu": "250m",<br>    "memory": "256Mi"<br>  }<br>}</pre> | no |
| <a name="input_injector_tolerations"></a> [injector\_tolerations](#input\_injector\_tolerations) | YAML string for injector tolerations | `string` | `""` | no |
| <a name="input_key_ring_name"></a> [key\_ring\_name](#input\_key\_ring\_name) | Name of the Keyring to create. | `string` | `"vault"` | no |
| <a name="input_kms_location"></a> [kms\_location](#input\_kms\_location) | Location of the KMS key ring. Must be in the same location as your storage bucket | `any` | n/a | yes |
| <a name="input_kms_project"></a> [kms\_project](#input\_kms\_project) | Project ID to create the keyring in | `any` | n/a | yes |
| <a name="input_kubernetes_annotations"></a> [kubernetes\_annotations](#input\_kubernetes\_annotations) | Annotations for Kubernetes in general | `map` | `{}` | no |
| <a name="input_kubernetes_labels"></a> [kubernetes\_labels](#input\_kubernetes\_labels) | Labels for Kubernetes in general | `map` | <pre>{<br>  "app": "vault",<br>  "terraform": "true"<br>}</pre> | no |
| <a name="input_kubernetes_namespace"></a> [kubernetes\_namespace](#input\_kubernetes\_namespace) | Namespace for Kubernetes resources | `string` | `"default"` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels for GCP resources | `map` | <pre>{<br>  "terraform": "true",<br>  "usage": "vault"<br>}</pre> | no |
| <a name="input_max_history"></a> [max\_history](#input\_max\_history) | Max history for Helm | `number` | `20` | no |
| <a name="input_namespace_selector"></a> [namespace\_selector](#input\_namespace\_selector) | The selector for restricting the webhook to only specific namespaces. See https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/#matching-requests-namespaceselector for more details. | `map` | `{}` | no |
| <a name="input_node_port"></a> [node\_port](#input\_node\_port) | If type is set to 'NodePort', a specific nodePort value can be configured, will be random if left blank. | `string` | `"30000"` | no |
| <a name="input_object_selector"></a> [object\_selector](#input\_object\_selector) | objectSelector is the selector for restricting the webhook to only specific labels. See https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/#matching-requests-objectselector | `map` | `{}` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Project ID for GCP Resources | `any` | n/a | yes |
| <a name="input_psp_annotations"></a> [psp\_annotations](#input\_psp\_annotations) | Template YAML string for PSP annotations | `string` | `"seccomp.security.alpha.kubernetes.io/allowedProfileNames: docker/default,runtime/default\napparmor.security.beta.kubernetes.io/allowedProfileNames: runtime/default\nseccomp.security.alpha.kubernetes.io/defaultProfileName:  runtime/default\napparmor.security.beta.kubernetes.io/defaultProfileName:  runtime/default\n"` | no |
| <a name="input_psp_enabled"></a> [psp\_enabled](#input\_psp\_enabled) | Enable PSP | `bool` | `false` | no |
| <a name="input_raft_backup_max_retention_days"></a> [raft\_backup\_max\_retention\_days](#input\_raft\_backup\_max\_retention\_days) | Maximum daily age of the snapshot that is allowed to be kept. | `number` | `14` | no |
| <a name="input_raft_backup_policy"></a> [raft\_backup\_policy](#input\_raft\_backup\_policy) | Data disk backup policy name | `string` | `"vault-data-backup"` | no |
| <a name="input_raft_disk_labels"></a> [raft\_disk\_labels](#input\_raft\_disk\_labels) | Override labels for Raft GCE PD resources. Will use `var.labels` if set to null | `map(string)` | `null` | no |
| <a name="input_raft_disk_regional"></a> [raft\_disk\_regional](#input\_raft\_disk\_regional) | Use regional disks instead of zonal disks | `bool` | `true` | no |
| <a name="input_raft_disk_size"></a> [raft\_disk\_size](#input\_raft\_disk\_size) | Size of Raft disks in GB | `number` | `10` | no |
| <a name="input_raft_disk_snapshot_labels"></a> [raft\_disk\_snapshot\_labels](#input\_raft\_disk\_snapshot\_labels) | Override labels for Raft GCE PD snapshot resources. Will use `var.labels` if set to null | `map(string)` | `null` | no |
| <a name="input_raft_disk_type"></a> [raft\_disk\_type](#input\_raft\_disk\_type) | Raft data disk type | `string` | `"pd-ssd"` | no |
| <a name="input_raft_disk_zones"></a> [raft\_disk\_zones](#input\_raft\_disk\_zones) | List of zones for disks. If not set, will default to the zones in var.region | `list(string)` | `[]` | no |
| <a name="input_raft_extra_parameters"></a> [raft\_extra\_parameters](#input\_raft\_extra\_parameters) | Extra parameters for Raft storage in HCL | `string` | `""` | no |
| <a name="input_raft_persistent_disks_prefix"></a> [raft\_persistent\_disks\_prefix](#input\_raft\_persistent\_disks\_prefix) | Prefix of the name persistent disks for Vault to create. The prefix will be appended with the index | `string` | `"vault-data-"` | no |
| <a name="input_raft_region"></a> [raft\_region](#input\_raft\_region) | GCP Region for Raft Disk resources | `string` | `""` | no |
| <a name="input_raft_replica_zones"></a> [raft\_replica\_zones](#input\_raft\_replica\_zones) | List of replica zones for disks. If not set, will default to the zones in var.region | `list(list(string))` | <pre>[<br>  []<br>]</pre> | no |
| <a name="input_raft_set_node_id"></a> [raft\_set\_node\_id](#input\_raft\_set\_node\_id) | Set Raft Node ID as the name of the vault pod | `bool` | `true` | no |
| <a name="input_raft_snapshot_daily"></a> [raft\_snapshot\_daily](#input\_raft\_snapshot\_daily) | Take snapshot of raft disks daily | `bool` | `true` | no |
| <a name="input_raft_snapshot_day_of_weeks"></a> [raft\_snapshot\_day\_of\_weeks](#input\_raft\_snapshot\_day\_of\_weeks) | Map where the key is the day of the week to take snapshot and the value is the time of the day | `map` | <pre>{<br>  "SUNDAY": "00:00",<br>  "WEDNESDAY": "00:00"<br>}</pre> | no |
| <a name="input_raft_snapshot_days_in_cycle"></a> [raft\_snapshot\_days\_in\_cycle](#input\_raft\_snapshot\_days\_in\_cycle) | Number of days between snapshots for daily snapshots | `number` | `1` | no |
| <a name="input_raft_snapshot_enable"></a> [raft\_snapshot\_enable](#input\_raft\_snapshot\_enable) | Create data disk resource backup policy | `bool` | `true` | no |
| <a name="input_raft_snapshot_hourly"></a> [raft\_snapshot\_hourly](#input\_raft\_snapshot\_hourly) | Take snapshot of raft disks hourly | `bool` | `false` | no |
| <a name="input_raft_snapshot_hours_in_cycle"></a> [raft\_snapshot\_hours\_in\_cycle](#input\_raft\_snapshot\_hours\_in\_cycle) | Number of hours between snapshots for hourly snapshots | `number` | `1` | no |
| <a name="input_raft_snapshot_start_time"></a> [raft\_snapshot\_start\_time](#input\_raft\_snapshot\_start\_time) | Time in UTC format to start snapshot. Context depends on whether it's daily or hourly | `string` | `"19:00"` | no |
| <a name="input_raft_snapshot_weekly"></a> [raft\_snapshot\_weekly](#input\_raft\_snapshot\_weekly) | Take snapshot of raft disks weekly | `bool` | `false` | no |
| <a name="input_raft_storage_enable"></a> [raft\_storage\_enable](#input\_raft\_storage\_enable) | Enable the use of Raft Storage | `any` | n/a | yes |
| <a name="input_raft_storage_use"></a> [raft\_storage\_use](#input\_raft\_storage\_use) | Use Raft storage in Vault configuration. Setting this to false allows Raft storage resouces to be created but not used with Vault | `bool` | `true` | no |
| <a name="input_release_name"></a> [release\_name](#input\_release\_name) | Helm release name for Vault | `string` | `"vault"` | no |
| <a name="input_revoke_on_shutdown"></a> [revoke\_on\_shutdown](#input\_revoke\_on\_shutdown) | Attempt to revoke Vault Token on injected agent shutdown. | `bool` | `true` | no |
| <a name="input_server_affinity"></a> [server\_affinity](#input\_server\_affinity) | Server affinity YAML string | `string` | `"podAntiAffinity:\n  requiredDuringSchedulingIgnoredDuringExecution:\n    - labelSelector:\n        matchLabels:\n          app.kubernetes.io/name: {{ template \"vault.name\" . }}\n          app.kubernetes.io/instance: \"{{ .Release.Name }}\"\n          component: server\n      topologyKey: kubernetes.io/hostname\n"` | no |
| <a name="input_server_annotations"></a> [server\_annotations](#input\_server\_annotations) | Annotations for server | `map` | `{}` | no |
| <a name="input_server_config"></a> [server\_config](#input\_server\_config) | Additional server configuration in HCL | `string` | `""` | no |
| <a name="input_server_enabled"></a> [server\_enabled](#input\_server\_enabled) | Enable Vault Server | `bool` | `true` | no |
| <a name="input_server_env"></a> [server\_env](#input\_server\_env) | Server extra environment variables | `map` | `{}` | no |
| <a name="input_server_extra_args"></a> [server\_extra\_args](#input\_server\_extra\_args) | Extra args for the server | `string` | `""` | no |
| <a name="input_server_extra_containers"></a> [server\_extra\_containers](#input\_server\_extra\_containers) | List of extra server containers | `any` | `[]` | no |
| <a name="input_server_image_repository"></a> [server\_image\_repository](#input\_server\_image\_repository) | Server image repository | `string` | `"vault"` | no |
| <a name="input_server_image_tag"></a> [server\_image\_tag](#input\_server\_image\_tag) | Server image tag | `string` | `"1.7.3"` | no |
| <a name="input_server_labels"></a> [server\_labels](#input\_server\_labels) | Labels for server | `map` | `{}` | no |
| <a name="input_server_liveness_probe_enable"></a> [server\_liveness\_probe\_enable](#input\_server\_liveness\_probe\_enable) | Enable server liness probe | `bool` | `true` | no |
| <a name="input_server_liveness_probe_path"></a> [server\_liveness\_probe\_path](#input\_server\_liveness\_probe\_path) | Server liveness probe path | `string` | `"/v1/sys/health?standbyok=true"` | no |
| <a name="input_server_log_format"></a> [server\_log\_format](#input\_server\_log\_format) | Configure the logging format for the Vault server. Supported log formats include: standard, json | `string` | `""` | no |
| <a name="input_server_log_level"></a> [server\_log\_level](#input\_server\_log\_level) | Configure the logging verbosity for the Vault server. Supported log levels include: trace, debug, info, warn, error | `string` | `""` | no |
| <a name="input_server_priority_class_name"></a> [server\_priority\_class\_name](#input\_server\_priority\_class\_name) | Priority class name for server pods | `string` | `""` | no |
| <a name="input_server_readiness_probe_enable"></a> [server\_readiness\_probe\_enable](#input\_server\_readiness\_probe\_enable) | Enable server readiness probe | `bool` | `true` | no |
| <a name="input_server_readiness_probe_path"></a> [server\_readiness\_probe\_path](#input\_server\_readiness\_probe\_path) | Path for server readiness probe | `string` | `""` | no |
| <a name="input_server_replicas"></a> [server\_replicas](#input\_server\_replicas) | Number of replicas. Should be either 3 or 5 for raft | `number` | `5` | no |
| <a name="input_server_resources"></a> [server\_resources](#input\_server\_resources) | Resources for server pods | `map` | <pre>{<br>  "limits": {<br>    "cpu": "250m",<br>    "memory": "256Mi"<br>  },<br>  "requests": {<br>    "cpu": "250m",<br>    "memory": "256Mi"<br>  }<br>}</pre> | no |
| <a name="input_server_secret_env"></a> [server\_secret\_env](#input\_server\_secret\_env) | Extra secret environment variables for server | `list` | `[]` | no |
| <a name="input_server_share_pid"></a> [server\_share\_pid](#input\_server\_share\_pid) | Share PID for server pods | `bool` | `false` | no |
| <a name="input_server_tolerations"></a> [server\_tolerations](#input\_server\_tolerations) | YAML string for server tolerations | `string` | `""` | no |
| <a name="input_server_update_strategy"></a> [server\_update\_strategy](#input\_server\_update\_strategy) | Configure the Update Strategy Type for the StatefulSet. See https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#update-strategies | `string` | `"RollingUpdate"` | no |
| <a name="input_server_volume_mounts"></a> [server\_volume\_mounts](#input\_server\_volume\_mounts) | Extra volume mounts for server | `list` | `[]` | no |
| <a name="input_server_volumes"></a> [server\_volumes](#input\_server\_volumes) | Extra volumes for server | `list` | `[]` | no |
| <a name="input_service_account_annotations"></a> [service\_account\_annotations](#input\_service\_account\_annotations) | Annotations for service account | `map` | `{}` | no |
| <a name="input_service_account_create"></a> [service\_account\_create](#input\_service\_account\_create) | Create service account for server | `bool` | `true` | no |
| <a name="input_service_account_name"></a> [service\_account\_name](#input\_service\_account\_name) | Override name for service account | `string` | `""` | no |
| <a name="input_service_annotations"></a> [service\_annotations](#input\_service\_annotations) | Annotations for the service | `map` | `{}` | no |
| <a name="input_service_type"></a> [service\_type](#input\_service\_type) | Service type for Vault | `string` | `"ClusterIP"` | no |
| <a name="input_storage_bucket_class"></a> [storage\_bucket\_class](#input\_storage\_bucket\_class) | Storage class of the bucket. See https://cloud.google.com/storage/docs/storage-classes | `string` | `"REGIONAL"` | no |
| <a name="input_storage_bucket_labels"></a> [storage\_bucket\_labels](#input\_storage\_bucket\_labels) | Set of labels for the storage bucket | `map` | <pre>{<br>  "terraform": "true"<br>}</pre> | no |
| <a name="input_storage_bucket_location"></a> [storage\_bucket\_location](#input\_storage\_bucket\_location) | Location of the storage bucket. Defaults to the provider's region if empty. This must be in the same location as your KMS key. | `string` | `""` | no |
| <a name="input_storage_bucket_name"></a> [storage\_bucket\_name](#input\_storage\_bucket\_name) | Name of the Storage Bucket to store Vault's state | `string` | `""` | no |
| <a name="input_storage_bucket_project"></a> [storage\_bucket\_project](#input\_storage\_bucket\_project) | Project ID to create the storage bucket under | `string` | `""` | no |
| <a name="input_storage_ha_enabled"></a> [storage\_ha\_enabled](#input\_storage\_ha\_enabled) | Use the GCS bucket to provide HA for Vault. Set to false if you are using alternative HA storage like Consul | `bool` | `true` | no |
| <a name="input_storage_key_name"></a> [storage\_key\_name](#input\_storage\_key\_name) | Name of the Vault storage key | `string` | `"storage"` | no |
| <a name="input_storage_key_rotation_period"></a> [storage\_key\_rotation\_period](#input\_storage\_key\_rotation\_period) | Rotation period of the Vault storage key. Defaults to 90 days | `string` | `"7776000s"` | no |
| <a name="input_sts_annotations"></a> [sts\_annotations](#input\_sts\_annotations) | Annotations for server StatefulSet | `map` | `{}` | no |
| <a name="input_timeout"></a> [timeout](#input\_timeout) | Time in seconds to wait for any individual kubernetes operation. | `number` | `600` | no |
| <a name="input_tls_cert_ca"></a> [tls\_cert\_ca](#input\_tls\_cert\_ca) | PEM encoded CA for Vault | `any` | n/a | yes |
| <a name="input_tls_cert_key"></a> [tls\_cert\_key](#input\_tls\_cert\_key) | PEM encoded private key for Vault | `any` | n/a | yes |
| <a name="input_tls_cert_pem"></a> [tls\_cert\_pem](#input\_tls\_cert\_pem) | PEM encoded certificate for Vault | `any` | n/a | yes |
| <a name="input_tls_cipher_suites"></a> [tls\_cipher\_suites](#input\_tls\_cipher\_suites) | Specifies the list of supported ciphersuites as a comma-separated-list. Make sure this matches the type of key of the TLS certificate you are using. See https://golang.org/src/crypto/tls/cipher_suites.go | `string` | `""` | no |
| <a name="input_ui_active_vault_pod_only"></a> [ui\_active\_vault\_pod\_only](#input\_ui\_active\_vault\_pod\_only) | Only select active vault server pod for UI service | `bool` | `true` | no |
| <a name="input_ui_annotations"></a> [ui\_annotations](#input\_ui\_annotations) | Annotations for UI service | `map` | `{}` | no |
| <a name="input_ui_load_balancer_ip"></a> [ui\_load\_balancer\_ip](#input\_ui\_load\_balancer\_ip) | UI Load balancer IP | `string` | `""` | no |
| <a name="input_ui_load_balancer_source_ranges"></a> [ui\_load\_balancer\_source\_ranges](#input\_ui\_load\_balancer\_source\_ranges) | Load balancer source ranges for UI service | `list` | `[]` | no |
| <a name="input_ui_publish_unready"></a> [ui\_publish\_unready](#input\_ui\_publish\_unready) | Publish unready pod IP address for UI service | `bool` | `false` | no |
| <a name="input_ui_service_enable"></a> [ui\_service\_enable](#input\_ui\_service\_enable) | Enable an additional UI service | `bool` | `false` | no |
| <a name="input_ui_service_node_port"></a> [ui\_service\_node\_port](#input\_ui\_service\_node\_port) | Service node port for UI | `string` | `""` | no |
| <a name="input_ui_service_port"></a> [ui\_service\_port](#input\_ui\_service\_port) | Port for UI service | `number` | `8200` | no |
| <a name="input_ui_service_type"></a> [ui\_service\_type](#input\_ui\_service\_type) | Service Type for UI | `string` | `"ClusterIP"` | no |
| <a name="input_unauthenticated_metrics_access"></a> [unauthenticated\_metrics\_access](#input\_unauthenticated\_metrics\_access) | If set to true, allows unauthenticated access to the /v1/sys/metrics endpoint. | `bool` | `false` | no |
| <a name="input_unseal_key_name"></a> [unseal\_key\_name](#input\_unseal\_key\_name) | Name of the Vault unseal key | `string` | `"unseal"` | no |
| <a name="input_unseal_key_rotation_period"></a> [unseal\_key\_rotation\_period](#input\_unseal\_key\_rotation\_period) | Rotation period of the Vault unseal key. Defaults to 6 months | `string` | `"7776000s"` | no |
| <a name="input_values_file"></a> [values\_file](#input\_values\_file) | Write Helm chart values to file | `string` | `""` | no |
| <a name="input_vault_node_service_account"></a> [vault\_node\_service\_account](#input\_vault\_node\_service\_account) | Service Account for Vault Node Pools if Workload Identity is enabled | `string` | `"vault-gke-node"` | no |
| <a name="input_vault_server_location_description"></a> [vault\_server\_location\_description](#input\_vault\_server\_location\_description) | Location of Vault server to put in description strings of resources | `string` | `""` | no |
| <a name="input_vault_server_service_account"></a> [vault\_server\_service\_account](#input\_vault\_server\_service\_account) | Service Account name for the Vault Server | `string` | `"vault-server"` | no |
| <a name="input_vault_service_account"></a> [vault\_service\_account](#input\_vault\_service\_account) | Required if you did not create a node pool. This should be the service account that is used by the nodes to run Vault workload. They will be given additional permissions to use the keys for auto unseal and to write to the storage bucket | `string` | `"<REQUIRED if not creating GKE node pool>"` | no |
| <a name="input_workload_identity_enable"></a> [workload\_identity\_enable](#input\_workload\_identity\_enable) | Enable Workload Identity on the GKE Node Pool. For more information, see https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity | `bool` | `false` | no |
| <a name="input_workload_identity_project"></a> [workload\_identity\_project](#input\_workload\_identity\_project) | Project to Create the Service Accoutn for Vault Pods  if Workload Identity is enabled. Defaults to the GKE project. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_key_ring_self_link"></a> [key\_ring\_self\_link](#output\_key\_ring\_self\_link) | Self-link of the KMS Keyring created for Vault |
| <a name="output_node_pool_service_account"></a> [node\_pool\_service\_account](#output\_node\_pool\_service\_account) | Email ID of the GKE node pool service account if created |
| <a name="output_release_name"></a> [release\_name](#output\_release\_name) | Release name of the Helm chart |
| <a name="output_storage_key_self_link"></a> [storage\_key\_self\_link](#output\_storage\_key\_self\_link) | Self-link of the KMS Key for storage |
| <a name="output_unseal_key_self_link"></a> [unseal\_key\_self\_link](#output\_unseal\_key\_self\_link) | Self-link of the KMS Key for unseal |
| <a name="output_vault_server_service_account"></a> [vault\_server\_service\_account](#output\_vault\_server\_service\_account) | Email ID of the Vault server Service Account if created |
