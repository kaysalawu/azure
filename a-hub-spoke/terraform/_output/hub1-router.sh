Section: IOS configuration

crypto ikev2 proposal AZURE-IKE-PROPOSAL 
encryption aes-cbc-256
integrity sha1
group 2
!
crypto ikev2 policy AZURE-IKE-PROFILE 
proposal AZURE-IKE-PROPOSAL
match address local 10.11.1.9
!
crypto ikev2 keyring AZURE-KEYRING
peer 10.22.1.9
address 10.22.1.9
pre-shared-key changeme
!
crypto ikev2 profile AZURE-IKE-PROPOSAL
match address local 10.11.1.9
match identity remote address 10.22.1.9 255.255.255.255
authentication remote pre-share
authentication local pre-share
keyring local AZURE-KEYRING
lifetime 28800
dpd 10 5 on-demand
!
crypto ipsec transform-set AZURE-IPSEC-TRANSFORM-SET esp-gcm 256 
mode tunnel
!
crypto ipsec profile AZURE-IPSEC-PROFILE
set transform-set AZURE-IPSEC-TRANSFORM-SET 
set ikev2-profile AZURE-IKE-PROPOSAL
set security-association lifetime seconds 3600
!
interface Tunnel0
ip address 10.11.50.1 255.255.255.252
tunnel mode ipsec ipv4
ip tcp adjust-mss 1350
tunnel source 10.11.1.9
tunnel destination 10.22.1.9
tunnel protection ipsec profile AZURE-IPSEC-PROFILE
!
interface Loopback0
ip address 10.11.11.11 255.255.255.255
!
ip route 0.0.0.0 0.0.0.0 10.11.1.1
ip route 10.22.22.22 255.255.255.255 Tunnel0
ip route 10.22.1.9 255.255.255.255 10.11.1.1
ip route 10.11.3.4 255.255.255.255 10.11.1.1
ip route 10.11.3.5 255.255.255.255 10.11.1.1
ip route 10.2.0.0 255.255.0.0 10.11.1.1
ip route 10.3.0.0 255.255.0.0 10.11.1.1
!
router bgp 65000
bgp router-id 10.11.1.9
neighbor 10.11.3.4 remote-as 65515
neighbor 10.11.3.4 ebgp-multihop 255
neighbor 10.11.3.4 soft-reconfiguration inbound
neighbor 10.11.3.4 as-override
neighbor 10.11.3.5 remote-as 65515
neighbor 10.11.3.5 ebgp-multihop 255
neighbor 10.11.3.5 soft-reconfiguration inbound
neighbor 10.11.3.5 as-override
neighbor 10.22.22.22 remote-as 65000
neighbor 10.22.22.22 soft-reconfiguration inbound
neighbor 10.22.22.22 next-hop-self
neighbor 10.22.22.22 update-source Loopback0
network 10.2.0.0 mask 255.255.0.0
network 10.3.0.0 mask 255.255.0.0