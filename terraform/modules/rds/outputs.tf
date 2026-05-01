output "db_endpoint" {
     description = "Endpoint of the database"
     value = aws_db_instance.postgres.address
     sensitive = true
}
output "db_name"     {
     description = "Name of the database"
     value = aws_db_instance.postgres.db_name
}
output "secret_arn"  {
     description = "ARN of the secret"
     value = aws_secretsmanager_secret.db_credentials.arn
}
output "db_instance_id" {
     description = "ID of the database instance"
     value = aws_db_instance.postgres.id
}
