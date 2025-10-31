data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {}

locals {
  region         = data.aws_region.current.region
  account_id     = data.aws_caller_identity.current.account_id
  region_account = "${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}"
}
