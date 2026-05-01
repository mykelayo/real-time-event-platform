locals {
  services = ["api-gateway", "event-producer", "stream-processor", "websocket-server"]
}

resource "aws_ecr_repository" "services" {
  for_each = toset(local.services)

  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
  
  force_delete = true

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name    = "${var.project_name}-${each.key}"
    Service = each.key
  })
}

resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
  rules = [
    {
      rulePriority = 1
      description  = "Expire untagged images after 14 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 14
      }
      action = {
        type = "expire"
      }
    },
    {
      rulePriority = 2  
      description  = "Keep only 10 most recent tagged images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}