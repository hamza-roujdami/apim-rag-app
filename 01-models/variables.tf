variable "image" {
  description = "Model image tag in ACR (built by build.sh)."
  type        = string
  default     = "ollama-models:latest"
}

variable "app_name" {
  description = "Name of the container group / public DNS label prefix."
  type        = string
  default     = "aci-ollama"
}

variable "cpu" {
  description = "vCPUs for the Ollama container."
  type        = number
  default     = 4
}

variable "memory" {
  description = "Memory (GB) for the Ollama container."
  type        = number
  default     = 8
}

variable "tags" {
  description = "Tags applied to the container group."
  type        = map(string)
  default = {
    project = "apim-rag-poc"
    purpose = "model-serving"
  }
}
