output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "cluster_nodegroup_id" {
  description = "id of the EKS managed nodegroup"
  value       = module.eks.eks_managed_node_groups["one"].node_group_id
}

output "region" {
  description = "AWS region"
  value       = var.REGION
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = module.eks.cluster_name
}

output "rds_writer_endpoint" {
  description = "RDS Writer Endpoint"
  value       = aws_rds_cluster.hubs_ce_db.endpoint
}

output "efs_id" {
  description = "EFS ID"
  value       = aws_efs_file_system.hubs_ce_efs.id
}