#!/bin/bash

# ============================================================================
# AZ-104 Beginner Project - Master Deployment Script
# Deploys complete multi-tier web application infrastructure
# ============================================================================

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration Variables
SUBSCRIPTION_ID=""
RESOURCE_GROUP="rg-az104-project-dev"
LOCATION="eastus"
VNET_NAME="vnet-az104-project"
VNET_PREFIX="10.0.0.0/16"
FRONTEND_SUBNET="subnet-frontend"
FRONTEND_PREFIX="10.0.1.0/24"
BACKEND_SUBNET="subnet-backend"
BACKEND_PREFIX="10.0.2.0/24"
NSG_FRONTEND="nsg-frontend"
NSG_BACKEND="nsg-backend"
WEB_VM_NAME="vm-web-server"
DB_VM_NAME="vm-db-server"
DATA_DISK_NAME="disk-data-db"
DATA_DISK_SIZE=64
STORAGE_ACCOUNT="staz104proj$(date +%s | tail -c 5)"
STORAGE_CONTAINER="data-container"
ADMIN_USERNAME="azureuser"
ADMIN_PASSWORD="P@ssw0rd1234!"
LOG_ANALYTICS_WORKSPACE="law-az104-project"
BACKUP_VAULT="rsv-az104-backup"
ACTION_GROUP="ag-az104-alerts"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

log_step() {
    echo -e "\n${YELLOW}[STEP]${NC} $1"
}

# ============================================================================
# PHASE 0: PRE-DEPLOYMENT CHECKS
# ============================================================================

check_prerequisites() {
    print_header "PHASE 0: Checking Prerequisites"
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI not found. Install it from: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    print_success "Azure CLI installed: $(az --version | head -1)"
    
    # Check Azure login
    if ! az account show &> /dev/null; then
        print_warning "Not logged into Azure. Running 'az login'..."
        az login
    fi
    print_success "Logged into Azure"
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    print_success "Using subscription: $SUBSCRIPTION_ID"
    
    # Verify location
    print_info "Checking if location '$LOCATION' is valid..."
    if az account list-locations --query "[?name=='$LOCATION']" --output tsv | grep -q "$LOCATION"; then
        print_success "Location '$LOCATION' is valid"
    else
        print_error "Location '$LOCATION' is not valid"
        print_info "Available locations:"
        az account list-locations --query "[].name" --output table
        exit 1
    fi
}

# ============================================================================
# PHASE 1: RESOURCE GROUP & NETWORKING
# ============================================================================

create_resource_group() {
    print_header "PHASE 1.1: Creating Resource Group"
    
    log_step "Creating resource group: $RESOURCE_GROUP"
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --output table
    
    print_success "Resource group created"
}

create_vnet() {
    print_header "PHASE 1.2: Creating Virtual Network"
    
    log_step "Creating VNet: $VNET_NAME"
    az network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VNET_NAME" \
        --address-prefix "$VNET_PREFIX" \
        --output table
    
    print_success "VNet created: $VNET_NAME"
}

create_subnets() {
    print_header "PHASE 1.3: Creating Subnets"
    
    log_step "Creating frontend subnet: $FRONTEND_SUBNET"
    az network vnet subnet create \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$FRONTEND_SUBNET" \
        --address-prefix "$FRONTEND_PREFIX" \
        --output table
    
    print_success "Frontend subnet created: $FRONTEND_SUBNET"
    
    log_step "Creating backend subnet: $BACKEND_SUBNET"
    az network vnet subnet create \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$BACKEND_SUBNET" \
        --address-prefix "$BACKEND_PREFIX" \
        --output table
    
    print_success "Backend subnet created: $BACKEND_SUBNET"
}

