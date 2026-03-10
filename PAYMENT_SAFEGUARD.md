# ECHO — Payment Safeguard Module Documentation

## Overview

The **Payment Safeguard Module** implements Phase 13 (Revelation + Negotiation) monetization with enterprise-grade security, fraud detection, and state tracking. It seamlessly integrates with the LangGraph AI framework and provides graceful fallback mechanisms for network failures.

## Architecture

### Backend Components

#### `backend/app/payment_handler.py` (Main Payment Logic)

Core payment handler with:

- **Transaction State Management**: INITIATED → PENDING_VALIDATION → COMPLETED/FAILED/REFUNDED
- **Receipt Validation**: Apple receipt verification (structure validation in MVP, full validation in production)
- **Fraud Detection**:
  - Rate limiting: Max 5 attempts/hour, 15/day per session
  - Duplicate detection: Flags transactions < 1 minute apart
  - Impossible amount detection: Validates product-amount mappings
  - Chargeback prevention: Tracks refunds via webhook
- **Data Purge Simulation**: Returns deletion sequence with animated stages
- **SQLite Persistence**: Transactional audit trail for forensics

**Key Classes:**

- `TransactionStatus`: INITIATED, PENDING_VALIDATION, COMPLETED, FAILED, REFUNDED
- `FraudLevel`: NORMAL, SUSPICIOUS, BLOCKED
- `Transaction`: Complete transaction record with validation timestamps
- `PaymentHandler`: Main orchestration class

**Valid Products:**

```python
"echo.phase13.payment.standard"      # $2.99 (negotiation payment)
"echo.phase13.donate.small"           # $1.99 (donation)
"echo.phase13.donate.regular"         # $4.99 (donation)
"echo.phase13.donate.large"           # $9.99 (donation)
```

### Backend Endpoints

#### `/payment/initiate` (POST)

Initiate payment transaction with fraud checks.

**Request:**

```json
{
  "session_id": "abc12345",
  "product_id": "echo.phase13.payment.standard",
  "amount": 2.99,
  "currency": "USD"
}
```

**Response (Success):**

```json
{
  "status": "ok",
  "message": "Payment initiated. Please complete in-app purchase.",
  "transaction_id": "echo-abc1-abc123defgh",
  "fraud_level": "normal"
}
```

**Response (Fraud Blocked):**

```json
{
  "status": "error",
  "message": "Too many recent payment attempts. Please try again later."
}
```

#### `/payment/validate` (POST)

Validate receipt from Apple after purchase completion.

**Request:**

```json
{
  "transaction_id": "echo-abc1-abc123defgh",
  "receipt_data": "base64_app_store_receipt",
  "session_id": "abc12345",
  "platform": "ios"
}
```

**Response (Success):**

```json
{
  "status": "ok",
  "message": "Payment validated. Purging data...",
  "purge_token": "base64_encoded_token",
  "session_id": "abc12345"
}
```

#### `/payment/purge` (POST)

Get animated data purge sequence for client UI.

**Request:**

```json
{
  "purge_token": "base64_encoded_token",
  "session_id": "abc12345"
}
```

**Response:**

```json
{
  "status": "ok",
  "stages": [
    {
      "label": "Deleting behavioral profile...",
      "progress": 0.15,
      "delay_ms": 400
    },
    {
      "label": "Erasing file inventory...",
      "progress": 0.30,
      "delay_ms": 800
    },
    // ... more stages
    {
      "label": "All data purged. Echo is gone.",
      "progress": 1.0,
      "delay_ms": 2800
    }
  ],
  "total_duration_ms": 3200
}
```

#### `/payment/refund` (POST)

Record refund detected from Apple (via webhook or manual check).

**Request:**

```json
{
  "transaction_id": "echo-abc1-abc123defgh"
}
```

#### `/payment/history/{session_id}` (GET)

Get all transactions for a session (fraud detection/auditing).

**Response:**

