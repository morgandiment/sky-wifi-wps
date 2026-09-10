# Sky Hub SR213 Automated WPS Trigger

A lightweight Bash script to trigger WPS (PushButton) on the white Sky WiFi Max Hub (SR213 / RDK-B) from your computer using `curl`.

---

## Why This Exists

Certain devices (like Samsung Tizen TVs) fail the WPA3-Transition handshake on the Sky Max Hub, dropping their connection on every reboot. The solution to this is either downgrading network security, or physically going to the router and activating WPS every single time you want to use the device.

This script saves that extra bit of effort and time by triggering the 120-second WPS pairing window headlessly over your local network.

---

## Requirements

* Unix shell (macOS, Linux, WSL)
* `curl`

---

## Setup & Usage

1. **Clone the repo:**
   ```bash
   git clone [https://github.com/your-username/sky-wifi-wps.git](https://github.com/your-username/sky-wifi-wps.git)
   cd sky-wifi-wps

2. **Create your `.env` file:**
   ```bash
   cp .env.example .env
    ```

    Add your router admin password (found on the hub's label):

    ```bash
    SKY_ROUTER_HOST="myrouter.io"
    SKY_ROUTER_IP="192.168.0.1"
    SKY_USERNAME="admin"
    SKY_PASSWORD="your_router_password"
    ```

3. **Run:**
    Put your TV or client device into WPS Search Mode, then run:
   ```bash
   chmod +x trigger_wps.sh
    ./trigger_wps.sh
    ```

---

## How It Works

The script automates the RDK-B web interface flow:
1. Pins `myrouter.io` to `192.168.0.1` via cURL.
2. Initializes the `DUKSID` session cookie.
3. Authenticates against `/check.jst`.
4. Extracts the active `csrfp_token`.
5. Sends the PushButton payload to `/actionHandler/ajaxSet_wps_config.jst`.

All communication is strictly local (LAN).

---

## License

MIT

--- 

Development aided by Google Gemini.