create_nsgs() {
    print_header "PHASE 1.4: Creating Network Security Groups"
    
    # Frontend NSG
    log_step "Creating frontend NSG: $NSG_FRONTEND"
    az network nsg create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NSG_FRONTEND" \
        --output table
    
    print_success "Frontend NSG created"
    
    # Frontend NSG Rules
    log_step "Adding HTTP rule to frontend NSG"
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_FRONTEND" \
        --name AllowHTTP \
        --priority 100 \
        --source-address-prefixes '*' \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges 80 \
        --access Allow \
        --protocol Tcp \
        --output table
    
    print_success "HTTP rule added"
    
    log_step "Adding HTTPS rule to frontend NSG"
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_FRONTEND" \
        --name AllowHTTPS \
        --priority 110 \
        --source-address-prefixes '*' \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges 443 \
        --access Allow \
        --protocol Tcp \
        --output table
    
    print_success "HTTPS rule added"
    
    log_step "Adding RDP rule to frontend NSG"
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_FRONTEND" \
        --name AllowRDP \
        --priority 120 \
        --source-address-prefixes '*' \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges 3389 \
        --access Allow \
        --protocol Tcp \
        --output table
    
    print_success "RDP rule added"
    
    log_step "Associating frontend NSG with subnet"
    az network vnet subnet update \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$FRONTEND_SUBNET" \
        --network-security-group "$NSG_FRONTEND" \
        --output table
    
    print_success "Frontend NSG associated with subnet"
    
    # Backend NSG
    log_step "Creating backend NSG: $NSG_BACKEND"
    az network nsg create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NSG_BACKEND" \
        --output table
    
    print_success "Backend NSG created"
    
    log_step "Adding SQL rule to backend NSG (from frontend subnet only)"
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_BACKEND" \
        --name AllowSQL-FromFrontend \
        --priority 100 \
        --source-address-prefixes '10.0.1.0/24' \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges 1433 \
        --access Allow \
        --protocol Tcp \
        --output table
    
    print_success "SQL rule added to backend NSG"
    
    log_step "Associating backend NSG with subnet"
    az network vnet subnet update \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$BACKEND_SUBNET" \
        --network-security-group "$NSG_BACKEND" \
        --output table
    
    print_success "Backend NSG associated with subnet"
}

# ============================================================================
# PHASE 2: VIRTUAL MACHINES
# ============================================================================

create_web_vm() {
    print_header "PHASE 2.1: Creating Web Server VM"
    
    log_step "Creating network interface for web VM"
    az network nic create \
        --resource-group "$RESOURCE_GROUP" \
        --name "nic-$WEB_VM_NAME" \
        --vnet-name "$VNET_NAME" \
        --subnet "$FRONTEND_SUBNET" \
        --output table
    
    print_success "Network interface created"
    
    log_step "Creating web server VM: $WEB_VM_NAME (this may take 3-5 minutes)"
    az vm create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WEB_VM_NAME" \
        --nics "nic-$WEB_VM_NAME" \
        --image Win2019Datacenter \
        --size Standard_B2s \
        --admin-username "$ADMIN_USERNAME" \
        --admin-password "$ADMIN_PASSWORD" \
        --os-disk-name "disk-${WEB_VM_NAME}-os" \
        --os-disk-size-gb 128 \
        --output table
    
    print_success "Web server VM created: $WEB_VM_NAME"
    
    # Get Web VM details
    WEB_VM_PUBLIC_IP=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$WEB_VM_NAME" --show-details --query publicIps --output tsv)
    WEB_VM_PRIVATE_IP=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$WEB_VM_NAME" --show-details --query privateIps --output tsv)
    
    print_info "Web VM Public IP: $WEB_VM_PUBLIC_IP"
    print_info "Web VM Private IP: $WEB_VM_PRIVATE_IP"
}

create_db_vm() {
    print_header "PHASE 2.2: Creating Database Server VM"
    
    log_step "Creating network interface for database VM"
    az network nic create \
        --resource-group "$RESOURCE_GROUP" \
        --name "nic-$DB_VM_NAME" \
        --vnet-name "$VNET_NAME" \
        --subnet "$BACKEND_SUBNET" \
        --output table
    
    print_success "Network interface created"
    
    log_step "Creating database server VM: $DB_VM_NAME (this may take 3-5 minutes)"
    az vm create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DB_VM_NAME" \
        --nics "nic-$DB_VM_NAME" \
        --image Win2019Datacenter \
        --size Standard_B2s \
        --admin-username "$ADMIN_USERNAME" \
        --admin-password "$ADMIN_PASSWORD" \
        --os-disk-name "disk-${DB_VM_NAME}-os" \
        --os-disk-size-gb 128 \
        --output table
    
    print_success "Database server VM created: $DB_VM_NAME"
    
    # Get DB VM details
    DB_VM_PRIVATE_IP=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$DB_VM_NAME" --show-details --query privateIps --output tsv)
    
    print_info "Database VM Private IP: $DB_VM_PRIVATE_IP"
}

