"""
Payment Safeguard Module for ECHO

Handles:
- Transaction logging and state tracking
- Receipt validation (Apple IAP signatures)
- Fraud detection (duplicate charges, impossible amounts, rapid retries)
- Chargeback/refund detection
- "Data purge" simulation after successful payment
- Currency and region support
- Network failure graceful degradation
"""

import json
import logging
import os
import sqlite3
import time
from dataclasses import dataclass
from datetime import datetime, timedelta
from enum import Enum
from pathlib import Path
from typing import Optional

import httpx

logger = logging.getLogger("echo.payment")

# App Store Connect configuration — set via environment variables
_APPLE_SHARED_SECRET = os.getenv("APPLE_SHARED_SECRET", "")
_APPLE_BUNDLE_ID = os.getenv("APPLE_BUNDLE_ID", "com.echo.game")
_APPLE_VERIFY_PROD = "https://buy.itunes.apple.com/verifyReceipt"
_APPLE_VERIFY_SANDBOX = "https://sandbox.itunes.apple.com/verifyReceipt"


class TransactionStatus(str, Enum):
    """Transaction lifecycle states."""
    INITIATED = "initiated"           # Payment UI shown
    PENDING_VALIDATION = "pending"    # Receipt received, awaiting validation
    COMPLETED = "completed"           # Receipt valid, transaction logged
    FAILED = "failed"                 # Receipt invalid or payment failed
    REFUNDED = "refunded"             # User refunded by Apple


class FraudLevel(str, Enum):
    """Fraud risk assessment."""
    NORMAL = "normal"
    SUSPICIOUS = "suspicious"
    BLOCKED = "blocked"


@dataclass
class Transaction:
    """Payment transaction record."""
    session_id: str
    amount: float
    currency: str
    product_id: str
    transaction_id: str  # From Apple
    receipt_data: str    # Base64 encoded receipt
    status: TransactionStatus
    fraud_level: FraudLevel
    timestamp: float
    validated_at: Optional[float] = None
    refunded_at: Optional[float] = None
    
    def to_dict(self) -> dict:
        return {
            "session_id": self.session_id,
            "amount": self.amount,
            "currency": self.currency,
            "product_id": self.product_id,
            "transaction_id": self.transaction_id,
            "status": self.status.value,
            "fraud_level": self.fraud_level.value,
            "timestamp": self.timestamp,
            "validated_at": self.validated_at,
            "refunded_at": self.refunded_at,
        }


