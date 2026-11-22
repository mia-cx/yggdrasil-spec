terraform {
  # Ephemeral resources and write-only attributes keep the database password
  # out of state; OpenTofu has both since 1.11.
  required_version = ">= 1.11.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.12.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }
  }

  # Created once by hand (README step 1): state can't live in a bucket this
  # configuration manages.
  backend "gcs" {
    bucket = "textile-515510-tofu-state"
    prefix = "textile-gcp"
  }
}