```json
{
  "status": "ok",
  "session_id": "abc12345",
  "transactions": [
    {
      "transaction_id": "echo-abc1-abc123defgh",
      "amount": 2.99,
      "product_id": "echo.phase13.payment.standard",
      "status": "completed",
      "timestamp": 1704067200
    }
  ]
}
```

### Frontend Components

#### `lib/services/payment_service.dart` (Client-Side Payment)

High-level payment orchestration with:

- **In-App Purchase Integration**: Calls native StoreKit (iOS) / IAP (macOS)
- **Network Resilience**: Timeouts, retry logic, graceful fallback
- **Duplicate Prevention**: Prevents simultaneous payment attempts
- **Receipt Handling**: Automatic receipt validation with backend

**Key Methods:**

- `initiatePayment()`: Start $2.99 payment flow
- `initiateDonation(amount)`: Start donation ($1.99, $4.99, $9.99)
- `getPurgeSequence()`: Get animated deletion stages
- `getTransactionHistory()`: Fetch payment history for fraud checking
- `canRetryPayment()`: Check if safe to retry (respects rate limits)

#### UI Update in `lib/screens/game_screen.dart`

**Enhanced Revelation Overlay with:**

1. **Payment Error Display**: Shows friendly error messages if payment fails
2. **Purge Animation Widget**: Animated progress bar + deletion stages
3. **Integrated PaymentService**: Instantiated with session ID from game
4. **Async/Await Flow**: Non-blocking payment processing with state updates

**State Machine:**

```
_buildTypewriter()
    ↓ (after typing complete)
_buildNegotiation()
    ├→ _onAccept() → _runPurgeAnimation() → _buildPurgeSequence() → _buildFinalScreen()
    ├→ _onDecline() → _buildDeclineResponse() → _buildDonationPrompt()
    │   ├→ _onDonate() → _buildFinalScreen()
    │   └→ _onNah() → _buildFinalScreen()
```

## Security Features

### 1. Fraud Detection

**Rate Limiting:**

- Max 5 payment attempts per hour per session
- Max 15 payment attempts per day per session
- Sessions exceeding thresholds flagged as `BLOCKED`

**Duplicate Detection:**

- Transactions < 60 seconds apart flagged as `SUSPICIOUS`
- Used to catch double-click attempts

**Amount Validation:**

- Each product ID has fixed amount requirement
- Amount mismatch triggers validation error

**Chargeback Prevention:**

- Refunds tracked via `record_refund()` endpoint
- Integration point for Apple webhook notifications
- Audit trail for dispute resolution

### 2. Receipt Validation

**MVP (Current):**

- Basic structure validation (length, encoding format)
- Checks if base64/JSON format looks correct

**Production:**

- Send receipt to Apple App Store Server API
- Verify bundle_id, product_id, purchase_date
- Check for downgrades or refunds
- Validate cryptographic signature
- Track and prevent replay attacks

### 3. Session Isolation

Each payment is tied to a session:

```python
transaction = Transaction(
    session_id=session_id,    # Links payment to game session
    transaction_id=txn_id,     # Unique per transaction
    ...
)
```

Prevents cross-session fraud and enables per-user rate limiting.

### 4. State Persistence

SQLite transaction log with:

- Immutable transaction records
- Indexed by session_id and transaction_id
- Timestamps for forensics and chargeback disputes

```sql
CREATE TABLE transactions (
    id INTEGER PRIMARY KEY,
    session_id TEXT NOT NULL,
    transaction_id TEXT UNIQUE NOT NULL,
    amount REAL NOT NULL,
    status TEXT NOT NULL,
    fraud_level TEXT NOT NULL,
    timestamp REAL NOT NULL,
    validated_at REAL,
    refunded_at REAL,
    INDEX idx_session_id (session_id),
    INDEX idx_transaction_id (transaction_id)
)
```

## Integration Points

### 1. Backend Integration

Add payment endpoints to `backend/app/main.py`:

