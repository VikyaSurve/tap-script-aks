#!/bin/bash
echo "############################ Keep these values handy:   ######################"
echo "############################ Pivnet token, Tanzu network username  ######################"
echo "############################ Tanzu network password, Ingress Domain for CNRS   ######################"
echo "############################ domain name for Learning center, region to deploy AKS Cluster and ACR repo  ######################"
echo "############################ github token, Subscription ID   ######################"
echo "#####################################################################################################"
echo "##### Pivnet Token: login to tanzu network, click on your username in top right corner of the page > select Edit Profile, scroll down and click on Request New Refresh Token ######"
read -p "Enter the Pivnet token: " pivnettoken
read -p "Enter the Tanzu network username: " tanzunetusername
read -p "Enter the Tanzu network password: " tanzunetpassword
read -p "Enter the Ingress Domain for CNRS: " cnrsdomain
read -p "Enter the domain name for Learning center: " domainname
read -p "Enter github token (to be collected from Githubportal): " githubtoken
read -p "Do you want to use existing EKS cluster or create a new one? Type "N" for new, "E" for existing: " clusterconnect
read -p "Do you want to use existing ACR repo or create a new one? Type "N" for new, "E" for existing: " azurerepo
read -p "Enter the Subscription ID: " subscription
echo "#################  Installing AZ cli #####################"
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
echo "#########################################"
echo "################ AZ CLI version #####################"
az --version
echo "#########################################"
echo "############### Install kubectl ##############"
sudo az aks install-cli
echo "############  Kubectl Version #######################"
kubectl version
echo "#####################################################################################################"
echo "#############  Authenticate to AZ cli by following the screen Instructions below #################"
echo "#####################################################################################################"
az login
echo "#########################################"
echo "#########################################"
if [ "$azurerepo" == "E" ];
then
        echo "###### Provide existing ACR details  ######"
	read -p "Enter ACR Login server Name: " acrloginserver
	read -p "Enter ACR Login server username: " acrusername
	read -p "Enter ACR Login server password: " acrpassword
else
         read -p "Enter the region to create ACR  : " regionacr
	 echo "###### Create RG for Repo  ######"
	 az group create --name tap-imagerepo-RG --location $regionacr
	 echo "####### Create container registry  ############"
         echo "#####################################################################################################"
	 az acr create --resource-group tap-imagerepo-RG --name tapdemoacr --sku Standard
	 echo "####### Fetching acr Admin credentials ##########"
	 az acr update -n tapdemoacr --admin-enabled true
         acrusername=$(az acr credential show --name tapdemoacr --query "username" -o tsv)
         acrloginserver=$(az acr show --name tapdemoacr --query loginServer -o tsv)
         acrpassword=$(az acr credential show --name tapdemoacr --query passwords[0].value -o tsv)
         if grep -q "/"  <<< "$acrpassword";
             then
	        acrpassword1=$(az acr credential show --name tapdemoacr --query passwords[1].value -o tsv)
	        if grep -q "/"  <<< "$acrpassword1";
	          then
                	   echo "##########################################################################"
		  	   echo "Update the password manually in tap-values file(repopassword): password is $acrpassword1 "
                  	   echo "###########################################################################"
	        else
		   acrpassword=$acrpassword1
	        fi
         else
   	          echo "Password Updated in tap values file"
         fi

fi
if [ "$clusterconnect" == "N" ];
then
         read -p "Enter the region to deploy EKS Cluster: " regioneks
	 echo "#########################################"
         echo "Resource group created with name tap-cluster-RG in region and subscription mentioned above"
         echo "#########################################"
	 az group create --name tap-cluster-RG --location $regioneks --subscription $subscription
         echo "#########################################"
	 echo "Creating AKS cluster with 1 node and sku as Standard_D8S_v3, can be changed if required"
         echo "#########################################"
         az aks create --resource-group tap-cluster-RG --name tap-cluster-1 --subscription $subscription --node-count 2 --enable-addons monitoring --generate-ssh-keys --node-vm-size Standard_D8S_v3 -z 1 --enable-cluster-autoscaler --min-count 1 --max-count 2
         echo "############### Created AKS Cluster ###############"
	 echo "############### Set the context ###############"
	 az account set --subscription $subscription
	 az aks get-credentials --resource-group tap-cluster-RG --name tap-cluster-1
	 echo "############## Verify the nodes #################"
	 echo "#####################################################################################################"
	 kubectl get nodes
         echo "#####################################################################################################"
