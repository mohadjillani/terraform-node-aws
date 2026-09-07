variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "availability_zones" {
  type    = list(string)
  default = ["eu-west-1a", "eu-west-1b"]
}

variable "container_image" {
  description = "The image to deploy. CI passes the digest of the commit being deployed."
  type        = string
}

variable "certificate_arn" {
  type    = string
  default = null
}
