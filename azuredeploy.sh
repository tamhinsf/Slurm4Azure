#!/bin/sh

# This script can be found on https://github.com/Azure/azure-quickstart-templates/blob/master/slurm/azuredeploy.sh
# This script is part of azure deploy ARM template
# This script assumes the Linux distribution to be Ubuntu (or at least have apt-get support)
# This script will install SLURM on a Linux cluster deployed on a set of Azure VMs

# Basic info
date > /tmp/azuredeploy.log.$$ 2>&1
whoami >> /tmp/azuredeploy.log.$$ 2>&1
echo $@ >> /tmp/azuredeploy.log.$$ 2>&1

# Usage
if [ "$#" -ne 10 ]; then
  echo "Usage: $0 MASTER_NAME MASTER_IP WORKER_NAME WORKER_IP_BASE WORKER_IP_START NUM_OF_VM ADMIN_USERNAME ADMIN_PASSWORD NUM_OF_DATA_DISKS TEMPLATE_BASE" >> /tmp/azuredeploy.log.$$
  exit 1
fi

# Preparation steps - hosts and ssh
###################################

# Parameters
MASTER_NAME=${1}
MASTER_IP=${2}
WORKER_NAME=${3}
WORKER_IP_BASE=${4}
WORKER_IP_START=${5}
NUM_OF_VM=${6}
ADMIN_USERNAME=${7}
ADMIN_PASSWORD=${8}
NUM_OF_DATA_DISKS=${9}
TEMPLATE_BASE=${10}

# Create a cluster wide NFS share directory. Format and mount the data disk on master and install NFS
sudo sh -c "mkdir /data" >> /tmp/azuredeploy.log.$$ 2>&1
if [ $NUM_OF_DATA_DISKS -eq 1 ]; then
  sudo sh -c "mkfs -t ext4 /dev/sdc" >> /tmp/azuredeploy.log.$$ 2>&1
  echo "/dev/sdc /data ext4  defaults,discard 0 0" | sudo tee -a /etc/fstab >> /tmp/azuredeploy.log.$$ 2>&1
# fi
else
# if [ $NUM_OF_DATA_DISKS -gt 1 ]; then  
  i = 0
  LETTERVAR=( {c..f} )
  LETTERSTRING=
  while [ $i -lt $NUM_OF_DATA_DISKS ]
  do      
    LETTERSTRING+="/dev/sd${LETTERVAR[x]} "
  done
  sudo mdadm --create /dev/md127 --level 0 --raid-devices=$NUM_OF_DATA_DISKS $LETTERSTRING >> /tmp/azuredeploy.log.$$ 2>&1
  sudo sh -c "mkfs -t ext4 /dev/md127" >> /tmp/azuredeploy.log.$$ 2>&1
  echo "/dev/md127 /data ext4  defaults,discard 0 0" | sudo tee -a /etc/fstab >> /tmp/azuredeploy.log.$$ 2>&1
fi

sudo sh -c "mount /data" >> /tmp/azuredeploy.log.$$ 2>&1
sudo sh -c "chown -R $ADMIN_USERNAME /data" >> /tmp/azuredeploy.log.$$ 2>&1
sudo sh -c "chgrp -R $ADMIN_USERNAME /data" >> /tmp/azuredeploy.log.$$ 2>&1
sudo apt-get install nfs-kernel-server -y >> /tmp/azuredeploy.log.$$ 2>&1
echo "/data 10.0.0.0/16(rw)" | sudo tee -a /etc/exports >> /tmp/azuredeploy.log.$$ 2>&1
sudo systemctl restart nfs-kernel-server >> /tmp/azuredeploy.log.$$ 2>&1

# Create a shared folder on /data to store files used by the installation process
sudo -u $ADMIN_USERNAME sh -c "rm -rf /data/tmp"
sudo -u $ADMIN_USERNAME sh -c "mkdir /data/tmp"

# Create a shared environment variables file on /data and reference it in the login .bashrc file
sudo rm /data/shared-bashrc
sudo -u $ADMIN_USERNAME touch /data/shared-bashrc
echo "source /data/shared-bashrc" | sudo -u $ADMIN_USERNAME tee -a /home/$ADMIN_USERNAME/.bashrc 

# Create Workers NFS client install script and store it on /data
sudo rm /data/tmp/workerNfs.sh
sudo touch /data/tmp/workerNfs.sh
sudo chmod u+x /data/tmp/workerNfs.sh
echo "sudo sh -c \"mkdir /data\"" | sudo tee -a /data/tmp/workerNfs.sh >> /tmp/azuredeploy.log.$$ 2>&1
echo "sudo apt-get install nfs-common -y" | sudo tee -a /data/tmp/workerNfs.sh >> /tmp/azuredeploy.log.$$ 2>&1
echo "echo \"$MASTER_NAME:/data /data nfs rw,hard,intr 0 0\" | sudo tee -a /etc/fstab " | sudo tee -a /data/tmp/workerNfs.sh  >> /tmp/azuredeploy.log.$$ 2>&1
echo "sudo sh -c \"mount /data\"" | sudo tee -a /data/tmp/workerNfs.sh >> /tmp/azuredeploy.log.$$ 2>&1