else
        az account set --subscription $subscription
        read -p "Provide the AKS cluster resource group: " aksclusterresourcegroup
        read -p "Provide the AKS cluster name: " aksclustername
        az aks get-credentials --resource-group aksclusterresourcegroup --name aksclustername
fi
	 echo "######### Preparing the tap-values file ##########"
         sed -i -r "s/tanzunetusername/$tanzunetusername/g" "$HOME/tap-script-aks/tap-values.yaml"
         sed -i -r "s/tanzunetpassword/$tanzunetpassword/g" "$HOME/tap-script-aks/tap-values.yaml"
         sed -i -r "s/registryname/$acrloginserver/g" "$HOME/tap-script-aks/tap-values.yaml"
         sed -i -r "s/repousername/$acrusername/g" "$HOME/tap-script-aks/tap-values.yaml"
         sed -i -r "s/repopassword/$acrpassword/g" "$HOME/tap-script-aks/tap-values.yaml"
         sed -i -r "s/domainname/$domainname/g" "$HOME/tap-script-aks/tap-values.yaml"
         sed -i -r "s/githubtoken/$githubtoken/g" "$HOME/tap-script-aks/tap-values.yaml"
         sed -i -r "s/cnrsdomain/$cnrsdomain/g" "$HOME/tap-script-aks/tap-values.yaml"
         echo "#####################################################################################################"
         echo "########### Creating Secrets in tap-install namespace  #############"
         kubectl create ns tap-install
         kubectl create secret docker-registry registry-credentials --docker-server=$acrloginserver --docker-username=$acrusername --docker-password=$acrpassword -n tap-install
echo "############# Installing Pivnet ###########"
wget https://github.com/pivotal-cf/pivnet-cli/releases/download/v3.0.1/pivnet-linux-amd64-3.0.1
chmod +x pivnet-linux-amd64-3.0.1
sudo mv pivnet-linux-amd64-3.0.1 /usr/local/bin/pivnet
echo "########## Installing Tanzu CLI  #############"
pivnet login --api-token=${pivnettoken}
pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version='1.3.0' --product-file-id=1330470
mkdir $HOME/tanzu-cluster-essentials
tar -xvf tanzu-cluster-essentials-linux-amd64-1.3.0.tgz -C $HOME/tanzu-cluster-essentials
export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:ab0a3539da241a6ea59c75c0743e9058511d7c56312ea3906178ec0f3491f51d
export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$tanzunetusername
export INSTALL_REGISTRY_PASSWORD=$tanzunetpassword
cd $HOME/tanzu-cluster-essentials
./install.sh
echo "######## Installing Kapp ###########"
sudo cp $HOME/tanzu-cluster-essentials/kapp /usr/local/bin/kapp
kapp version
echo "######## Installing Imgpkg ###########"
sudo cp $HOME/tanzu-cluster-essentials/imgpkg /usr/local/bin/imgpkg
imgpkg version
echo "#################################"
pivnet download-product-files --product-slug='tanzu-application-platform' --release-version='1.3.2' --product-file-id=1352407
mkdir $HOME/tanzu
tar -xvf tanzu-framework-linux-amd64-v0.25.0.4.tar -C $HOME/tanzu
export TANZU_CLI_NO_INIT=true
cd $HOME/tanzu
sudo install cli/core/v0.25.0/tanzu-core-linux_amd64 /usr/local/bin/tanzu
tanzu version
tanzu plugin install --local cli all
tanzu plugin list
echo "######### Installing Docker ############"
sudo apt-get update
sudo apt-get install  ca-certificates curl  gnupg  lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io -y
sudo usermod -aG docker $USER
echo "####### Install tap-registry in all namespaces  ###########"
sudo apt-get install jq -y
sudo snap install yq
echo "#####################################################################################################"
echo "########### Rebooting #############"
sudo reboot