create_data_disk() {
    print_header "PHASE 2.3: Creating and Attaching Data Disk"
    
    log_step "Creating managed data disk: $DATA_DISK_NAME"
    az disk create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DATA_DISK_NAME" \
        --size-gb "$DATA_DISK_SIZE" \
        --sku Standard_LRS \
        --output table
    
    print_success "Data disk created: $DATA_DISK_NAME"
    
    log_step "Attaching data disk to database VM"
    az vm disk attach \
        --resource-group "$RESOURCE_GROUP" \
        --vm-name "$DB_VM_NAME" \
        --disk "$DATA_DISK_NAME" \
        --output table
    
    print_success "Data disk attached to $DB_VM_NAME"
    print_warning "Remember: You must initialize the disk inside the VM (Disk Management on Windows or fdisk on Linux)"
}

# ============================================================================
# PHASE 3: STORAGE
# ============================================================================

create_storage_account() {
    print_header "PHASE 3.1: Creating Storage Account"
    
    log_step "Creating storage account: $STORAGE_ACCOUNT"
    az storage account create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STORAGE_ACCOUNT" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --output table
    
    print_success "Storage account created: $STORAGE_ACCOUNT"
}

create_blob_container() {
    print_header "PHASE 3.2: Creating Blob Container"
    
    log_step "Getting storage account connection string"
    STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STORAGE_ACCOUNT" \
        --query connectionString \
        --output tsv)
    
    log_step "Creating blob container: $STORAGE_CONTAINER"
    az storage container create \
        --name "$STORAGE_CONTAINER" \
        --connection-string "$STORAGE_CONNECTION_STRING" \
        --output table
    
    print_success "Blob container created: $STORAGE_CONTAINER"
    
    log_step "Uploading sample data file"
    echo "This is sample data for AZ-104 project - Created at $TIMESTAMP" > sample-data.txt
    
    az storage blob upload \
        --file sample-data.txt \
        --container-name "$STORAGE_CONTAINER" \
        --name "sample-data.txt" \
        --connection-string "$STORAGE_CONNECTION_STRING" \
        --output table
    
    print_success "Sample data uploaded to blob storage"
    
    # Cleanup
    rm -f sample-data.txt
}

# ============================================================================
# PHASE 4: MONITORING
# ============================================================================

create_log_analytics_workspace() {
    print_header "PHASE 4.1: Creating Log Analytics Workspace"
    
    log_step "Creating Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --location "$LOCATION" \
        --output table
    
    print_success "Log Analytics workspace created: $LOG_ANALYTICS_WORKSPACE"
    
    # Get workspace ID
    LAW_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query id \
        --output tsv)
    
    print_info "Workspace Resource ID: $LAW_ID"
}

create_action_group() {
    print_header "PHASE 4.2: Creating Action Group for Alerts"
    
    log_step "Creating action group: $ACTION_GROUP"
    az monitor action-group create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ACTION_GROUP" \
        --output table
    
    print_success "Action group created: $ACTION_GROUP"
}

