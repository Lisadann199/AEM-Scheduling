

import paho.mqtt.client as mqtt
import json
import threading
import time
from datetime import datetime

# === Config ===
BROKER = '172.18.5.105'  # Replace with actual IP
PORT = 9883
USERNAME = 'pldk'
PASSWORD = 'only4pldk'
TOPIC = 'telemetry/v1/#'  # You can make this more specific
# Topic stack IDs
stackid_342A = '342A4045C953B949B957E3B5B0946D5A964EDFDE'
stackid_A568 = 'A568B1F1615820619D52C4C9A07D466223CFD5EF'
stackid_AD7F = 'AD7F038191AC7F26612396BD65EC74740258D8CA'



# READ ONE TELEMETRY VALUE

def get_telemetry_value(stack_id, field_key, timeout=5):

    topic = f'telemetry/v1/{stack_id}'
    result = {'value': None}
    stop_event = threading.Event()

    def on_connect(client, userdata, flags, rc):
        if rc == 0:
            client.subscribe(topic)
        else:
            print(f"[MQTT] Connection failed for {stack_id}: {rc}")
            stop_event.set()

    def on_message(client, userdata, msg):
        try:
            payload = json.loads(msg.payload.decode())
            if field_key in payload:
                result['value'] = payload[field_key]
            else:
                print(f"[MQTT] Key '{field_key}' not in payload for {stack_id}")
        except json.JSONDecodeError:
            print(f"[MQTT] Failed to decode JSON from {stack_id}")
        finally:
            stop_event.set()
            client.disconnect()

    try:
        client = mqtt.Client()
        client.username_pw_set(USERNAME, PASSWORD)
        client.on_connect = on_connect
        client.on_message = on_message

        try:
            client.connect(BROKER, PORT, keepalive=60)
        except Exception as e:
            print(f"[MQTT] Could not connect to broker {BROKER}:{PORT} → {e}")
            return None
        
        client.loop_start()

        stop_event.wait(timeout)
        client.loop_stop()

    except Exception as e:
        print(f"[MQTT] Full exception while reading {field_key} from {stack_id}: {e}")
        return None

    return result['value']



# Example: 
stackid = stackid_342A # Choose stack
value = "electrolyte_tank_temperature" # Choose value

timestamp = get_telemetry_value(stackid, "timestamp")
print(datetime.fromtimestamp(timestamp))
print(f"{value} for {stackid}: {get_telemetry_value(stackid,value)}")
