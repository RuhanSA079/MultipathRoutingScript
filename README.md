# MultipathRoutingScript
A simple bash script that will install/uninstall some routing rules for multipath routing. Not to be confused with ECMP

# Disclaimer
The author does not take any responsibility for ANY damages or loss caused by this script (directly or indirectly) to infrastructure, systems, life or capital/income.   
This script is a experimental script.

# Notes
This script has been written to cater for multipath routing, not to be confused with ECMP.   
This allows the router or device to accept/make connections on a cellular interface or ethernet interface, without route-metrics interfering and only one gateway.   
For example, on Ethernet 1, I do have internet access, but on Ethernet 2 as well. Problem is, there is an IP address only reachable from Ethernet 2, not Ethernet 1.   
Linux route-metrics and only one gateway will allow traffic over one gateway. If Ethernet 1 is main gateway, connections will fail to Ethernet 2, sending intended   
traffic over Ethernet 1 gateway, not Ethernet 2's gateway.  

This script aims to solve that by having two or more routing tables (one custom) to solve this issue.   
Both Ethernet 1 and Ethernet 2 can now then make their own connections, or accept their incoming connections.  

# Requirements
Network-Manager version above or on 1.10   
Linux kernel with ADVANCED_ROUTING features enabled   

