terraform {
  required_version = ">= 0.12.17"

  required_providers {
    helm       = ">= 1.0"
    kubernetes = ">= 1.11.4"
  }
}
