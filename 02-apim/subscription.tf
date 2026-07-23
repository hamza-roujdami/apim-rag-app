# A subscription so clients (the app + k6) have an api-key to call the gateway.
# Scoped to all APIs (no product_id / api_id).
resource "azurerm_api_management_subscription" "poc" {
  api_management_name = local.apim_name
  resource_group_name = local.rg
  display_name        = "poc-test"
  state               = "active"
  allow_tracing       = true
}
