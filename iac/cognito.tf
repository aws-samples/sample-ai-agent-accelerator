resource "aws_cognito_user_pool" "main" {
  count = var.enable_authentication ? 1 : 0
  name = var.name

  auto_verified_attributes = ["email"]
  admin_create_user_config {
    allow_admin_create_user_only = true
  }
  
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  schema {
    attribute_data_type = "String"
    name               = "email"
    required           = true
    mutable            = true
  }

  tags = var.tags
}

resource "aws_cognito_user_pool_client" "main" {
  count        = var.enable_authentication ? 1 : 0
  name         = var.name
  user_pool_id = aws_cognito_user_pool.main[0].id

  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  
  callback_urls = var.acm_certificate_arn != "" ? [
    "https://${module.alb.dns_name}/oauth2/idpresponse"
  ] : [
    "http://${module.alb.dns_name}/oauth2/idpresponse"
  ]

  logout_urls = var.acm_certificate_arn != "" ? [
    "https://${module.alb.dns_name}"
  ] : [
    "http://${module.alb.dns_name}"
  ]

  supported_identity_providers = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "main" {
  count        = var.enable_authentication ? 1 : 0
  domain       = "${var.name}-${random_string.cognito_domain[0].result}"
  user_pool_id = aws_cognito_user_pool.main[0].id
}

resource "random_string" "cognito_domain" {
  count   = var.enable_authentication ? 1 : 0
  length  = 8
  special = false
  upper   = false
}