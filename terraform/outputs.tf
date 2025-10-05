output "alb_dns_name" {
  description = "ALB DNS for PetClinic app"
  value       = aws_lb.main.dns_name
}

output "cluster_name" {
  description = "ECS Cluster name"
  value       = aws_ecs_cluster.main.name
}
