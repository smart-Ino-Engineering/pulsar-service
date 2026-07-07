"""
Safari Pro: Ultimate SDK Integration Test
Tests the Fluent API, Auto-Provisioning, Time Parsing, and Pydantic Routing.
"""
import time
import threading
import logging
from pydantic import BaseModel

from smartinno.messaging import MessageClient
from smartinno.apache_pulsar import PulsarConfig

# Configure beautiful logging
logging.basicConfig(
    level=logging.INFO, 
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("SafariPro.Test")

# 1. Define our strict Data Model
class FlightBooking(BaseModel):
    booking_id: str
    flight_number: str
    status: str

# 2. Configure the HA Network Profile
config = PulsarConfig(
    host="109.205.180.118",
    port=6651,
    admin_port=8085,
    cluster_name="cluster-a", # Ensures the Admin API authorizes this cluster
    subscription_name="fluent-worker-group"
)

# 3. Initialize the Unified Client
app = MessageClient(backend="pulsar", pulsar_config=config, mock_mode=False)

# ==========================================
# PART A: THE CONSUMER (Worker Node)
# ==========================================
@app.on("flight-bookings", tenant="default", namespace="public", strategy="shared")
def handle_booking(booking: FlightBooking):
    logger.info("=" * 50)
    logger.info(f"📥 [WORKER] Received Booking: {booking.booking_id}")
    logger.info(f"   Flight: {booking.flight_number}")
    logger.info(f"   Status: {booking.status}")
    logger.info("=" * 50)


# ==========================================
# PART B: THE PRODUCER (Web API Node)
# ==========================================
def simulate_web_traffic():
    """Runs in the background to simulate a user booking a flight."""
    # Wait 3 seconds to let the Pulsar Consumer connect first
    time.sleep(3)
    logger.info("🚀 [WEB_API] Simulating incoming user traffic...")
    
    booking_data = FlightBooking(
        booking_id="BK-999888", 
        flight_number="KQ-100", 
        status="CONFIRMED"
    )
    
    try:
        # ✨ THE FLUENT API IN ACTION ✨
        msg_id = (app.isolate_by_tenant("default")
                     .inside_namespace("public")
                     .auto_provision() # Will automatically hit Admin API if missing!
                     .smart_send(
                         topic="flight-bookings",
                         message=booking_data,
                         delay_delivery="2s", # Holds message invisible for 2 seconds
                         expire_after="24h"   # Drops message if broker goes down for a whole day
                     ))
        
        logger.info(f"📤 [WEB_API] Successfully published! Message ID: {msg_id}")
        logger.info("⏳ [WEB_API] Notice how the worker won't see it for exactly 2 seconds (Delayed Delivery)...")
        
    except Exception as e:
        logger.error(f"❌ Failed to publish: {e}")


if __name__ == "__main__":
    # Fire the simulated traffic in a background thread
    threading.Thread(target=simulate_web_traffic, daemon=True).start()
    
    # Start the Safari Pro SDK Router (Blocks the main thread)
    logger.info("Starting Safari Pro Unified SDK...")
    try:
        app.start(block=True)
    except KeyboardInterrupt:
        logger.info("Shutting down cleanly.")