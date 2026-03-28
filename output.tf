output "cluster_id" {
  value = aws_eks_cluster.capstone_devops.id
}

output "node_group_id" {
  value = aws_eks_node_group.capstone_devops.id
}

output "vpc_id" {
  value = aws_vpc.capstone_devops_vpc.id
}

output "subnet_ids" {
  value = aws_subnet.capstone_devops_subnet[*].id
}