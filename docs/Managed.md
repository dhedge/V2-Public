Role manage contract

# Functions:
- [`isMemberAllowed(address member)`](#Managed-isMemberAllowed-address-)
- [`getMembers()`](#Managed-getMembers--)
- [`changeManager(address newManager, string newManagerName)`](#Managed-changeManager-address-string-)
- [`addMembers(address[] members)`](#Managed-addMembers-address---)
- [`removeMembers(address[] members)`](#Managed-removeMembers-address---)
- [`addMember(address member)`](#Managed-addMember-address-)
- [`removeMember(address member)`](#Managed-removeMember-address-)
- [`trader()`](#Managed-trader--)
- [`setTrader(address newTrader)`](#Managed-setTrader-address-)
- [`removeTrader()`](#Managed-removeTrader--)
- [`numberOfMembers()`](#Managed-numberOfMembers--)

# Events:
- [`ManagerUpdated(address newManager, string newManagerName)`](#Managed-ManagerUpdated-address-string-)




# Function `isMemberAllowed(address member) → bool` {#Managed-isMemberAllowed-address-}
Return boolean if the address is a member of the list


## Parameters:
- `member`: The address of the member


## Return Values:
- Ture if the address is a member of the list, false otherwise


# Function `getMembers() → address[] members` {#Managed-getMembers--}
Get a list of members



## Return Values:
- members Array of member addresses


# Function `changeManager(address newManager, string newManagerName)` {#Managed-changeManager-address-string-}
change the manager address


## Parameters:
- `newManager`: The address of the new manager

- `newManagerName`: The name of the new manager



# Function `addMembers(address[] members)` {#Managed-addMembers-address---}
add a list of members


## Parameters:
- `members`: Array of member addresses



# Function `removeMembers(address[] members)` {#Managed-removeMembers-address---}
remove a list of members


## Parameters:
- `members`: Array of member addresses



# Function `addMember(address member)` {#Managed-addMember-address-}
add a member


## Parameters:
- `member`: The address of the member



# Function `removeMember(address member)` {#Managed-removeMember-address-}
remove a member


## Parameters:
- `member`: The address of the member



# Function `trader() → address` {#Managed-trader--}
Return the address of the trader



## Return Values:
- Address of the trader


# Function `setTrader(address newTrader)` {#Managed-setTrader-address-}
Set the address of the trader


## Parameters:
- `newTrader`: The address of the new trader



# Function `removeTrader()` {#Managed-removeTrader--}
Remove the trader




# Function `numberOfMembers() → uint256 _numberOfMembers` {#Managed-numberOfMembers--}
Return the number of members



## Return Values:
- _numberOfMembers The number of members






# Event `ManagerUpdated(address newManager, string newManagerName)` {#Managed-ManagerUpdated-address-string-}
No description

