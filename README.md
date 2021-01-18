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
| terraform | >= 0.12.17 |
| helm | >= 1.0 |
| kubernetes | >= 1.11.4 |

## Providers

| Name | Version |
|------|---------|
| google-beta | n/a |
| helm | >= 1.0 |
| kubernetes | >= 1.11.4 |
| local | n/a |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| agent\_image\_repository | Image repository for the Vault agent that is injected | `string` | `"vault"` | no |
| agent\_image\_tag | Image tag for the Vault agent that is injected | `string` | `"1.5.2"` | no |
| api\_addr | Set the api\_addr configuration for Vault HA. See https://www.vaultproject.io/docs/configuration#api_addr If set to null, this will be set to the Pod IP Address | `any` | `null` | no |
| auth\_path | Mount path of the Kubernetes Auth Engine that the injector will use | `string` | `"auth/kubernetes"` | no |
| chart\_name | Helm chart name to provision | `string` | `"vault"` | no |
| chart\_repository | Helm repository for the chart | `string` | `"https://helm.releases.hashicorp.com"` | no |
| chart\_version | Version of Chart to install. Set to empty to install the latest version | `string` | `"0.8.0"` | no |
| enable\_auth\_delegator | uthDelegator enables a cluster role binding to be attached to the service account.  This cluster role binding can be used to setup Kubernetes auth method. https://www.vaultproject.io/docs/auth/kubernetes.html | `bool` | `true` | no |
| external\_vault\_addr | External vault server address for the injector to use. Setting this will disable deployment of a vault server along with the injector. | `string` | `""` | no |
| fullname\_override | Helm resources full name override | `string` | `""` | no |
| gcs\_extra\_parameters | Additional paramaters for GCS storage. See https://www.vaultproject.io/docs/configuration/storage/google-cloud-storage | `map` | `{}` | no |
| gcs\_storage\_enable | Enable the use of GCS Storage | `any` | n/a | yes |
| gcs\_storage\_use | Use GCS storage in Vault configuration. Setting this to false allows GCS storage resouces to be created but not used with Vault | `bool` | `true` | no |
| gke\_cluster | Cluster to create node pool for | `string` | `"<REQUIRED if gke_pool_create is true>"` | no |
| gke\_disk\_type | Disk type for the nodes | `string` | `"pd-standard"` | no |
| gke\_labels | Labels for the GKE nodes | `map` | `{}` | no |
| gke\_machine\_type | Machine type for the GKE nodes. Make sure this matches the resources you are requesting | `string` | `"n1-standard-2"` | no |
| gke\_metadata | Metadata for the GKE nodes | `map` | `{}` | no |
| gke\_node\_count | Initial Node count. If regional, remember to divide the desired node count by the number of zones | `number` | `3` | no |
| gke\_node\_size\_gb | Disk size for the nodes in GB | `string` | `"20"` | no |
| gke\_node\_upgrade\_settings | Surge upgrade settings as per https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-upgrades#surge | `object({ max_surge = number, max_unavailable = number })` | <pre>{<br>  "max_surge": 1,<br>  "max_unavailable": 0<br>}</pre> | no |
| gke\_node\_upgrade\_settings\_enabled | Enable/disable gke node pool surge upgrade settings | `bool` | `false` | no |
| gke\_pool\_create | Whether to create the GKE node pool or not | `bool` | `false` | no |
| gke\_pool\_location | Location for the node pool | `string` | `"<REQUIRED if gke_pool_create is true>"` | no |
| gke\_pool\_name | Name of the GKE Pool name to create | `string` | `"vault"` | no |
| gke\_tags | Network tags for the GKE nodes | `list` | `[]` | no |
| gke\_taints | List of map of taints for GKE nodes. It is highly recommended you do set this alongside the pods toleration. See https://www.terraform.io/docs/providers/google/r/container_cluster.html#key for the keys and the README for more information | `list` | `[]` | no |
| global\_enabled | Globally enable or disable chart resources | `bool` | `true` | no |
| ingress\_annotations | Annotations for server ingress | `map` | `{}` | no |
| ingress\_enabled | Enable ingress for the server | `bool` | `false` | no |
| ingress\_hosts | Hosts for server ingress | `list` | <pre>[<br>  {<br>    "host": "chart-example.local",<br>    "paths": []<br>  }<br>]</pre> | no |
| ingress\_labels | Labels for server ingress | `map` | `{}` | no |
| ingress\_tls | Configuration for server ingress | `list` | `[]` | no |
| injector\_affinity | YAML string for injector pod affinity | `string` | `""` | no |
| injector\_enabled | Enable Vault Injector | `bool` | `true` | no |
| injector\_env | Extra environment variable for the injector pods | `map` | `{}` | no |
| injector\_failure\_policy | Configures failurePolicy of the webhook. Default behaviour depends on the admission webhook version. See https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/#failure-policy | `any` | `null` | no |
| injector\_image\_repository | Image repository for Vault Injector | `string` | `"hashicorp/vault-k8s"` | no |
| injector\_image\_tag | Image tag for Vault Injector | `string` | `"0.6.0"` | no |
| injector\_log\_format | Log format for the injector. standard or json | `string` | `"standard"` | no |
| injector\_log\_level | Log level for the injector. Supported log levels: trace, debug, error, warn, info | `string` | `"info"` | no |
| injector\_metrics\_enabled | enable a node exporter metrics endpoint at /metrics | `bool` | `false` | no |
| injector\_priority\_class\_name | Priority class name for injector pods | `string` | `""` | no |
| injector\_resources | Resources for the injector | `map` | <pre>{<br>  "limits": {<br>    "cpu": "250m",<br>    "memory": "256Mi"<br>  },<br>  "requests": {<br>    "cpu": "250m",<br>    "memory": "256Mi"<br>  }<br>}</pre> | no |
| injector\_tolerations | YAML string for injector tolerations | `string` | `""` | no |
| key\_ring\_name | Name of the Keyring to create. | `string` | `"vault"` | no |
| kms\_location | Location of the KMS key ring. Must be in the same location as your storage bucket | `any` | n/a | yes |
| kms\_project | Project ID to create the keyring in | `any` | n/a | yes |
| kubernetes\_annotations | Annotations for Kubernetes in general | `map` | `{}` | no |
| kubernetes\_labels | Labels for Kubernetes in general | `map` | <pre>{<br>  "app": "vault",<br>  "terraform": "true"<br>}</pre> | no |
| kubernetes\_namespace | Namespace for Kubernetes resources | `string` | `"default"` | no |
| labels | Labels for GCP resources | `map` | <pre>{<br>  "terraform": "true",<br>  "usage": "vault"<br>}</pre> | no |
| max\_history | Max history for Helm | `number` | `20` | no |
| namespace\_selector | The selector for restricting the webhook to only specific namespaces. See https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/#matching-requests-namespaceselector for more details. | `map` | `{}` | no |
| node\_port | If type is set to 'NodePort', a specific nodePort value can be configured, will be random if left blank. | `string` | `"30000"` | no |
| project\_id | Project ID for GCP Resources | `any` | n/a | yes |
| psp\_annotations | Template YAML string for PSP annotations | `string` | `"seccomp.security.alpha.kubernetes.io/allowedProfileNames: docker/default,runtime/default\napparmor.security.beta.kubernetes.io/allowedProfileNames: runtime/default\nseccomp.security.alpha.kubernetes.io/defaultProfileName:  runtime/default\napparmor.security.beta.kubernetes.io/defaultProfileName:  runtime/default\n"` | no |
| psp\_enabled | Enable PSP | `bool` | `false` | no |
| raft\_backup\_max\_retention\_days | Maximum daily age of the snapshot that is allowed to be kept. | `number` | `14` | no |
| raft\_backup\_policy | Data disk backup policy name | `string` | `"vault-data-backup"` | no |
| raft\_disk\_labels | Override labels for Raft GCE PD resources. Will use `var.labels` if set to null | `map(string)` | `null` | no |
| raft\_disk\_regional | Use regional disks instead of zonal disks | `bool` | `true` | no |
| raft\_disk\_size | Size of Raft disks in GB | `number` | `10` | no |
| raft\_disk\_snapshot\_labels | Override labels for Raft GCE PD snapshot resources. Will use `var.labels` if set to null | `map(string)` | `null` | no |
| raft\_disk\_type | Raft data disk type | `string` | `"pd-ssd"` | no |
| raft\_disk\_zones | List of zones for disks. If not set, will default to the zones in var.region | `list(string)` | `[]` | no |
| raft\_extra\_parameters | Extra parameters for Raft storage | `map` | `{}` | no |
| raft\_persistent\_disks\_prefix | Prefix of the name persistent disks for Vault to create. The prefix will be appended with the index | `string` | `"vault-data-"` | no |
| raft\_region | GCP Region for Raft Disk resources | `string` | `""` | no |
| raft\_replica\_zones | List of replica zones for disks. If not set, will default to the zones in var.region | `list(list(string))` | <pre>[<br>  []<br>]</pre> | no |
| raft\_set\_node\_id | Set Raft Node ID as the name of the vault pod | `bool` | `true` | no |
| raft\_snapshot\_daily | Take snapshot of raft disks daily | `bool` | `true` | no |
| raft\_snapshot\_day\_of\_weeks | Map where the key is the day of the week to take snapshot and the value is the time of the day | `map` | <pre>{<br>  "SUNDAY": "00:00",<br>  "WEDNESDAY": "00:00"<br>}</pre> | no |
| raft\_snapshot\_days\_in\_cycle | Number of days between snapshots for daily snapshots | `number` | `1` | no |
| raft\_snapshot\_enable | Create data disk resource backup policy | `bool` | `true` | no |
| raft\_snapshot\_hourly | Take snapshot of raft disks hourly | `bool` | `false` | no |
| raft\_snapshot\_hours\_in\_cycle | Number of hours between snapshots for hourly snapshots | `number` | `1` | no |
| raft\_snapshot\_start\_time | Time in UTC format to start snapshot. Context depends on whether it's daily or hourly | `string` | `"19:00"` | no |
| raft\_snapshot\_weekly | Take snapshot of raft disks weekly | `bool` | `false` | no |
| raft\_storage\_enable | Enable the use of Raft Storage | `any` | n/a | yes |
| raft\_storage\_use | Use Raft storage in Vault configuration. Setting this to false allows Raft storage resouces to be created but not used with Vault | `bool` | `true` | no |
| release\_name | Helm release name for Vault | `string` | `"vault"` | no |
| revoke\_on\_shutdown | Attempt to revoke Vault Token on injected agent shutdown. | `bool` | `true` | no |
| server\_affinity | Server affinity YAML string | `string` | `"podAntiAffinity:\n  requiredDuringSchedulingIgnoredDuringExecution:\n    - labelSelector:\n        matchLabels:\n          app.kubernetes.io/name: {{ template \"vault.name\" . }}\n          app.kubernetes.io/instance: \"{{ .Release.Name }}\"\n          component: server\n      topologyKey: kubernetes.io/hostname\n"` | no |
| server\_annotations | Annotations for server | `map` | `{}` | no |
| server\_config | Additional server configuration | `map` | `{}` | no |
| server\_env | Server extra environment variables | `map` | `{}` | no |
| server\_extra\_args | Extra args for the server | `string` | `""` | no |
| server\_extra\_containers | Extra containers for Vault server as a raw YAML string | `string` | `""` | no |
| server\_image\_repository | Server image repository | `string` | `"vault"` | no |
| server\_image\_tag | Server image tag | `string` | `"1.5.2"` | no |
| server\_labels | Labels for server | `map` | `{}` | no |
| server\_liveness\_probe\_enable | Enable server liness probe | `bool` | `true` | no |
| server\_liveness\_probe\_path | Server liveness probe path | `string` | `"/v1/sys/health?standbyok=true"` | no |
| server\_priority\_class\_name | Priority class name for server pods | `string` | `""` | no |
| server\_readiness\_probe\_enable | Enable server readiness probe | `bool` | `true` | no |
| server\_readiness\_probe\_path | Path for server readiness probe | `string` | `""` | no |
| server\_replicas | Number of replicas. Should be either 3 or 5 for raft | `number` | `5` | no |
| server\_resources | Resources for server pods | `map` | <pre>{<br>  "limits": {<br>    "cpu": "250m",<br>    "memory": "256Mi"<br>  },<br>  "requests": {<br>    "cpu": "250m",<br>    "memory": "256Mi"<br>  }<br>}</pre> | no |
| server\_secret\_env | Extra secret environment variables for server | `list` | `[]` | no |
| server\_share\_pid | Share PID for server pods | `bool` | `false` | no |
| server\_tolerations | YAML string for server tolerations | `string` | `""` | no |
| server\_update\_strategy | Configure the Update Strategy Type for the StatefulSet. See https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#update-strategies | `string` | `"RollingUpdate"` | no |
| server\_volumes | Extra volumes for server | `list` | `[]` | no |
| service\_account\_annotations | Annotations for service account | `map` | `{}` | no |
| service\_account\_create | Create service account for server | `bool` | `true` | no |
| service\_account\_name | Override name for service account | `string` | `""` | no |
| service\_annotations | Annotations for the service | `map` | `{}` | no |
| service\_type | Service type for Vault | `string` | `"ClusterIP"` | no |
| storage\_bucket\_class | Storage class of the bucket. See https://cloud.google.com/storage/docs/storage-classes | `string` | `"REGIONAL"` | no |
| storage\_bucket\_labels | Set of labels for the storage bucket | `map` | <pre>{<br>  "terraform": "true"<br>}</pre> | no |
| storage\_bucket\_location | Location of the storage bucket. Defaults to the provider's region if empty. This must be in the same location as your KMS key. | `string` | `""` | no |
| storage\_bucket\_name | Name of the Storage Bucket to store Vault's state | `string` | `""` | no |
| storage\_bucket\_project | Project ID to create the storage bucket under | `string` | `""` | no |
| storage\_ha\_enabled | Use the GCS bucket to provide HA for Vault. Set to false if you are using alternative HA storage like Consul | `bool` | `true` | no |
| storage\_key\_name | Name of the Vault storage key | `string` | `"storage"` | no |
| storage\_key\_rotation\_period | Rotation period of the Vault storage key. Defaults to 90 days | `string` | `"7776000s"` | no |
| sts\_annotations | Annotations for server StatefulSet | `map` | `{}` | no |
| timeout | Time in seconds to wait for any individual kubernetes operation. | `number` | `600` | no |
| tls\_cert\_ca | PEM encoded CA for Vault | `any` | n/a | yes |
| tls\_cert\_key | PEM encoded private key for Vault | `any` | n/a | yes |
| tls\_cert\_pem | PEM encoded certificate for Vault | `any` | n/a | yes |
| tls\_cipher\_suites | Specifies the list of supported ciphersuites as a comma-separated-list. Make sure this matches the type of key of the TLS certificate you are using. See https://golang.org/src/crypto/tls/cipher_suites.go | `string` | `""` | no |
| ui\_active\_vault\_pod\_only | Only select active vault server pod for UI service | `bool` | `true` | no |
| ui\_annotations | Annotations for UI service | `map` | `{}` | no |
| ui\_load\_balancer\_ip | UI Load balancer IP | `string` | `""` | no |
| ui\_load\_balancer\_source\_ranges | Load balancer source ranges for UI service | `list` | `[]` | no |
| ui\_publish\_unready | Publish unready pod IP address for UI service | `bool` | `false` | no |
| ui\_service\_enable | Enable an additional UI service | `bool` | `false` | no |
| ui\_service\_node\_port | Service node port for UI | `string` | `""` | no |
| ui\_service\_port | Port for UI service | `number` | `8200` | no |
| ui\_service\_type | Service Type for UI | `string` | `"ClusterIP"` | no |
| unauthenticated\_metrics\_access | If set to true, allows unauthenticated access to the /v1/sys/metrics endpoint. | `bool` | `false` | no |
| unseal\_key\_name | Name of the Vault unseal key | `string` | `"unseal"` | no |
| unseal\_key\_rotation\_period | Rotation period of the Vault unseal key. Defaults to 6 months | `string` | `"7776000s"` | no |
| values\_file | Write Helm chart values to file | `string` | `""` | no |
| vault\_node\_service\_account | Service Account for Vault Node Pools if Workload Identity is enabled | `string` | `"vault-gke-node"` | no |
| vault\_server\_location\_description | Location of Vault server to put in description strings of resources | `string` | `""` | no |
| vault\_server\_service\_account | Service Account name for the Vault Server | `string` | `"vault-server"` | no |
| vault\_service\_account | Required if you did not create a node pool. This should be the service account that is used by the nodes to run Vault workload. They will be given additional permissions to use the keys for auto unseal and to write to the storage bucket | `string` | `"<REQUIRED if not creating GKE node pool>"` | no |
| workload\_identity\_enable | Enable Workload Identity on the GKE Node Pool. For more information, see https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity | `bool` | `false` | no |
| workload\_identity\_project | Project to Create the Service Accoutn for Vault Pods  if Workload Identity is enabled. Defaults to the GKE project. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| key\_ring\_self\_link | Self-link of the KMS Keyring created for Vault |
| node\_pool\_service\_account | Email ID of the GKE node pool service account if created |
| release\_name | Release name of the Helm chart |
| storage\_key\_self\_link | Self-link of the KMS Key for storage |
| unseal\_key\_self\_link | Self-link of the KMS Key for unseal |
| vault\_server\_service\_account | Email ID of the Vault server Service Account if created |
