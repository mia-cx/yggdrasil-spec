terraform {
  required_version = ">= 1.11.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.12.0"
    }
  }

  # Created once by hand (README step 1): state can't live in a bucket this
  # configuration manages.
  backend "gcs" {
    bucket = "textile-515510-tofu-state"
    prefix = "textile-gcp"
  }
}