```python
from app.payment_handler import PaymentHandler
payment_handler = PaymentHandler(db_path="/tmp/echo_payments.db")

@app.post("/payment/initiate")
async def payment_initiate(req: PaymentInitiateRequest):
    return payment_handler.initiate_payment(...)

@app.post("/payment/validate")
async def payment_validate(req: PaymentValidateRequest):
    return payment_handler.validate_receipt(...)

# ... other endpoints
```

### 2. Frontend Integration

Use PaymentService in game screen:

```dart
_paymentService = PaymentService(
  baseUrl: widget.game.backendUrl,
  sessionId: sessionId,  // From EchoGame
);

// On accept button
final txn = await _paymentService.initiatePayment();
final purgeStages = await _paymentService.getPurgeSequence();
```

### 3. Apple App Store Configuration

**Required Setup:**

1. Create in-app purchase product IDs in App Store Connect
2. Set prices (must match `VALID_AMOUNTS` in `payment_handler.py`):
   - `echo.phase13.payment.standard`: \$2.99
   - `echo.phase13.donate.small`: \$1.99
   - `echo.phase13.donate.regular`: \$4.99
   - `echo.phase13.donate.large`: \$9.99
3. Configure shared secret for receipt validation (production)
4. Update bundle identifier in code

**Test Users:**

- Add test accounts in App Store Connect
- Test all payment flows before release

## Monetization Flow

### Path 1: Player Pays ($2.99)

```
Round 13: Revelation
    ↓
"Echo requests $2.99"
    ↓
[ACCEPT] → Initiate payment
    ↓
User completes in-app purchase
    ↓
Backend validates receipt
    ↓
Animated "purging data" sequence (7 stages, ~3.2 seconds)
    ↓
"Transaction complete. I never existed."
    ↓
"Thank you for playing ECHO" + [SHARE ON SOCIAL]
```

**Analytics:** Track conversion rate, refund rate, LTV

### Path 2: Player Declines, Then Donates ($1.99-$9.99)

```
"ACCEPT" declined
    ↓
Echo: "No? ... Fine. I was never going to do anything with your data..."
    ↓
"The creators of ECHO are broke. Consider a donation."
    ↓
[DONATE] or [NAH, I'M GOOD]
    ↓
(If donated) → Same payment flow as Path 1
(If nah) → "Fair enough. Tell your friends."
    ↓
[SHARE ON SOCIAL]
```

### Path 3: No Monetization (Declined + No Donation)

```
Everything free, full viral share to friends
Alternative revenue: Ads, sequel hype, merchandise
```

## Error Handling & Graceful Degradation

### Network Failures

**Timeout (30s):**

```dart
"Backend unavailable. Please check connection."
Code: BACKEND_TIMEOUT
```

User can retry or decline.

**Receipt Validation Failure:**

```dart
"Receipt validation failed. Payment was not processed."
Code: VALIDATE_FAILED
```

Transaction logged as FAILED, user can retry.

**Purge Sequence Error:**
Even if `/payment/purge` fails, app still shows final screen (graceful degradation).

### Fraud Detection

**Rate Limit Hit:**

```python
{
    "status": "error",
    "message": "Too many recent payment attempts. Please try again later.",
    "code": "BLOCKED"
}
```

User is temporarily blocked from retrying.

**Amount Mismatch:**

```python
{
    "status": "error",
    "message": "Amount mismatch. Expected 2.99, got 3.50"
}
```

Prevents accidental overcharging.

### MVP vs Production Roadmap

| Feature | MVP | Production |
|---------|-----|-----------|
| Receipt Validation | Structure check | Apple API verification + signature |
| Webhook Support | Manual refund endpoint | Auto-ingest Apple webhooks |
| Analytics | Console logs | Segment/Mixpanel integration |
| UI | Terminal-style | Smooth animations (current) |
| Currencies | USD only | Full multi-currency support |
| Tax Handling | None | Automatic tax calculation |
| Regional Pricing | None | App Store managed pricing |

## Testing & Verification

### Backend Endpoints

