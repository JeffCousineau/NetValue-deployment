variable "subscription_id" {
  type    = string
  default = "0bc9dd71-16c4-428e-8160-8a90c7c892f5"
}
variable "tenant_id" {
  type    = string
  default = "e099407c-b3b3-45aa-868e-cc901f513dc5"
}
variable "owner_object_id" {
  type    = string
  default = "1112bb2c-81d0-4e08-8009-4eab2c6a9b8b"
}
variable "location" {
  type    = string
  default = "canadacentral"
  validation {
    condition     = var.location == "canadacentral"
    error_message = "This reviewed configuration is restricted to Canada Central."
  }
}
variable "free_offer_verified" {
  type        = bool
  default     = false
  description = "Set true only after verifying F1 availability and Azure SQL free offer eligibility in Canada Central for this subscription."
}
locals {
  name     = "netvalue-${substr(sha256(var.subscription_id), 0, 8)}"
  sql_name = "${local.name}-sql"
  tags     = { application = "NetValue", cost_policy = "free-tier-only" }
}
