variable "name" {
  type = string
}

variable "price_class" {
  description = "Which edge locations CloudFront uses. PriceClass_100 is North America and Europe."
  type        = string
  default     = "PriceClass_100"
}

variable "certificate_arn" {
  description = "ACM certificate, which must be in us-east-1 for CloudFront. Null uses the default CloudFront domain."
  type        = string
  default     = null
}

variable "aliases" {
  description = "Custom domains served by this distribution."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
