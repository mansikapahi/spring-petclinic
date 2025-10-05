variable "env" {
  description = "Environment name (prod/dev/staging)"
  type        = string
  default     = "prod"
}

variable "ecr_image" {
  description = "ECR image URI for PetClinic"
  type        = string
  default     = "688393570742.dkr.ecr.eu-central-1.amazonaws.com/gorillaclinc:v3.5.0"
}

variable "desired_count_min" {
  description = "Min desired tasks for scaling"
  type        = number
  default     = 2
}

variable "desired_count_max" {
  description = "Max desired tasks for scaling"
  type        = number
  default     = 100  # For 30k users
}
