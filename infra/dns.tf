data "cloudflare_zone" "bochi" {
  filter = {
    name = local.domain_name
  }
}

resource "cloudflare_dns_record" "bochi_apex" {
  zone_id = data.cloudflare_zone.bochi.id
  name    = "@"
  type    = "CNAME"
  content = aws_lb.bochi.dns_name
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "bochi_wildcard" {
  zone_id = data.cloudflare_zone.bochi.id
  name    = "*"
  type    = "CNAME"
  content = aws_lb.bochi.dns_name
  ttl     = 1
  proxied = true
}

resource "cloudflare_ruleset" "canonical_domain_redirects" {
  zone_id     = data.cloudflare_zone.bochi.id
  name        = "Canonical domain redirects"
  description = "Redirect bochi.app subdomains to the apex domain."
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules = [
    {
      ref         = "redirect_bochi_subdomains_to_apex"
      description = "Redirect all bochi.app subdomains to bochi.app"
      expression  = "(lower(http.host) ne \"${local.domain_name}\" and ends_with(lower(http.host), \".${local.domain_name}\"))"
      action      = "redirect"
      action_parameters = {
        from_value = {
          status_code = 301
          target_url = {
            expression = "concat(\"https://${local.domain_name}\", http.request.uri.path)"
          }
          preserve_query_string = true
        }
      }
    }
  ]
}

resource "cloudflare_dns_record" "acm_validation" {
  for_each = {
    for option in aws_acm_certificate.bochi.domain_validation_options :
    option.domain_name => {
      name    = trimsuffix(option.resource_record_name, ".")
      type    = option.resource_record_type
      content = trimsuffix(option.resource_record_value, ".")
    }
  }

  zone_id = data.cloudflare_zone.bochi.id
  name    = each.value.name
  type    = each.value.type
  content = each.value.content
  ttl     = 1
  proxied = false
}
