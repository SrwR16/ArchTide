#!/usr/bin/env python3
import json
import os

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    env_path = os.path.abspath(os.path.join(script_dir, "../../.env"))
    
    cid = ""
    sec = ""
    if os.path.exists(env_path):
        with open(env_path, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    k, v = line.split('=', 1)
                    if k.strip() == "GMAIL_CLIENT_ID":
                        cid = v.strip()
                    elif k.strip() == "GMAIL_CLIENT_SECRET":
                        sec = v.strip()
                        
    print(json.dumps({
        "client_id": cid,
        "client_secret": sec
    }))

if __name__ == "__main__":
    main()
