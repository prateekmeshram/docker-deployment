# GitHub repository information for cloning the application code
variable "github_username" {
  description = "GitHub username where the repository is hosted"
  type        = string
  default     = "prateekmeshram"
}

variable "key_name" {
  description = "Name of the AWS key pair to use for SSH access"
  type        = string
  default     = "id_rsa"  # Default key name, change as needed  

}

variable "repo_name" {
  description = "Name of the repository containing the Dockerfile"
  type        = string
  default     = "docker-deployment"
}