# Update master node hosts file
echo $MASTER_IP $MASTER_NAME >> /etc/hosts
echo $MASTER_IP $MASTER_NAME > /data/tmp/hosts

# Update ssh config file to ignore unknown hosts
# Note all settings are for $ADMIN_USERNAME, NOT root
sudo -u $ADMIN_USERNAME sh -c "mkdir /home/$ADMIN_USERNAME/.ssh/;echo Host worker\* > /home/$ADMIN_USERNAME/.ssh/config; echo StrictHostKeyChecking no >> /home/$ADMIN_USERNAME/.ssh/config; echo UserKnownHostsFile=/dev/null >> /home/$ADMIN_USERNAME/.ssh/config"

# Generate a set of sshkey under /honme/$ADMIN_USERNAME/.ssh if there is not one yet
if ! [ -f /home/$ADMIN_USERNAME/.ssh/id_rsa ]; then
    sudo -u $ADMIN_USERNAME sh -c "ssh-keygen -f /home/$ADMIN_USERNAME/.ssh/id_rsa -t rsa -N ''"
fi

# Install sshpass to automate ssh-copy-id action
sudo apt-get install sshpass -y >> /tmp/azuredeploy.log.$$ 2>&1

# Loop through all worker nodes, update hosts file and copy ssh public key to it
# The script make the assumption that the node is called %WORKER+<index> and have
# static IP in sequence order
i=0
while [ $i -lt $NUM_OF_VM ]
do
   workerip=`expr $i + $WORKER_IP_START`
   echo 'I update host - '$WORKER_NAME$i >> /tmp/azuredeploy.log.$$ 2>&1
   echo $WORKER_IP_BASE$workerip $WORKER_NAME$i >> /etc/hosts
   echo $WORKER_IP_BASE$workerip $WORKER_NAME$i >> /data/tmp/hosts
   sudo -u $ADMIN_USERNAME sh -c "sshpass -p '$ADMIN_PASSWORD' ssh-copy-id $WORKER_NAME$i"
   i=`expr $i + 1`
done

# Install SLURM on master node
###################################

# Install the package
sudo apt-get update >> /tmp/azuredeploy.log.$$ 2>&1
sudo chmod g-w /var/log >> /tmp/azuredeploy.log.$$ 2>&1 # Must do this before munge will generate key
sudo apt-get install slurm-llnl -y >> /tmp/azuredeploy.log.$$ 2>&1

# Make a slurm spool directory
sudo mkdir /var/spool/slurm
sudo chown slurm /var/spool/slurm

# Download slurm.conf and fill in the node info
SLURMCONF=/data/tmp/slurm.conf
wget $TEMPLATE_BASE/slurm.template.conf -O $SLURMCONF >> /tmp/azuredeploy.log.$$ 2>&1
sed -i -- 's/__MASTERNODE__/'"$MASTER_NAME"'/g' $SLURMCONF >> /tmp/azuredeploy.log.$$ 2>&1
lastvm=`expr $NUM_OF_VM - 1`
sed -i -- 's/__WORKERNODES__/'"$WORKER_NAME"'[0-'"$lastvm"']/g' $SLURMCONF >> /tmp/azuredeploy.log.$$ 2>&1
sed -i -- 's/__NODECPUS__/'"CPUs=`nproc --all`"'/g' $SLURMCONF >> /tmp/azuredeploy.log.$$ 2>&1
sed -i -- 's/__NODERAM__/'"RealMemory=`free -m | awk '/Mem:/{print $2}'`"'/g' $SLURMCONF >> /tmp/azuredeploy.log.$$ 2>&1
sed -i -- 's/__NODETHREADS__/'"ThreadsPerCore=`lscpu|grep Thread|cut -d ":" -f 2|awk '{$1=$1;print}'`"'/g' $SLURMCONF >> /tmp/azuredeploy.log.$$ 2>&1
sudo cp -f $SLURMCONF /etc/slurm-llnl/slurm.conf >> /tmp/azuredeploy.log.$$ 2>&1
sudo chown slurm /etc/slurm-llnl/slurm.conf >> /tmp/azuredeploy.log.$$ 2>&1
sudo chmod o+w /var/spool # Write access for slurmctld log. Consider switch log file to another location
sudo -u slurm /usr/sbin/slurmctld >> /tmp/azuredeploy.log.$$ 2>&1 # Start the master daemon service
sudo munged --force >> /tmp/azuredeploy.log.$$ 2>&1 # Start munged
sudo slurmd >> /tmp/azuredeploy.log.$$ 2>&1 # Start the node

