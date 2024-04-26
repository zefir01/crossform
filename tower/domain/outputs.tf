output "main_domain" {
  value = aws_route53_zone.zone.name
}

output "public_zone_id" {
  value = aws_route53_zone.zone.id
}