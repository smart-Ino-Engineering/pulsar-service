import socket
import sys
import time

def test_tcp_connection(host, port, service_name):
    print(f"Checking TCP connection to {service_name} at {host}:{port}...")
    try:
        with socket.create_connection((host, port), timeout=5) as sock:
            print(f"SUCCESS: Connected to {service_name} at {host}:{port}!")
            return True
    except Exception as e:
        print(f"FAILED: Cannot connect to {service_name} at {host}:{port}. Error: {e}")
        return False

def test_pulsar_client(host):
    print(f"\nAttempting to initialize Pulsar client using pulsar://{host}:6650...")
    try:
        import pulsar
        client = pulsar.Client(f"pulsar://{host}:6650")
        print("SUCCESS: Pulsar Client initialized successfully!")
        client.close()
        return True
    except Exception as e:
        print(f"FAILED: Pulsar Client initialization failed: {e}")
        return False

if __name__ == "__main__":
    print("=== Safari Pro Connection Diagnostics ===")
    
    # Check localhost
    print("\n--- Checking Localhost (127.0.0.1) ---")
    test_tcp_connection("127.0.0.1", 6650, "Pulsar Broker")
    test_tcp_connection("127.0.0.1", 8080, "Pulsar Admin")
    test_tcp_connection("127.0.0.1", 6379, "Redis Fallback")
    
    # Check advertised IP
    print("\n--- Checking Advertised IP (109.205.180.118) ---")
    test_tcp_connection("109.205.180.118", 6650, "Pulsar Broker")
    test_tcp_connection("109.205.180.118", 8080, "Pulsar Admin")
    
    # Try actual client connection via localhost
    test_pulsar_client("127.0.0.1")
    
    # Try actual client connection via advertised IP
    test_pulsar_client("109.205.180.118")
    
    print("\nDiagnostics Completed.")
