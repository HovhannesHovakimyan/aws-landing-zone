variable "organization_arn" {
  description = "AWS Organizations ARN to associate with the Transit Gateway RAM share"
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)?:organizations::[0-9]{12}:organization/o-[a-z0-9-]+$", trimspace(var.organization_arn)))
    error_message = "organization_arn must be an AWS Organizations ARN in the form arn:aws:organizations::<management-account-id>:organization/o-xxxxxxxxxx."
  }
}