# Install slurm on all nodes by running apt-get
# Also push munge key and slurm.conf to them
echo "Prepare the local copy of munge key" >> /tmp/azuredeploy.log.$$ 2>&1 
mungekey=/data/tmp/munge.key
sudo cp -f /etc/munge/munge.key $mungekey
echo "Done copying munge" >> /tmp/azuredeploy.log.$$ 2>&1 
sudo chown $ADMIN_USERNAME $mungekey
ls -la $mungekey >> /tmp/azuredeploy.log.$$ 2>&1 

# Get and install shared software on /data
# This example installs the Canu package and dependencies
# You can substitute your own specifics here

# Install JDK and GNU packages required by Canu
sudo apt-get install openjdk-8-jdk -y >> /tmp/azuredeploy.log.$$ 2>&1
sudo apt-get install libgomp1 -y >> /tmp/azuredeploy.log.$$ 2>&1
sudo apt-get install gnuplot -y >> /tmp/azuredeploy.log.$$ 2>&1

# Create a canu subdirectory within the /data shared folder and install it
sudo -u $ADMIN_USERNAME sh -c "mkdir /data/canu" >> /tmp/azuredeploy.log.$$ 2>&1
sudo -u $ADMIN_USERNAME wget https://github.com/marbl/canu/releases/download/v1.6/canu-1.6.Linux-amd64.tar.xz -P /data/canu
sudo -u $ADMIN_USERNAME xz -dc /data/canu/canu-1.6.*.tar.xz |tar -xf - -C /data/canu/

# Update the file to store environment vars used across the cluster
echo "PATH=\$PATH:/data/canu/canu-1.6/Linux-amd64/bin" | sudo -u $ADMIN_USERNAME tee -a /data/shared-bashrc

# Create and deploy assets to worker nodes
echo "Start looping all workers" >> /tmp/azuredeploy.log.$$ 2>&1 

i=0
while [ $i -lt $NUM_OF_VM ]
do
   worker=$WORKER_NAME$i

   echo "SCP to $worker"  >> /tmp/azuredeploy.log.$$ 2>&1 
   # copy NFS mount script over
   sudo -u $ADMIN_USERNAME scp /data/tmp/workerNfs.sh $ADMIN_USERNAME@$worker:/tmp/workerNfs.sh >> /tmp/azuredeploy.log.$$ 2>&1
   # small hack: munge.key has permission problems when copying from NFS drive.  Fix this later
   sudo -u $ADMIN_USERNAME scp $mungekey $ADMIN_USERNAME@$worker:/tmp/munge.key >> /tmp/azuredeploy.log.$$ 2>&1
   
   echo "Remote execute on $worker" >> /tmp/azuredeploy.log.$$ 2>&1 
   sudo -u $ADMIN_USERNAME ssh $ADMIN_USERNAME@$worker >> /tmp/azuredeploy.log.$$ 2>&1 << 'ENDSSH1'
      sudo /tmp/workerNfs.sh
      sudo rm -f /tmp/workerNfs.sh
      sudo echo "source /data/shared-bashrc" | sudo -u $USER tee -a /home/$USER/.bashrc
      sudo sh -c "cat /data/tmp/hosts >> /etc/hosts"
      sudo chmod g-w /var/log
      sudo mkdir /var/spool/slurm
      sudo chown slurm /var/spool/slurm
      sudo apt-get update
      sudo apt-get install slurm-llnl -y
      sudo cp -f /tmp/munge.key /etc/munge/munge.key
      sudo chown munge /etc/munge/munge.key
      sudo chgrp munge /etc/munge/munge.key
      sudo rm -f /tmp/munge.key
      sudo /usr/sbin/munged --force # ignore egregrious security warning
      sudo cp -f /data/tmp/slurm.conf /etc/slurm-llnl/slurm.conf
      sudo chown slurm /etc/slurm-llnl/slurm.conf
      sudo slurmd
      sudo echo "Installing packages required by Canu.  These can be removed if you don't need them."
      sudo apt-get install openjdk-8-jdk -y
      sudo apt-get install libgomp1 -y
      sudo apt-get install gnuplot -y
ENDSSH1
   i=`expr $i + 1`
done

# Remove temp files on master
#rm -f $mungekey
sudo rm -f /data/tmp/*

# Write a file called done in the $ADMIN_USERNAME home directory to let the user know we're all done
sudo -u $ADMIN_USERNAME touch /home/$ADMIN_USERNAME/done

exit 0
