# Step to Installation Storage Scale

1. Transfer ISO file to Bastion, Spectrum Node1, Spectrum Node2
___   
2. Mount and Create local repo on Bastion, Spectrum Node1, Spectrum Node2
___
3. Setup Pre-requisite on Bastion, Spectrum Node1, Spectrum Node2
  -  Login as root
  -  Configure `/etc/hosts` add following
      ```bash
        <ip_bastion> <Bastion_name>
        <ip_spectrum_node1> <Spectrum_Node1_name>
        <ip_spectrum_node2> <Spectrum_Node2_name>
        <ip_backend_spectrum_node1> <Spectrum_Node1_Backend_name>    #  In case you use backend
        <ip_backend_spectrum_node2> <Spectrum_Node2_Backend_name>    #  In case you use backend
  -  Create SSH-key pair and Copy to Other Node
      -  `ssh-keygen`
      -  `ssh-copy-id <Bastion_name>`
      -  `ssh-copy-id <Spectrum_Node1_name>`
      -  `ssh-copy-id <Spectrum_Node2_name>`
  - Check Storage
    -  `multipath -ll`
    -  If storage is not detected run `scsi-rescan`
    -  Add following in `/etc/multipath.conf`
      ```bash
       devices {
         device {
            vendor "IBM"
            product "2145"
            path_grouping_policy group_by_prio
            prio alua
            path_checker tur
            hardware_handler "1 alua"
            failback immediate
            no_path_retry 60
            rr_weight uniform
            rr_min_io 1000
         }
      }
      ```
      -   check multipath <br> `multipath -ll | grep 2145`
      -   Mapping storage ID
   -   Configure NTP from `/etc/chrony.conf`
        -   replace as following (looking for pool -> you can remove or just #)
          ```bash
          # pool .....   iburst
          server <ip_ntp_server> iburst
          ```
          `systemctl restart chronyd` <br>
          `timedatectl`
        -   Stop firewall, selinux
          `systemctl stop firewalld`<br>
          `systemctl disable firewalld`<br>
          `setenforce 0`<br>
          `getenforce`
          -   configure file `/etc/selinux/config` change from enable to disable
                ```bash
                SELINUX=disabled
                ```
   -   Check DNS on Spectrum Node1 <br>
        `dig <FQDN_Spectrum_node1_name>` <br>
        `dig <FQDN_Spectrum_node2_name>`
___
4.   Install package on Spectrum Node1, Spectrum Node2<br>
      `yum install kernel-devel cpp gcc gcc-c++ binutils elfutils elfutils-devel -y`
___
5.   Install Spectrum Scale on Bastion <br>
      -  Go to path Storage_Scale file that you prepared <br>
      `./Storage_Scale_Data_Management-5.2.3.0-x86_64-Linux-install` <br>
      -  Go to path ansible
      `cd /usr/lpp/mmfs/5.2.3.0/ansible-toolkit`<br>
      `./spectrumscale setup -s <ip_bastion>` <br>
      `./spectrumscale node add <Spectrum_Node1_name> -a -g -n -m` # -a = admin , -g = gui, -n = node, -m = manager <br>
      `./spectrumscale node add <Spectrum_Node2_name> -a -g -n` <br>
      `./spectrumscale callhome disable` # If callhome is not used <br>
      -  Configure can modified in `ansible/vars/scale_clusterdefinition.json` for example change scale_daemon_node_name <br>
      -  Run the precheck, then debug and fix any reported errors. <br>
      `./spectrumscale install --precheck` <br>
      -  After running the precheck with no errors, run the install <br>
      `./spectrumscale install`<br>
___
6.  Add NSD 
      -  Add all NSDs are needed (default name start from nsd1) <br>
      `./spectrumscale nsd add -p <Spectrum_Node1_name> -s <Spectrum_Node2_name> -u dataAndMetadata "</dev/dm-x>"` <br>
      -  To Change the NSDs name <br>
      `./spectrumscale nsd modify <nsd_old_name> --name "<nsd_new_name>"` <br>
      - Run following command to add a name <br>
      `./spectrumscale nsd add -p <Spectrum_Node1_name> -s <Spectrum_Node2_name> -u dataAndMetadata --name <nsd_name> "</dev/dm-x>"` <br>
      - List the NSDs configuration <br>
      `./spectrumscale nsd list` <br>
      -  Run the precheck, then debug and fix any reported errors. <br>
      `./spectrumscale install --precheck` <br>
      -  After running the precheck with no errors, run the install <br>
      `./spectrumscale install`<br>
___
7.  Configure `.bash_profile` on Spectrum Node1 , Spectrum Node2 <br>
    ```bash
    export PATH=$PATH:$HOME/bin:/usr/lpp/mmfs/bin
___
8. Go to Spectrum Node1 to add tiebreakerDisks <br>
  `mmchconfig tiebreakerDisks=<nsd_name>`<br>
___
9. Go back to Bastion and Add filesystem <br>
  -  List file system <br>
  `./spectrumscale filesystem list` <br>
  - Add filesystem to all nsd <br>
  `./spectrumscale nsd modify <nsd_name> -fs <filesystem_name>` <br>
  - Modify the size and mount point of the filesystem <br>
    `./spectrumscale filesystem modify <filesystem_name> -B <filesystem_size> -m <filesystem_mount_path>`<br>
  - Check configure <br>
    `./spectrumscale filesystem list`<br>
  - Run the precheck, then debug and fix any reported errors. <br>
      `./spectrumscale install --precheck` <br>
  - After running the precheck with no errors, run the install <br>
      `./spectrumscale install`<br>
___
10. Access the GUI URL and create a GUI user on Spectrum Node1 <br>
  `/usr/lpp/mmfs/gui/cli/mkuser <username> -p "<password>" -g SecurityAdmin` <br>
___
11. Tuning Filesystem <br>
  `mmlsfs <filesystem_name> --perfileset -quota` <br>
  `mmchfs <filesystem_name> -Q yes` <br>
  `mmlsfs <filesystem_name> -Q` <br>
  `mmchconfig enforceFilesetQuotaOnRoot=yes -i` <br>
  `mmchconfig ignoreReplicationForQuota=yes -i` <br>
  `mmchconfig controlSetxattrImmutableSELinux=yes -i` <br>
  `mmchfs <filesystem_name> --filesetdf` <br>
  `mmchfs <filesystem_name> --auto-inode-limit` <br>
  ___

  ## Expected Result
  The GUI node is accessible and the Storage Scale cluster is healthy.
