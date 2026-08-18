variable "vpc_id" {
  description = "ID of the VPC where RDS will be deployed"
  type        = string
}

variable "private_subnet_id" {
  description = "ID of the private subnet for RDS"
  type        = string
}

variable "private_subnet_b_id" {
  description = "ID of the second private subnet for RDS"
  type        = string
}