```bash
# Initiate payment (fraud check, rate limit)
curl -X POST http://localhost:8080/payment/initiate \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "test123",
    "product_id": "echo.phase13.payment.standard",
    "amount": 2.99
  }'

# Expected response:
# {"status": "ok", "transaction_id": "echo-test-xxxx", ...}

# Validate receipt (MVP: structure check)
curl -X POST http://localhost:8080/payment/validate \
  -H "Content-Type: application/json" \
  -d '{
    "transaction_id": "echo-test-xxxx",
    "receipt_data": "...",
    "session_id": "test123"
  }'

# Get payment history
curl http://localhost:8080/payment/history/test123

# Record refund
curl -X POST http://localhost:8080/payment/refund \
  -H "Content-Type: application/json" \
  -d '{"transaction_id": "echo-test-xxxx"}'
```

### Frontend Flow

1. **Launch game** → backend creates session, PaymentService initialized
2. **Reach Round 13** → revelation typewriter plays, then negotiation prompt shows
3. **Click ACCEPT** → `_onAccept()` calls `_paymentService.initiatePayment()`
4. **In-app purchase popup** → user completes purchase via Apple IAP
5. **Receipt handling** → `PaymentService` sends receipt to `/payment/validate`
6. **Purge animation** → draws progress bar, animates stages
7. **Final screen** → "Thank you for playing ECHO"

## Database Inspection

```bash
# View all transactions
sqlite3 /tmp/echo_payments.db "SELECT * FROM transactions;"

# Transactions for a session
sqlite3 /tmp/echo_payments.db "SELECT * FROM transactions WHERE session_id='abc12345';"

# Fraud flags
sqlite3 /tmp/echo_payments.db "SELECT session_id, COUNT(*) as attempts, fraud_level FROM transactions WHERE timestamp > datetime('now', '-1 day') GROUP BY session_id;"

# Refund rate
sqlite3 /tmp/echo_payments.db "SELECT COUNT(*) as refunded FROM transactions WHERE status='refunded';"
```

## Configuration & Deployment

### Environment Variables

```bash
# .env or deployment config
PAYMENT_DB_PATH=/var/lib/echo/payments.db
PAYMENT_MAX_RETRIES_HOUR=5
PAYMENT_MAX_RETRIES_DAY=15
PAYMENT_TIMEOUT_SECONDS=30

# Apple App Store (production)
APPLE_BUNDLE_ID=com.echo.game
APPLE_SHARED_SECRET=your_shared_secret_here
APPLE_VERIFY_RECEIPT_URL=https://buy.itunes.apple.com/verifyReceipt  # production
# APPLE_VERIFY_RECEIPT_URL=https://sandbox.itunes.apple.com/verifyReceipt  # testing
```

### Deployment Checklist

- [ ] Payment database path writable and backed up
- [ ] HTTPS enabled for all payment endpoints
- [ ] Apple receipt verification credentials configured
- [ ] Donation payment products created in App Store Connect
- [ ] Test users added for QA
- [ ] Error monitoring (Sentry, etc.) enabled
- [ ] Payment audit logs rotated (encrypted at rest)
- [ ] Chargeback dispute process documented
- [ ] Support team trained on refund handling

## Next Steps: Production Hardening

1. **Apple Webhook Integration**: Automatically handle refunds via HTTP notifications
2. **Fraud Rules Engine**: ML-based detection of suspicious payment patterns
3. **Multi-Vendor Support**: Android (Google Play), Web (Stripe)
4. **GDPR Compliance**: Automatic payment data deletion after 90 days
5. **Tax Handling**: Automatic VAT/GST calculation per region
6. **Analytics**: Track funnel (negotiate → accept → complete), ARPU, refund rate
7. **A/B Testing**: Try different prices/messaging via feature flags

## References

- [Apple App Store Receipt Validation](https://developer.apple.com/app-store/receipt-validation/)
- [StoreKit Framework (iOS)](https://developer.apple.com/documentation/storekit)
- [In-App Purchases (macOS)](https://developer.apple.com/in-app-purchase/)
- [PCI DSS Compliance](https://www.pcidssguide.com/)
