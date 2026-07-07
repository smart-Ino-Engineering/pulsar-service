import pulsar
import time
import threading

def run_consumer():
    try:
        print("[Consumer] Initializing raw Pulsar Client...")
        client = pulsar.Client('pulsar://127.0.0.1:6650')
        
        print("[Consumer] Subscribing to topic...")
        consumer = client.subscribe('persistent://public/default/test-raw-topic', 'test-subscription')
        
        print("[Consumer] Waiting for message...")
        msg = consumer.receive(timeout_millis=10000)
        print(f"[Consumer] Received message: '{msg.data().decode('utf-8')}' id='{msg.message_id()}'")
        consumer.acknowledge(msg)
        
        consumer.close()
        client.close()
    except Exception as e:
        print(f"[Consumer] Error: {e}")

def run_producer():
    try:
        # Wait a moment for consumer to be ready
        time.sleep(1)
        print("[Producer] Initializing raw Pulsar Client...")
        client = pulsar.Client('pulsar://127.0.0.1:6650')
        
        print("[Producer] Creating producer...")
        producer = client.create_producer('persistent://public/default/test-raw-topic')
        
        message = "Hello from Raw Pulsar!"
        print(f"[Producer] Sending message: '{message}'")
        producer.send(message.encode('utf-8'))
        
        producer.close()
        client.close()
    except Exception as e:
        print(f"[Producer] Error: {e}")

if __name__ == "__main__":
    print("=== Raw Pulsar Client Integration Test ===")
    
    # Run consumer in background thread
    t = threading.Thread(target=run_consumer)
    t.start()
    
    # Run producer
    run_producer()
    
    # Wait for consumer to finish
    t.join()
    print("Test finished.")
