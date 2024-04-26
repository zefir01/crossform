resource "aws_route53_zone" "zone" {
  name = var.zone
}

module "this" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 3.0"

  domain_name = aws_route53_zone.zone.name
  zone_id     = aws_route53_zone.zone.id

  subject_alternative_names = [
    "*.${aws_route53_zone.zone.name}",
  ]

  wait_for_validation = true

  tags = {
    Environment = terraform.workspace
  }
}