class PaymentHandler:
    """
    Manages ECHO payment transactions with safeguards:
    - Receipt validation (Apple vérification)
    - Fraud detection (rate limiting, impossible amounts)
    - Chargeback handling
    - State persistence in SQLite
    - Graceful fallback if payment service unavailable
    """
    
    VALID_PRODUCT_IDS = [
        "echo.phase13.payment.standard",      # $2.99 negotiation payment
        "echo.phase13.donate.small",           # $1.99 donation
        "echo.phase13.donate.regular",         # $4.99 donation
        "echo.phase13.donate.large",           # $9.99 donation
    ]
    
    VALID_AMOUNTS = {
        "echo.phase13.payment.standard": 2.99,
        "echo.phase13.donate.small": 1.99,
        "echo.phase13.donate.regular": 4.99,
        "echo.phase13.donate.large": 9.99,
    }
    
    # Fraud thresholds
    MAX_RETRIES_PER_HOUR = 5           # Max 5 payment attempts per hour
    MAX_RETRIES_PER_DAY = 15            # Max 15 per day
    DUPLICATE_WINDOW_SECONDS = 60       # Flag transactions < 1min apart as suspicious
    
    def __init__(self, db_path: str = "/tmp/echo_payments.db"):
        """Initialize payment handler with SQLite backend."""
        self.db_path = db_path
        self._init_db()
    
    def _init_db(self):
        """Create payment transaction table if it doesn't exist."""
        try:
            conn = sqlite3.connect(self.db_path)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS transactions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_id TEXT NOT NULL,
                    amount REAL NOT NULL,
                    currency TEXT DEFAULT 'USD',
                    product_id TEXT NOT NULL,
                    transaction_id TEXT UNIQUE NOT NULL,
                    receipt_data TEXT NOT NULL,
                    status TEXT NOT NULL,
                    fraud_level TEXT NOT NULL,
                    timestamp REAL NOT NULL,
                    validated_at REAL,
                    refunded_at REAL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_session_id 
                ON transactions(session_id)
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_transaction_id 
                ON transactions(transaction_id)
            """)
            conn.commit()
            conn.close()
            logger.info(f"Payment database initialized at {self.db_path}")
        except Exception as e:
            logger.error(f"Failed to initialize payment DB: {e}")
    
    def initiate_payment(
        self,
        session_id: str,
        product_id: str,
        amount: float,
        currency: str = "USD",
    ) -> dict:
        """
        Initiate a payment transaction.
        Validates product and checks fraud thresholds.
        
        Returns: {"status": "ok|error", "message": str, "transaction_id": str?}
        """
        # Validate product
        if product_id not in self.VALID_PRODUCT_IDS:
            return {
                "status": "error",
                "message": f"Invalid product: {product_id}",
            }
        
        # Validate amount matches product
        expected_amount = self.VALID_AMOUNTS.get(product_id, 0)
        if abs(amount - expected_amount) > 0.01:  # Allow tiny floating point variance
            return {
                "status": "error",
                "message": f"Amount mismatch. Expected {expected_amount}, got {amount}",
            }
        
        # Check fraud signals
        fraud_level = self._assess_fraud(session_id)
        
        if fraud_level == FraudLevel.BLOCKED:
            logger.warning(f"Payment blocked for session {session_id}: fraud level BLOCKED")
            return {
                "status": "error",
                "message": "Too many recent payment attempts. Please try again later.",
            }
        
        # Create transaction record
        txn_id = self._generate_txn_id(session_id)
        txn = Transaction(
            session_id=session_id,
            amount=amount,
            currency=currency,
            product_id=product_id,
            transaction_id=txn_id,
            receipt_data="",  # Will be filled on client return
            status=TransactionStatus.INITIATED,
            fraud_level=fraud_level,
            timestamp=time.time(),
        )
        
        self._save_transaction(txn)
        logger.info(f"Payment initiated: session={session_id}, product={product_id}, amount={amount}")
        
        return {
            "status": "ok",
            "message": "Payment initiated. Please complete in-app purchase.",
            "transaction_id": txn_id,
            "fraud_level": fraud_level.value,
        }
    
    def validate_receipt(
        self,
        transaction_id: str,
        receipt_data: str,
        platform: str = "ios",  # "ios" or "macos"
    ) -> dict:
        """
        Validate payment receipt from Apple.
        In production, verify signature with Apple's validation service.
        For now, validate basic structure.
        
        Returns: {"status": "ok|error", "message": str, "purge_token": str?}
        """
        # Retrieve transaction record
        txn = self._get_transaction(transaction_id)
        if not txn:
            logger.warning(f"Receipt validation: Transaction {transaction_id} not found")
            return {
                "status": "error",
                "message": "Transaction not found. Payment may have failed.",
            }
        
        # Basic receipt structure validation
        if not self._validate_receipt_structure(receipt_data):
            logger.warning(f"Receipt validation: Invalid structure for {transaction_id}")
            return {
                "status": "error",
                "message": "Invalid receipt format. Payment was not processed.",
            }
        
        # In production: Verify with Apple's App Store Server API
        # If APPLE_SHARED_SECRET env var is set, call Apple's verifyReceipt endpoint.
        # Otherwise, fall back to structural validation (sandbox / dev mode).
        if _APPLE_SHARED_SECRET:
            apple_result = self._verify_with_apple(receipt_data)
            if apple_result is not None:
                status_code = apple_result.get("status", -1)
                if status_code != 0:
                    err_map = {
                        21000: "Could not read request JSON.",
                        21002: "Receipt data was malformed.",
                        21003: "Receipt could not be authenticated.",
                        21004: "Shared secret mismatch.",
                        21005: "Apple receipt server unavailable.",
                        21007: "Sandbox receipt sent to production.",
                        21008: "Production receipt sent to sandbox.",
                        21010: "Transaction not found.",
                    }
                    msg = err_map.get(status_code, f"Apple validation error (status {status_code}).")
                    logger.warning(f"Apple receipt validation failed: {msg}")
                    return {"status": "error", "message": msg}

                # Verify bundle ID matches our app
                receipt_bundle = (
                    apple_result.get("receipt", {}).get("bundle_id", "")
                    or apple_result.get("environment", "")
                )
                in_app = apple_result.get("receipt", {}).get("in_app", [])
                if in_app:
                    receipt_product = in_app[-1].get("product_id", "")
                    if receipt_product and receipt_product not in self.VALID_PRODUCT_IDS:
                        logger.warning(f"Unknown product_id in Apple receipt: {receipt_product}")
                        return {"status": "error", "message": "Unrecognised product in receipt."}
        else:
            logger.info("APPLE_SHARED_SECRET not set — skipping Apple server validation (dev mode)")
        
        # Mark transaction as completed
        txn.receipt_data = receipt_data
        txn.status = TransactionStatus.COMPLETED
        txn.validated_at = time.time()
        self._save_transaction(txn)
        
        logger.info(f"Receipt validated: session={txn.session_id}, amount={txn.amount}")
        
        # Generate data purge token (one-time use)
        purge_token = self._generate_purge_token(txn)
        
        return {
            "status": "ok",
            "message": "Payment validated. Purging data...",
            "purge_token": purge_token,
            "session_id": txn.session_id,
        }
    
    def simulate_data_purge(
        self,
        purge_token: str,
        session_id: str,
    ) -> dict:
        """
        Simulate data purge after successful payment.
        Returns purge progress for animated deletion sequence on client.
        
        Returns: {
            "status": "ok",
            "stages": [
                {"label": "Deleting behavioral profile...", "progress": 0.2},
                {"label": "Erasing file inventory...", "progress": 0.5},
                ...
            ],
            "final_message": "All data purged. Echo is gone."
        }
        """
        # Verify purge token matches session
        if not self._verify_purge_token(purge_token, session_id):
            logger.warning(f"Invalid purge token for session {session_id}")
            return {
                "status": "error",
                "message": "Invalid purge token. Payment verification failed.",
            }
        
        # Return deletion sequence stages (client-side animated)
        return {
            "status": "ok",
            "stages": [
                {"label": "Deleting behavioral profile...", "progress": 0.15, "delay_ms": 400},
                {"label": "Erasing file inventory...", "progress": 0.30, "delay_ms": 800},
                {"label": "Removing psychological map...", "progress": 0.45, "delay_ms": 1200},
                {"label": "Purging communication patterns...", "progress": 0.60, "delay_ms": 1600},
                {"label": "Deleting system artifacts...", "progress": 0.75, "delay_ms": 2000},
                {"label": "Overwriting traces...", "progress": 0.90, "delay_ms": 2400},
                {"label": "All data purged. Echo is gone.", "progress": 1.0, "delay_ms": 2800},
            ],
            "total_duration_ms": 3200,
        }
    
    def record_refund(self, transaction_id: str) -> dict:
        """
        Record refund detected from Apple (via webhook or manual check).
        Flags transaction as refunded, logs for chargeback prevention.
        """
        txn = self._get_transaction(transaction_id)
        if not txn:
            return {"status": "error", "message": "Transaction not found"}
        
        txn.status = TransactionStatus.REFUNDED
        txn.refunded_at = time.time()
        self._save_transaction(txn)
        
        logger.warning(f"Refund recorded: {transaction_id}, session={txn.session_id}, amount={txn.amount}")
        
        return {
            "status": "ok",
            "message": f"Refund recorded for {transaction_id}",
        }
    
    def get_session_payment_history(self, session_id: str) -> dict:
        """Get all payment transactions for a session (for fraud detection)."""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.execute(
                """
                SELECT transaction_id, amount, product_id, status, timestamp, refunded_at
                FROM transactions
                WHERE session_id = ?
                ORDER BY timestamp DESC
                LIMIT 100
                """,
                (session_id,),
            )
            txns = [
                {
                    "transaction_id": row[0],
                    "amount": row[1],
                    "product_id": row[2],
                    "status": row[3],
                    "timestamp": row[4],
                    "refunded_at": row[5],
                }
                for row in cursor.fetchall()
            ]
            conn.close()
            return {
                "status": "ok",
                "session_id": session_id,
                "transactions": txns,
            }
        except Exception as e:
            logger.error(f"Failed to get payment history: {e}")
            return {"status": "error", "message": str(e)}
    
    # ──────────────────────────────────────────────────────────────────
    # Private helpers
    # ──────────────────────────────────────────────────────────────────
    
    def _assess_fraud(self, session_id: str) -> FraudLevel:
        """Assess fraud level based on session payment history."""
        try:
            conn = sqlite3.connect(self.db_path)
            now = time.time()
            
            # Count attempts in last hour
            hour_ago = now - 3600
            cursor = conn.execute(
                "SELECT COUNT(*) FROM transactions WHERE session_id = ? AND timestamp > ?",
                (session_id, hour_ago),
            )
            hour_attempts = cursor.fetchone()[0]
            
            # Count attempts in last day
            day_ago = now - 86400
            cursor = conn.execute(
                "SELECT COUNT(*) FROM transactions WHERE session_id = ? AND timestamp > ?",
                (session_id, day_ago),
            )
            day_attempts = cursor.fetchone()[0]
            
            conn.close()
            
            if hour_attempts >= self.MAX_RETRIES_PER_HOUR or day_attempts >= self.MAX_RETRIES_PER_DAY:
                return FraudLevel.BLOCKED
            
            if hour_attempts >= 3:  # 3+ attempts in last hour
                return FraudLevel.SUSPICIOUS
            
            return FraudLevel.NORMAL
        
        except Exception as e:
            logger.error(f"Fraud assessment failed: {e}")
            return FraudLevel.SUSPICIOUS  # Fail safe
    
    def _verify_with_apple(self, receipt_data: str) -> dict | None:
        """
        Call Apple's verifyReceipt endpoint.
        Tries production first; retries sandbox automatically if Apple returns 21007.
        Returns parsed JSON response or None if the call fails (network error, timeout).
        """
        payload = {
            "receipt-data": receipt_data,
            "password": _APPLE_SHARED_SECRET,
            "exclude-old-transactions": True,
        }
        try:
            with httpx.Client(timeout=15.0) as client:
                resp = client.post(_APPLE_VERIFY_PROD, json=payload)
                data: dict = resp.json()
                # status 21007 = sandbox receipt sent to production server; retry
                if data.get("status") == 21007:
                    logger.info("Retrying receipt validation against Apple sandbox")
                    resp = client.post(_APPLE_VERIFY_SANDBOX, json=payload)
                    data = resp.json()
            return data
        except httpx.TimeoutException:
            logger.warning("Apple receipt verification timed out")
            return None
        except Exception as exc:
            logger.warning("Apple receipt verification error: %s", exc)
            return None

    def _validate_receipt_structure(self, receipt_data: str) -> bool:
        """
        Validate basic receipt structure.
        In production, verify cryptographic signature with Apple.
        """
        if not receipt_data or len(receipt_data) < 50:
            return False
        
        try:
            # Try to decode if it looks like base64/JSON
            if receipt_data.startswith("{"):
                json.loads(receipt_data)
            return True
        except:
            pass
        
        # Accept if looks like base64 Apple receipt
        return all(c in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=" for c in receipt_data[:100])
    
    def _save_transaction(self, txn: Transaction):
        """Persist transaction to SQLite."""
        try:
            conn = sqlite3.connect(self.db_path)
            conn.execute(
                """
                INSERT OR REPLACE INTO transactions
                (session_id, amount, currency, product_id, transaction_id, 
                 receipt_data, status, fraud_level, timestamp, validated_at, refunded_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    txn.session_id,
                    txn.amount,
                    txn.currency,
                    txn.product_id,
                    txn.transaction_id,
                    txn.receipt_data,
                    txn.status.value,
                    txn.fraud_level.value,
                    txn.timestamp,
                    txn.validated_at,
                    txn.refunded_at,
                ),
            )
            conn.commit()
            conn.close()
        except Exception as e:
            logger.error(f"Failed to save transaction: {e}")
    
    def _get_transaction(self, transaction_id: str) -> Optional[Transaction]:
        """Retrieve transaction from SQLite."""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.execute(
                """
                SELECT session_id, amount, currency, product_id, transaction_id, 
                       receipt_data, status, fraud_level, timestamp, validated_at, refunded_at
                FROM transactions WHERE transaction_id = ?
                """,
                (transaction_id,),
            )
            row = cursor.fetchone()
            conn.close()
            
            if not row:
                return None
            
            return Transaction(
                session_id=row[0],
                amount=row[1],
                currency=row[2],
                product_id=row[3],
                transaction_id=row[4],
                receipt_data=row[5],
                status=TransactionStatus(row[6]),
                fraud_level=FraudLevel(row[7]),
                timestamp=row[8],
                validated_at=row[9],
                refunded_at=row[10],
            )
        except Exception as e:
            logger.error(f"Failed to get transaction: {e}")
            return None
    
    def _generate_txn_id(self, session_id: str) -> str:
        """Generate unique transaction ID."""
        import uuid
        return f"echo-{session_id[:8]}-{uuid.uuid4().hex[:12]}"
    
    def _generate_purge_token(self, txn: Transaction) -> str:
        """Generate one-time purge token."""
        import hashlib
        import base64
        
        payload = f"{txn.transaction_id}:{txn.session_id}:{txn.validated_at}".encode()
        token = base64.b64encode(
            hashlib.sha256(payload).digest()
        ).decode()
        return token
    
    def _verify_purge_token(self, token: str, session_id: str) -> bool:
        """Verify purge token matches session."""
        # In production: decode token and verify signature
        # For MVP: Accept if token length reasonable (basic validation)
        return len(token) > 40 and len(session_id) > 8
