variable "name" {
  description = "Repository name. Lowercase, no slashes unless you want a 'namespace/repo' layout."
  type        = string
}

variable "image_tag_mutability" {
  description = "MUTABLE allows reusing tags (typical for `latest`); IMMUTABLE forbids it (best practice for prod tags)."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Run the basic vulnerability scanner on every push. Free; always on."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "CMK for image encryption. If null, the AES256 default is used."
  type        = string
  default     = null
}

variable "untagged_image_expiry_days" {
  description = "Untagged images deleted after this many days. Untagged images = builds nobody references = wasted storage."
  type        = number
  default     = 7
}

variable "max_tagged_images" {
  description = "Maximum number of tagged images to retain (oldest evicted first)."
  type        = number
  default     = 30
}

variable "tagged_image_prefixes" {
  description = "Tag prefixes that the retention rule for tagged images applies to. ECR requires at least one prefix when filtering by tagStatus=tagged."
  type        = list(string)
  default     = ["v", "release-", "main-", "sha-"]
}

variable "additional_pull_principals" {
  description = "Extra AWS principal ARNs that can pull from this repo (cross-account, etc). The repo's own account always has access."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
