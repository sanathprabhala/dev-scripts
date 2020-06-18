#!/bin/bash
# This script is meant to be ran as root user.
# Requires the pull-secret file to be present in the current directory.
# The script will:
# 1. Create a new user
# 2. Configure passwordless sudo for that user
# 3. Invoke subscription-manager in order to register and activate the subscription
# 4. Install new packages (like Git, text editor, shell and so on)
# 5. Clone the dev-scripts repository
# 6. Add the shared secret into the personal user pull-secret file (Get it at https://cloud.redhat.com/openshift/install/pull-secret)
# 7. Create a config file and apply basic configuration (including pull-secret and install directory)
# 8. Create world-readable dev-scripts directory under /home (as by default it's the largest volume)
# 9. Run make

# --- Config, please edit according to personal preferences:
host_username=""  # Name for the user to be created, or one that was created during install on the host machine
host_password=""  # Pass for the same user
shell="zsh"       # Enter the name of the package, as it will be directly piped into yum
text_editor="vim" # Enter the name of the package, as it will be directly piped into yum
subs_username=""  # RH Subscription username
subs_password=""  # RH Subscription password
# --- End config

# Vars
home_dir=eval echo "~${host_username}"

# Alias for text styles
bold=$(tput bold)
normal=$(tput sgr0)
warning=$(tput setaf 3)

# Warnings / Errors
error=false
if [ ! -f "pull-secret" ]; then
    echo "${bold}${warning}Please place the pull-secret file in the current directory${normal}"
    error=true

fi
if [ -z "$host_username" ]; then
    echo "${bold}${warning}Please edit the prefereces in this file before running it${normal}"
    error=true

fi
if [ $(id -u) -ne 0 ]; then
    echo "${bold}${warning}Please run the script as root user${normal}"
    error=true
fi
# Exit in case of an error
if [ "$error" = true ]; then
    exit 1
fi

# Add user
echo "${bold}Creating user${normal}"
egrep "^$host_username" /etc/passwd >/dev/null
if [ $? -eq 0 ]; then
    echo "$host_username already exists"
else
    useradd -m -p "$host_password" "$host_username"
    [ $? -eq 0 ] && echo "Created $host_username user" || echo "Failed to add a user!" && exit 1
fi

# Change working dir to home dir
cd $home_dir

# Passwordless sudo (if not set up yet)
if ! grep -xq "${host_username}\s*ALL=(ALL)\s*NOPASSWD:\s*ALL" /etc/sudoers; then
    echo "${bold}Enabling passwordless sudo for $host_username${normal}"
    echo "${host_username}\tALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers
fi

# Subscription manager (in case of RHEL)
if [ -f "/etc/redhat-release" ] && grep -q "Red Hat Enterprise Linux" /etc/redhat-release; then
    echo "${bold}Registering and activating subscription${normal}"
    sudo subscription-manager register --username $subs_username --password $subs_password
    sudo subscription-manager attach
fi

# Packages
echo "${bold}Updating existing and installing new packages${normal}"
sudo yum update -y
echo "${bold}Updating existing and installing new packages${normal}"
install_cmd="sudo yum install -y git make wget jq "
[ -n "$shell" ] && $install_cmd="${install_cmd}$shell"             # Concatenate the shell variable if it isn't empty
[ -n "$text_editor" ] && $install_cmd="${install_cmd}$text_editor" # Same as above
eval $install_cmd

# Dev-Scripts
echo "${bold}Cloning dev-scripts repository${normal}"
git clone https://github.com/openshift-metal3/dev-scripts
cp dev-scripts/config_example.sh dev-scripts/config_$host_username.sh
echo 'export WORKING_DIR=${WORKING_DIR:-"/home/dev-scripts"}' >>dev-scripts/config_$host_username.sh

# Pull secret
echo "${bold}Configuring the pull secret${normal}"
shared_secret='{"registry.svc.ci.openshift.org": {
    "auth": "PLACE_SECRET_HERE"
}}'
cat pull-secret | jq --argjson secret $shared_secret '.["auths"] + $secret' >$home_dir/pull-secret
sed -i "s/PULL_SECRET=''/PULL_SECRET='cat ${home_dir}/pull-secret'/g" config_$host_username.sh

# Workdir
echo "${bold}Creating workdir${normal}"
sudo mkdir /home/dev-scripts
sudo chmod 755 /home/dev-scripts

# Run `make`
echo "${bold}Running dev-scripts install${normal}"
export CONFIG=config_$host_username.sh
make -C dev-scripts
