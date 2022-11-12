
####################################################
# hub1
####################################################

# vnet peerings
#----------------------------

# spoke2-to-hub1

resource "azurerm_virtual_network_peering" "spoke2_to_hub1_peering" {
  resource_group_name          = azurerm_resource_group.rg.name
  name                         = "${local.prefix}-spoke2-to-hub1-peering"
  virtual_network_name         = azurerm_virtual_network.spoke2_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.hub1_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# spoke3-to-hub1

resource "azurerm_virtual_network_peering" "spoke3_to_hub1_peering" {
  resource_group_name          = azurerm_resource_group.rg.name
  name                         = "${local.prefix}-spoke3-to-hub1-peering"
  virtual_network_name         = azurerm_virtual_network.spoke3_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.hub1_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# hub1-to-spoke2

resource "azurerm_virtual_network_peering" "hub1_to_spoke2_peering" {
  resource_group_name          = azurerm_resource_group.rg.name
  name                         = "${local.prefix}-hub1-to-spoke2-peering"
  virtual_network_name         = azurerm_virtual_network.hub1_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke2_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# hub1-to-spoke3

resource "azurerm_virtual_network_peering" "hub1_to_spoke3_peering" {
  resource_group_name          = azurerm_resource_group.rg.name
  name                         = "${local.prefix}-hub1-to-spoke3-peering"
  virtual_network_name         = azurerm_virtual_network.hub1_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke3_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# nva
#----------------------------

# config

resource "local_file" "hub1_router" {
  content  = local.hub1_router_init
  filename = "_output/hub1-router.sh"
}

locals {
  hub1_router_init = templatefile("../scripts/nva-hub.sh", {
    LOCAL_ASN = local.hub1_nva_asn
    LOOPBACK0 = local.hub1_nva_loopback0
    INT_ADDR  = local.hub1_nva_addr
    VPN_PSK   = local.psk
    TUNNELS   = []

    STATIC_ROUTES = [
      { network = "0.0.0.0", mask = "0.0.0.0", next_hop = local.hub1_default_gw_nva },
      { network = local.vhub1_router_bgp0, mask = "255.255.255.255", next_hop = local.hub1_default_gw_nva },
      { network = local.vhub1_router_bgp1, mask = "255.255.255.255", next_hop = local.hub1_default_gw_nva },
      {
        network  = cidrhost(local.spoke2_address_space[0], 0),
        mask     = cidrnetmask(local.spoke2_address_space[0])
        next_hop = local.hub1_default_gw_nva
      },
      {
        network  = cidrhost(local.spoke3_address_space[0], 0),
        mask     = cidrnetmask(local.spoke3_address_space[0])
        next_hop = local.hub1_default_gw_nva
      },
    ]

    BGP_SESSIONS = [
      { peer_asn = local.vhub1_bgp_asn, peer_ip = local.vhub1_router_bgp0, ebgp_multihop = true },
      { peer_asn = local.vhub1_bgp_asn, peer_ip = local.vhub1_router_bgp1, ebgp_multihop = true },
    ]

    BGP_ADVERTISED_NETWORKS = [
      { network = cidrhost(local.spoke2_address_space[0], 0), mask = cidrnetmask(local.spoke2_address_space[0]) },
      { network = cidrhost(local.spoke3_address_space[0], 0), mask = cidrnetmask(local.spoke3_address_space[0]) },
    ]
  })
}

module "hub1_nva" {
  source               = "../modules/csr-hub"
  resource_group       = azurerm_resource_group.rg.name
  name                 = "${local.hub1_prefix}nva"
  location             = local.hub1_location
  enable_ip_forwarding = true
  enable_public_ip     = true
  subnet               = azurerm_subnet.hub1_subnets["${local.hub1_prefix}nva"].id
  private_ip           = local.hub1_nva_addr
  storage_account      = azurerm_storage_account.region1
  admin_username       = local.username
  admin_password       = local.password
  custom_data          = base64encode(local.hub1_router_init)
}

# udr (region1)
#----------------------------

# route table

resource "azurerm_route_table" "rt_region1" {
  resource_group_name = azurerm_resource_group.rg.name
  name                = "${local.prefix}-rt-region1"
  location            = local.region1

  disable_bgp_route_propagation = true
  depends_on = [
    time_sleep.rt_spoke_region1,
  ]
}

# routes

resource "azurerm_route" "default_route_hub1" {
  name                   = "${local.prefix}-default-route-hub1"
  resource_group_name    = azurerm_resource_group.rg.name
  route_table_name       = azurerm_route_table.rt_region1.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = module.hub1_nva.interface.ip_configuration[0].private_ip_address
}

# association

resource "azurerm_subnet_route_table_association" "spoke2_default_route_hub1" {
  subnet_id      = azurerm_subnet.spoke2_subnets["${local.spoke2_prefix}main"].id
  route_table_id = azurerm_route_table.rt_region1.id
}

resource "azurerm_subnet_route_table_association" "spoke3_default_route_hub1" {
  subnet_id      = azurerm_subnet.spoke3_subnets["${local.spoke3_prefix}main"].id
  route_table_id = azurerm_route_table.rt_region1.id
}

####################################################
# vhub1
####################################################

# vpn-site connections
#----------------------------

resource "azurerm_vpn_gateway_connection" "vhub1_site_branch1_conn" {
  name                      = "${local.vhub1_prefix}site-branch1-conn"
  vpn_gateway_id            = azurerm_vpn_gateway.vhub1.id
  remote_vpn_site_id        = azurerm_vpn_site.vhub1_site_branch1.id
  internet_security_enabled = false
  vpn_link {
    name             = "${local.vhub1_prefix}site-branch1-conn-vpn-link-0"
    bgp_enabled      = true
    shared_key       = local.psk
    vpn_site_link_id = azurerm_vpn_site.vhub1_site_branch1.link[0].id
  }
}

# vnet connections
#----------------------------

resource "azurerm_virtual_hub_connection" "spoke1_vnet_conn" {
  name                      = "${local.vhub1_prefix}spoke1-vnet-conn"
  virtual_hub_id            = azurerm_virtual_hub.vhub1.id
  remote_virtual_network_id = azurerm_virtual_network.spoke1_vnet.id
}

resource "azurerm_virtual_hub_connection" "hub1_vnet_conn" {
  name                      = "${local.vhub1_prefix}hub1-vnet-conn"
  virtual_hub_id            = azurerm_virtual_hub.vhub1.id
  remote_virtual_network_id = azurerm_virtual_network.hub1_vnet.id
}

# bgp connection
#----------------------------

resource "azurerm_virtual_hub_bgp_connection" "vhub1_hub1_bgp_conn" {
  name           = "${local.vhub1_prefix}hub1-bgp-conn"
  virtual_hub_id = azurerm_virtual_hub.vhub1.id
  peer_asn       = local.hub1_nva_asn
  peer_ip        = local.hub1_nva_addr

  virtual_network_connection_id = azurerm_virtual_hub_connection.hub1_vnet_conn.id
}