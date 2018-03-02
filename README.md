# Container PKI Janitor

This script is deployed on a Docker Container Host (e.g., _AWS Container Instance_) and manages certificates for all hosted containers. Certificates are automatically requested and revoked on container create/destroy.


## Create Required Permission & Role

    ipa privilege-add "Manage Containers"
    ipa privilege-add-permission "Manage Containers" \
        --permission "Request Certificate" \
        --permission "Revoke Certificate" \
        --permission "Request Certificates from a different host" \
        --permission "Retrieve Certificates from the CA" \
        --permission "System: Add Hosts" \
        --permission "System: Modify Hosts" \
        --permission "System: Remove Hosts" \
        --permission "System: Add Services" \
        --permission "System: Modify Services" \
        --permission "System: Remove Services" \
        --permission "System: Add DNS Entries" \
        --permission "System: Read DNS Configuration" \
        --permission "System: Remove DNS Entries" \
        --permission "System: Update DNS Entries"

    ipa role-add "Container Manager"
    ipa role-add-privilege "Container Manager" --privilege "Manage Containers"


## Assign Roles

   ipa role-add-member "Container Manager" --hosts=ipa3.dev.aws.iis.se
