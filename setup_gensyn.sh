#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

# BANNER
echo -e "${GREEN}"
cat << 'EOF'
 ______              _         _                                             
|  ___ \            | |       | |                   _                        
| |   | |  ___    _ | |  ____ | | _   _   _  ____  | |_   ____   ____  _____ 
| |   | | / _ \  / || | / _  )| || \ | | | ||  _ \ |  _) / _  ) / ___)(___  )
| |   | || |_| |( (_| |( (/ / | | | || |_| || | | || |__( (/ / | |     / __/ 
|_|   |_| \___/  \____| \____)|_| |_| \____||_| |_| \___)\____)|_|    (_____)
EOF
echo -e "${NC}"

# Set user and paths
USER_HOME=$(eval echo "~$(whoami)")
PEM_SRC=""
PEM_DEST="$USER_HOME/swarm.pem"
RL_SWARM_DIR="$USER_HOME/rl-swarm"

echo -e "${GREEN}[0/10] Backing up swarm.pem if exists...${NC}"

# Search for swarm.pem in home directory or inside rl-swarm
if [ -f "$USER_HOME/swarm.pem" ]; then
  PEM_SRC="$USER_HOME/swarm.pem"
elif [ -f "$RL_SWARM_DIR/swarm.pem" ]; then
  PEM_SRC="$RL_SWARM_DIR/swarm.pem"
fi

# Backup PEM if found
if [ -n "$PEM_SRC" ]; then
  echo "Found swarm.pem at: $PEM_SRC"
  cp "$PEM_SRC" "$PEM_DEST.backup"
  echo "Backup created: $PEM_DEST.backup"
else
  echo "swarm.pem not found. Continuing without backup."
fi

echo -e "${GREEN}[1/10] Updating system silently...${NC}"
sudo apt-get update -qq > /dev/null
sudo apt-get upgrade -y -qq > /dev/null

echo -e "${GREEN}[2/10] Installing dependencies silently...${NC}"
sudo apt install -y -qq sudo nano curl python3 python3-pip python3-venv git screen > /dev/null

echo -e "${GREEN}[3/10] Installing NVM and latest Node.js...${NC}"
curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"
nvm install node > /dev/null
nvm use node > /dev/null

# Remove old rl-swarm if exists
if [ -d "$RL_SWARM_DIR" ]; then
  echo -e "${GREEN}[4/10] Removing existing rl-swarm folder...${NC}"
  rm -rf "$RL_SWARM_DIR"
fi

echo -e "${GREEN}[5/10] Cloning rl-swarm repository...${NC}"
git clone https://github.com/gensyn-ai/rl-swarm "$RL_SWARM_DIR" > /dev/null

# Restore swarm.pem if we had a backup
if [ -f "$PEM_DEST.backup" ]; then
  cp "$PEM_DEST.backup" "$RL_SWARM_DIR/swarm.pem"
  echo "Restored swarm.pem into rl-swarm folder."
fi

cd "$RL_SWARM_DIR"

echo -e "${GREEN}[6/10] Setting up Python virtual environment...${NC}"
python3 -m venv .venv
echo -e "${GREEN} Activating virtual environment...${NC}"
cd "$HOME/rl-swarm"
source .venv/bin/activate

echo -e "${GREEN}🧹 Closing any existing 'gensyn' screen sessions...${NC}"
screen -ls | grep -o '[0-9]*\.gensyn' | while read -r session; do
  screen -S "${session%%.*}" -X quit
done
# Free port 3000 if already in use
echo -e "${GREEN}🔍 Checking if port 3000 is in use (via netstat)...${NC}"
PORT_3000_PID=$(sudo netstat -tunlp 2>/dev/null | grep ':3000' | awk '{print $7}' | cut -d'/' -f1 | head -n1)

if [ -n "$PORT_3000_PID" ]; then
  echo -e "${RED}⚠️  Port 3000 is in use by PID $PORT_3000_PID. Terminating...${NC}"
  sudo kill -9 "$PORT_3000_PID" || true
  echo -e "${GREEN}✅ Port 3000 has been freed.${NC}"
else
  echo -e "${GREEN}✅ Port 3000 is already free.${NC}"
fi

echo -e "${GREEN}[8/10] Running rl-swarm in screen session...${NC}"
screen -dmS gensyn bash -c "
cd ~/rl-swarm
source \"$HOME/rl-swarm/.venv/bin/activate\"
./run_rl_swarm.sh || echo '⚠️ run_rl_swarm.sh exited with error code \$?'
exec bash
"

echo -e "${GREEN}[9/10] Attempting to expose localhost:3000...${NC}"
TUNNEL_URL=""

# Try LocalTunnel
echo -e "${GREEN}🌐 Choose a tunnel method to expose port 3000:${NC}"
echo -e "1) LocalTunnel"
echo -e "2) Cloudflared"
echo -e "3) Ngrok"
echo -e "4) Auto fallback (try all methods)"
read -rp "Enter your choice [1-4]: " TUNNEL_CHOICE

TUNNEL_URL=""

start_localtunnel() {
  echo -e "${GREEN}🔌 Starting LocalTunnel...${NC}"
  npm install -g localtunnel > /dev/null 2>&1
  screen -S lt_tunnel -X quit 2>/dev/null
  screen -dmS lt_tunnel bash -c "npx localtunnel --port 3000 > lt.log 2>&1"
  sleep 5
  grep -o 'https://[^[:space:]]*\.loca\.lt' lt.log | head -n 1
}

start_cloudflared() {
  echo -e "${GREEN}🔌 Starting Cloudflared...${NC}"
  if ! command -v cloudflared &> /dev/null; then
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    sudo dpkg -i cloudflared-linux-amd64.deb > /dev/null
    rm -f cloudflared-linux-amd64.deb
  fi
  screen -S cf_tunnel -X quit 2>/dev/null
  screen -dmS cf_tunnel bash -c "cloudflared tunnel --url http://localhost:3000 --logfile cf.log --loglevel info"
  sleep 5
  grep -o 'https://[^[:space:]]*\.trycloudflare\.com' cf.log | head -n 1
}

start_ngrok() {
  echo -e "${GREEN}🔌 Starting Ngrok...${NC}"
  if ! command -v ngrok &> /dev/null; then
    npm install -g ngrok > /dev/null
  fi
  read -rp "🔑 Enter your Ngrok auth token from https://dashboard.ngrok.com/get-started/your-authtoken: " NGROK_TOKEN
  ngrok config add-authtoken "$NGROK_TOKEN" > /dev/null 2>&1
  screen -S ngrok_tunnel -X quit 2>/dev/null
  screen -dmS ngrok_tunnel bash -c "ngrok http 3000 > /dev/null 2>&1"
  sleep 5
  curl -s http://localhost:4040/api/tunnels | grep -o 'https://[^"]*' | head -n 1
}

# Manual selection or fallback logic
case "$TUNNEL_CHOICE" in
  1)
    TUNNEL_URL=$(start_localtunnel)
    ;;
  2)
    TUNNEL_URL=$(start_cloudflared)
    ;;
  3)
    TUNNEL_URL=$(start_ngrok)
    ;;
  4|*)
    TUNNEL_URL=$(start_localtunnel)
    if [ -z "$TUNNEL_URL" ]; then
      echo -e "${YELLOW}⚠️ LocalTunnel failed, trying Cloudflared...${NC}"
      TUNNEL_URL=$(start_cloudflared)
    fi
    if [ -z "$TUNNEL_URL" ]; then
      echo -e "${YELLOW}⚠️ Cloudflared failed, trying Ngrok...${NC}"
      TUNNEL_URL=$(start_ngrok)
    fi
    ;;
esac

if [ -n "$TUNNEL_URL" ]; then
  echo -e "${GREEN}✅ Tunnel established at: ${CYAN}$TUNNEL_URL${NC}"
  echo -e "${GREEN}=========================================${NC}"
  echo -e "${GREEN}🧠 Use this in your browser to access the login page.${NC}"
  echo -e "${GREEN}🎥 Guide: https://youtu.be/0vwpuGsC5nE${NC}"
  echo -e "${GREEN}=========================================${NC}"
else
  echo -e "${RED}❌ Failed to establish a tunnel. Please check logs or try again.${NC}"
fi