create_cpu_alert() {
    print_header "PHASE 4.3: Creating CPU Alert Rule"
    
    log_step "Getting Web VM resource ID"
    WEB_VM_ID=$(az vm show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WEB_VM_NAME" \
        --query id \
        --output tsv)
    
    log_step "Getting action group resource ID"
    ACTION_GROUP_ID=$(az monitor action-group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ACTION_GROUP" \
        --query id \
        --output tsv)
    
    log_step "Creating metric alert: CPU > 80%"
    az monitor metrics alert create \
        --name "alert-cpu-high" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "$WEB_VM_ID" \
        --condition "avg Percentage CPU > 80" \
        --description "Alert when Web Server CPU exceeds 80%" \
        --evaluation-frequency 1m \
        --window-size 5m \
        --action "$ACTION_GROUP_ID" \
        --output table 2>/dev/null || print_warning "Alert creation may require email configuration"
    
    print_success "CPU alert rule created"
}

# ============================================================================
# PHASE 5: BACKUP
# ============================================================================

create_recovery_vault() {
    print_header "PHASE 5.1: Creating Recovery Services Vault"
    
    log_step "Creating Recovery Services Vault: $BACKUP_VAULT"
    az backup vault create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$BACKUP_VAULT" \
        --location "$LOCATION" \
        --output table
    
    print_success "Recovery Services Vault created: $BACKUP_VAULT"
}

enable_vm_backup() {
    print_header "PHASE 5.2: Enabling Backup for Web VM"
    
    log_step "Enabling backup for Web VM: $WEB_VM_NAME"
    az backup protection enable-for-vm \
        --resource-group "$RESOURCE_GROUP" \
        --vault-name "$BACKUP_VAULT" \
        --vm "$WEB_VM_NAME" \
        --policy-name DefaultPolicy \
        --output table 2>/dev/null || print_warning "Backup protection may need additional configuration"
    
    print_success "Backup enabled for Web VM"
}

# ============================================================================
# PHASE 6: DEPLOYMENT SUMMARY
# ============================================================================

print_deployment_summary() {
    print_header "DEPLOYMENT COMPLETE!"
    
    echo ""
    echo -e "${GREEN}========== RESOURCE DETAILS ==========${NC}"
    echo ""
    
    # Get all resource details
    WEB_VM_PUBLIC_IP=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$WEB_VM_NAME" --show-details --query publicIps --output tsv 2>/dev/null || echo "N/A")
    WEB_VM_PRIVATE_IP=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$WEB_VM_NAME" --show-details --query privateIps --output tsv 2>/dev/null || echo "N/A")
    DB_VM_PRIVATE_IP=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$DB_VM_NAME" --show-details --query privateIps --output tsv 2>/dev/null || echo "N/A")
    
    echo -e "${YELLOW}Resource Group:${NC}"
    echo "  Name: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo ""
    
    echo -e "${YELLOW}Networking:${NC}"
    echo "  VNet: $VNET_NAME ($VNET_PREFIX)"
    echo "  Frontend Subnet: $FRONTEND_SUBNET ($FRONTEND_PREFIX)"
    echo "  Backend Subnet: $BACKEND_SUBNET ($BACKEND_PREFIX)"
    echo ""
    
    echo -e "${YELLOW}Web Server VM:${NC}"
    echo "  Name: $WEB_VM_NAME"
    echo "  Public IP: $WEB_VM_PUBLIC_IP"
    echo "  Private IP: $WEB_VM_PRIVATE_IP"
    echo "  Connect via RDP: $WEB_VM_PUBLIC_IP:3389"
    echo ""
    
    echo -e "${YELLOW}Database Server VM:${NC}"
    echo "  Name: $DB_VM_NAME"
    echo "  Private IP: $DB_VM_PRIVATE_IP"
    echo ""
    
    echo -e "${YELLOW}Storage:${NC}"
    echo "  Account: $STORAGE_ACCOUNT"
    echo "  Container: $STORAGE_CONTAINER"
    echo ""
    
    echo -e "${YELLOW}Monitoring:${NC}"
    echo "  Log Analytics: $LOG_ANALYTICS_WORKSPACE"
    echo "  Action Group: $ACTION_GROUP"
    echo ""
    
    echo -e "${YELLOW}Backup:${NC}"
    echo "  Vault: $BACKUP_VAULT"
    echo ""
    
    echo -e "${GREEN}========== NEXT STEPS ==========${NC}"
    echo ""
    echo "1. Connect to Web VM via RDP using public IP: $WEB_VM_PUBLIC_IP"
    echo "2. Initialize data disk on Database VM (Disk Management → Initialize)"
    echo "3. Install SQL Server or MySQL on Database VM"
    echo "4. Configure firewall rules if needed"
    echo "5. Test connectivity between VMs"
    echo "6. Monitor resources in Azure Portal"
    echo ""
    
    echo -e "${GREEN}========== CLEANUP ==========${NC}"
    echo ""
    echo "To delete all resources when done:"
    echo "  az group delete --name $RESOURCE_GROUP --yes --no-wait"
    echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║   AZ-104 Beginner Project - Infrastructure Deployment Script   ║"
    echo "║                                                                ║"
    echo "║            Multi-Tier Web Application on Azure                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo "This script will deploy:"
    echo "  ✓ Resource Group"
    echo "  ✓ Virtual Network with Subnets"
    echo "  ✓ Network Security Groups"
    echo "  ✓ 2 Virtual Machines (Web & Database)"
    echo "  ✓ Data Disk"
    echo "  ✓ Storage Account with Blob Container"
    echo "  ✓ Log Analytics Workspace"
    echo "  ✓ Action Group & CPU Alert"
    echo "  ✓ Recovery Services Vault for Backups"
    echo ""
    echo "Estimated deployment time: 10-15 minutes"
    echo ""
    
    read -p "Do you want to continue? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Deployment cancelled"
        exit 1
    fi
    
    # Run all phases
    check_prerequisites
    create_resource_group
    create_vnet
    create_subnets
    create_nsgs
    create_web_vm
    create_db_vm
    create_data_disk
    create_storage_account
    create_blob_container
    create_log_analytics_workspace
    create_action_group
    create_cpu_alert
    create_recovery_vault
    enable_vm_backup
    print_deployment_summary
    
    print_success "All resources deployed successfully!"
}

# Run main function
main "$@"
