# Container PKI Janitor

This script is deployed on a Docker Container Host (e.g., _AWS Container Instance_) and manages certificates for all hosted containers. Certificates are automatically requested and revoked on container create/destroy.


## Create Required Permission & Role

    ipa privilege-add "Manage Containers"
    ipa privilege-add-permission "Manage Containers" \
        --permission "System: Add Hosts" \
        --permission "System: Modify Hosts" \
        --permission "System: Remove Hosts" \
        --permission "System: Manage Host Certificates" \
        --permission "Request Certificate" \
        --permission "Revoke Certificate" \
        --permission "Retrieve Certificates from the CA" \
        --permission "Request Certificates from a different host"
    ipa role-add "Container Manager"
    ipa role-add-privilege "Container Manager" --privilege "Manage Containers"


## Assign Roles

    ipa role-add-member "Container Manager" --hosts=host.example.com
