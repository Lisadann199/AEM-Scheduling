# -*- coding: utf-8 -*-
"""
Created on Tue Mar 25 10:34:48 2025

@author: mariu
"""


import requests
import time
from threading import Thread
import pandas as pd

# === Config
ENAPTER_TOKEN = "fd25d83b0d6dd1447f9454b16d22259ba2084c2d11e337587100b6fc0ddac8c7"
BROKER_IP = "172.18.5.105"
COMMAND_ENDPOINT = f"http://{BROKER_IP}/api/commands/v1/execute"

# === Device IDs for each stack
STACKS = {
    "342A": "29ee3293-8b22-4693-a031-b600d9c83c21",
    "A568": "3a0747d1-3540-48ef-8c8f-348ef94ec0d4",
    "AD7F": "2f6d995a-1142-4726-a574-93bd4857d011"
}

# List of commands
commands = {
    "set_production_rate": True,
    "start": False,
    "stop": False,
    "reset": False,
    "force_water_filling": False,
    "preheat": False,
    "stop_preheat": False 
}

# === Function to send command
def send_command(stack_name, command_name, value=None):
    if stack_name not in STACKS:
        raise ValueError(f"Stack {stack_name} not found.")

    payload = {
        "device_id": STACKS[stack_name],
        "command_name": command_name
    }

    if value is not None:
        payload["arguments"] = {"value": round(float(value), 1)}

    headers = {
        "X-Enapter-Auth-Token": ENAPTER_TOKEN,
        "Content-Type": "application/json"
    }

    try:
        response = requests.post(COMMAND_ENDPOINT, json=payload, headers=headers)
        response.raise_for_status()
        timestamp = time.strftime("%H:%M:%S")
        print("timestamp: ", f"Command sent: {payload}")
        print(f"Response: {response.json()}")
        return response.json()
    except requests.RequestException as e:
        print(f"Failed to send command: {e}")
        return None
    
# # Mock function for testing
# def send_command(stack_name, command_name, value=None):
#     timestamp = time.strftime("%H:%M:%S")
#     print(f"[{timestamp}] (MOCK) Sending command to {stack_name}: {command_name} {f'value={value}' if value is not None else ''}")

# === Function to run scheduled list of commands
def run_scheduled_commands(filepath):
    df = pd.read_csv(filepath, sep=None, engine="python", skiprows=[1])
    df.fillna("", inplace=True)

    start_time = time.time()
    cumulative_duration = 0

    for idx, row in df.iterrows():
        duration = float(row['duration']) if row['duration'] != "" else 0
        cumulative_duration += duration

        
        # Go through each stack column
        for col in df.columns:
            if col in ["duration", "commands", "argument"]:
                continue

            if str(row[col]).strip() == "1":
                stack_name = col.strip().upper()
                command_name = row["commands"]
                argument = row["argument"]

                Thread(
                    target=send_command,
                    args=(stack_name, command_name, float(argument) if argument != "" else None),
                    daemon=True
                ).start()
        # Wait until the cumulative time is reached
        now = time.time()
        elapsed = now - start_time
        if elapsed < cumulative_duration:
            time.sleep(cumulative_duration - elapsed)


# Main loop
if __name__ == "__main__":
    
    #"""
    # Run scheduled commands file
    run_scheduled_commands("converted_commands.csv")


    #run_scheduled_commands("pldk_converted_commands.csv")

    # Stop stacks at the end of the loop
    #time.sleep(10)
    #send_command("342A", "stop")
    #send_command("A568", "stop")
    #send_command("AD7F", "stop")
    #"""
    
    send_command("A568", "set_production_rate", 90)



    # Send individual commands
    """
    send_command("342A", "start")
    send_command("A568", "start")
    send_command("AD7F", "start")
    time.sleep(5)
    send_command("342A", "set_production_rate", 60)
    send_command("A568", "set_production_rate", 60)
    send_command("AD7F", "set_production_rate", 60)
    # time.sleep(60)
    #send_command("342A", "preheat")
    #send_command("342A", "stop_preheat")
    """

#%%
"""
# SEND COMMANDS LIST
# Send commands from XOLTA BESS controller

# def send_enapter_commands(command_list, device_id, broker_ip, token):
    url = f"http://{broker_ip}/api/commands/v1/execute"
    headers = {
        "X-Enapter-Auth-Token": token,
        "Content-Type": "application/json"
    }

    for cmd in command_list:
        payload = {
            "device_id": device_id,
            "command_name": cmd["commands"]
        }
        if "argument" in cmd:
            payload["arguments"] = {"value": round(cmd["argument"], 1)}

        try:
            response = requests.post(url, json=payload, headers=headers)
            print(f" Sent: {cmd['commands']}, Status: {response.status_code}")
        except requests.RequestException as e:
            print(f" Failed: {cmd['commands']} - {e}")
            
# Example    
commands = [{'commands': 'start'},
 {'commands': 'batt_charge', 'argument': 9304.965087890638},
 {'commands': 'batt_discharge', 'argument': 0},
 {'commands': 'set_production_rate', 'argument': 100}]

# send_enapter_commands(commands, device_id=STACKS["342A"], broker_ip=BROKER_IP, token=ENAPTER_TOKEN)
"""