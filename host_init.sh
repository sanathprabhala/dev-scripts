#!/bin/bash
# This script is meant to be ran as a sudo user.
# Requires the pull-secret file to be present in the current directory.
# The script will:
# 1. Configure passwordless sudo for that user
# 2. Invoke subscription-manager in order to register and activate the subscription (in case of RHEL)
# 3. Install new packages (like Git, text editor, shell and so on)
# 4. Clone the dev-scripts repository
# 5. Add the shared secret into the personal user pull-secret file (Get it at https://cloud.redhat.com/openshift/install/pull-secret)
# 6. Create a config file and apply basic configuration (including pull-secret and install directory)
# 7. Create world-readable dev-scripts directory under /home (as by default it's the largest volume)
# 8. Run make

# --- Config, please edit according to personal preferences:
shell="zsh"       # Enter the name of the package, as it will be directly piped into yum
text_editor="vim" # Enter the name of the package, as it will be directly piped into yum
subs_username=""  # RH Subscription username
subs_password=""  # RH Subscription password
# --- End config

# Alias for text styles
bold=$(tput bold)
normal=$(tput sgr0)
warning=$(tput setaf 3)

# Vars
user=$(logname)
home_dir=eval echo ~$user

# Warnings / Errors
error=false
sudo -v
if [ $? -ne 0 ]; then
    echo "${bold}${warning}Please run the script as a sudo user${normal}"
    error=true
fi
if [ ! -f "pull-secret" ]; then
    echo "${bold}${warning}Please place the pull-secret file in the current directory${normal}"
    error=true
fi
# Exit in case of an error
if [ "$error" = true ]; then
    exit 1
fi

# Passwordless sudo (if not set up yet)
if ! grep -xq "$user\s*ALL=(ALL)\s*NOPASSWD:\s*ALL" /etc/sudoers; then
    echo "${bold}Enabling passwordless sudo for $user${normal}"
    echo "$user  ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers
fi

# Subscription manager (in case of RHEL)
if [ -f "/etc/redhat-release" ] && grep -q "Red Hat Enterprise Linux" /etc/redhat-release; then
    if [ -z "$subs_username" ] || [ -z "$subs_password" ]; then
        echo "${bold}${warning}Please edit the prefereces in this file before running it${normal}"
        exit 1
    fi
    echo "${bold}Registering and activating subscription${normal}"
    subscription-manager register --username $subs_username --password $subs_password
    subscription-manager attach
fi

# Packages
echo "${bold}Updating existing packages${normal}"
yum update -y
echo "${bold}Installing new packages${normal}"
install_cmd="yum install -y git make wget tmux jq"
[ -n "$shell" ] && install_cmd+=" $shell"             # Concatenate the shell variable if it isn't empty
[ -n "$text_editor" ] && install_cmd+=" $text_editor" # Same as above
eval $install_cmd
[ $? -eq 0 ] || (echo "${bold}${warning}Failed:${normal} ${install_cmd}" && exit 1)

# Dev-Scripts
echo "${bold}Cloning dev-scripts repository${normal}"
git clone https://github.com/openshift-metal3/dev-scripts
cp dev-scripts/config_example.sh dev-scripts/config_$user.sh
echo 'export WORKING_DIR=${WORKING_DIR:-"/home/dev-scripts"}' >>dev-scripts/config_$user.sh

# Pull secret
echo "${bold}Configuring the pull secret${normal}"
shared_secret='{"registry.svc.ci.openshift.org": {
    "auth": "PLACE_SECRET_HERE"
}}'
cat pull-secret | jq --argjson secret $shared_secret '.["auths"] + $secret' >$home_dir/pull-secret
sed -i "s/PULL_SECRET=''/PULL_SECRET='cat ${home_dir}/pull-secret'/g" config_$user.sh

# Workdir
echo "${bold}Creating workdir${normal} at /home/dev-scripts"
mkdir /home/dev-scripts 2>/dev/null
chmod 755 /home/dev-scripts

# Run `make`
echo "${bold}Running dev-scripts install${normal}"
su - $user -c 'make -C $home_dir/dev-scripts'
