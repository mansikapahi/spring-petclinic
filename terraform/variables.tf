variable "ecr_image" {
  description = "ECR image URI for PetClinic"
  type        = string
  default     = "688393570742.dkr.ecr.eu-central-1.amazonaws.com/gorillaclinc:v3.5.0"
}

variable "desired_count" {
  description = "Number of ECS tasks for HA"
  type        = number
  default     = 2
}
