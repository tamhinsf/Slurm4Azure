# Slurm Workload Manager for Microsoft Azure. 

It's easy to deploy a Slurm cluster to Microsoft Azure!  The Azure template on this page helps you quickly create and configure a Slurm cluster running Ubuntu 16.04 (LTS).  

When you're done, you'll have an operational Slurm cluster consisting of:

* One master node - containing a shared directory exported to worker nodes
* One or more worker nodes - mounting the shared directory from master
* A local installation of Slurm and related binaries on both master and worker nodes
* Full configuration of Slurm and related binaries.  This includes the creation of a cluster wide administrator user, automatic startup of Slurm processes at boot, and configuration of Slurm compute parameters to match the processor and memory configuration of the underlying virtual machines
* An NFS shared directory called "/data" accesible across all nodes

Our Slurm4Azure repository is based on the "slurm" repository found here: https://github.com/Azure/azure-quickstart-templates/tree/master/slurm

NOTE: The Slurm workers created by this template are individual vitual machines and not part of an Azure Virtual Machine Scale Set.  We'll look to enhance functionality in the future.  Onwards!

# Let's Get Started!

Begin deploying your Slurm cluster by clicking the Deploy to Azure button below.  You'll be able to adjust:

* Azure region you wish to deploy.  Our deault is West US.
* Azure Resource Group.  We strongly recommend you create a new Resource Group.
* Username and Password of the cluster-wide Slurm administrator. 
  * The default username is "slurmadmin"
  * Make sure your password meets the Azure requirements for Linux VMs as described here https://docs.microsoft.com/en-us/azure/virtual-machines/linux/faq#what-are-the-password-requirements-when-creating-a-vm
* Azure VM Series used for both the master and worker nodes
* Size of the cluster-wide shared disk
* Number of worker nodes

Enure  the VM Series you enter is available in the Azure region you target.  Need help figuring out the right combination?  The Azure VM Comparision website will provide you the list of VMs available in a particular region.  https://azureprice.net/

You'll need to Agree to the terms and click Purchase to begin deployment.  As a reminder, you're not actually paying to use this free template. However, the resources that you deploy and make use of will be billed to your subscription.

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ftamhinsf%2FSlurm4Azure%2Fmaster%2Fazuredeploy.json" target="_blank">
   <img alt="Deploy to Azure" src="http://azuredeploy.net/deploybutton.png"/>
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Ftamhinsf%2FSlurm4Azure%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>

## Using your Slurm Cluster

Once you've begun your deployment, you can remain in the Azure Portal or navigate away and come back.  Either way, you'll receive a notification in the top navigation bar once your deployment has completed.  Once this has occured:

* Navigate to the Azure Resource Group you targeted.  
* Look for a virtual machine called "master".   This machine is the head node in your Slurm cluster.  
  * This VM will be assigned a public IP address that you can use to gain access using SSH.  
  * On the "Overview" Pane click the Connect button.  You'll be shown the username@ipaddress value you can supply to your SSH client.  Note that username defaults to "slurmadmin" unless you've explicitly changed it.
* Connect to "master" using your SSH credentials
* After you login, look for a file called "done" in your home directory.  This is an indication that the scripts used to deploy and configure Slurm and your cluster have completed.  However, this does not necessarily mean that these operations have suceeded.  We suggest you perform the following:
  * Review the file called /tmp/azuredeploy.log.xxxx where xxxx is a random four digit number.  Check for errors.  The operations performed by our setup scripts may have failed due to unexpected network timeouts or other reasons.  
  * Use the Slurm commands "sinfo" and "scontrol show nodes" to validate the number of nodes in your cluster and their configuration.  Here's the output of "sinfo" showing a cluster containing one master and two workers.  

        slurmadmin@master:/tmp$ sinfo
        PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
        debug*       up   infinite      3   idle master,worker[0-1]
  
  * Go to the /data directory.  It's the cluster-wide shared folder.  You'll want to run any Slurm workloads requiring cluster-wide shared files in this directory.
    * Take a look at the file called shared-bashrc.  The .bashrc file for the Slurm admin account on the master and all worker nodes references this file - making it a great place to store cluster-wide environmnent settings.  
    * There should also be a folder called "canu", which contains an open source genomics application of the same name.  You can use canu to validate the functionality of your Slurm cluster.  
      * No need for it? It can be safely removed.  
      * Want to give it a try?  Follow the instructions here: http://canu.readthedocs.io/en/latest/quick-start.html




  

