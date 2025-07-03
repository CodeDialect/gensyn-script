# GENSYN Setup Guide

This guide walks you through setting up gensyn.

---

## Step 1: Install Dependencies

Update and upgrade your system, then install required packages:

```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo apt install nano curl screen git ufw -y
```
---

If sudo: command not found:
```bash
apt install sudo
```
---

## Step 2: Clone the Repository

```bash
git clone https://github.com/CodeDialect/gensyn-script.git
cd gensyn-script
```

## If above command giving you error file already exits then run below command first then run the Step 2 else don't run below command

```bash
rm -rf gensyn-script
```

---

## Step 3: Make Scripts Executable

```bash
chmod +x setup_gensyn.sh
```

---

If you are using vps then
## Step 4: Enable Firewall & Open Required Ports

```bash
# Basic SSH Access
sudo ufw allow 22
sudo ufw allow ssh
sudo ufw allow 3000

# Enable Firewall
sudo ufw enable
```
---

## Step 5: Run the GENSYN

```bash
./setup_gensyn.sh
```
---

## Fix RuntimeError: Hivemind Resource temporarily unavailable

Full error:
> **RuntimeError: [ERROR] [hivemind.dht.dht._run:130] [Errno 11] Resource temporarily unavailable**

```bash
sed -i -E 's/(fp16:\s*)false/\1true/; s/(num_train_samples:\s*)2/\1 1/' "$HOME/rl-swarm/rgym_exp/config/rg-swarm.yaml"
```
nano 

## Restart the node
Press `Ctrl + C`.
Run command:
```./run_rl_swarm.sh```


### How to upgrade the node as per new changes in the official repository (Do only If your node is already running if you are new or stopped your node it's fine because script already points to the original repository)

Open the rl-swarm directory:

```bash
cd $HOME/rl-swarm
```

Pull the changes from original repository:
```bash
git reset --hard HEAD
git pull
```

**Note:** If the above command response is already up to date then there is no need to go further. If not then follow below.


Open gensyn screen:

```bash
screen -r gensyn
```
Stop the already running node:
Press Ctrl+c

Restart the node:
```bash
./run_rl_swarm.sh
```


**Note:** Press `Ctrl+A` then `D` to detach from the screen session. Reconnect later using:

```bash
screen -r gensyn
```
