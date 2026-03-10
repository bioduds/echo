// Payment Service — ECHO Phase 13 In-App Purchase Integration
//
// Handles:
// - In-app purchase flow for Phase 13 negotiation via Apple StoreKit
// - Receipt validation with backend
// - Transaction state tracking
// - Network failure graceful fallback
// - Duplicate charge prevention

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';

class PaymentException implements Exception {
  final String message;
  final String? code;

  PaymentException(this.message, {this.code});

  @override
  String toString() => 'PaymentException: $message${code != null ? ' ($code)' : ''}';
}

class PaymentTransaction {
  final String transactionId;
  final String productId;
  final double amount;
  final String currency;
  final String status; // 'initiated', 'pending', 'completed', 'failed'
  final String? receiptData;
  final String? purgeToken;

  PaymentTransaction({
    required this.transactionId,
    required this.productId,
    required this.amount,
    required this.currency,
    required this.status,
    this.receiptData,
    this.purgeToken,
  });

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) {
    return PaymentTransaction(
      transactionId: json['transaction_id'] ?? '',
      productId: json['product_id'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] ?? 'USD',
      status: json['status'] ?? 'initiated',
      receiptData: json['receipt_data'],
      purgeToken: json['purge_token'],
    );
  }
}

class PurgeStage {
  final String label;
  final double progress; // 0.0 - 1.0
  final int delayMs;

  PurgeStage({
    required this.label,
    required this.progress,
    required this.delayMs,
  });

  factory PurgeStage.fromJson(Map<String, dynamic> json) {
    return PurgeStage(
      label: json['label'] ?? '',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      delayMs: (json['delay_ms'] as num?)?.toInt() ?? 0,
    );
  }
}

class PaymentService {
  final String baseUrl;
  final String sessionId;

  // In-App Purchase product IDs (must match Apple's AppStore configuration)
  static const String productStandardPayment = 'echo.phase13.payment.standard';
  static const String productDonateSmall = 'echo.phase13.donate.small';
  static const String productDonateRegular = 'echo.phase13.donate.regular';
  static const String productDonateLarge = 'echo.phase13.donate.large';

  // Product amounts (must match backend validation)
  static const double amountPayment = 2.99;
  static const double amountDonateSmall = 1.99;
  static const double amountDonateRegular = 4.99;
  static const double amountDonateLarge = 9.99;

  // State tracking
  PaymentTransaction? _currentTransaction;
  bool _isPaymentInProgress = false;
  Timer? _paymentTimeout;

  // StoreKit bridge — completes when the purchase stream fires a result
  StreamSubscription<List<PurchaseDetails>>? _iapSubscription;
  Completer<String>? _receiptCompleter;

  static const int paymentTimeoutSeconds = 120; // IAP sheets can take a while

  PaymentService({
    required this.baseUrl,
    required this.sessionId,
  }) {
    _initIap();
  }

  /// Subscribe to the StoreKit purchase stream once for the lifetime of this service.
  void _initIap() {
    _iapSubscription?.cancel();
    _iapSubscription = InAppPurchase.instance.purchaseStream.listen(
      _handlePurchaseUpdate,
      onError: (Object e) {
        _receiptCompleter?.completeError(
          PaymentException('Store error: $e', code: 'STORE_STREAM_ERROR'),
        );
        _receiptCompleter = null;
      },
    );
  }

  /// Called by the StoreKit stream on every transaction update.
  Future<void> _handlePurchaseUpdate(List<PurchaseDetails> updates) async {
    for (final purchase in updates) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // Deliver receipt to the waiting _initiatePurchase call
          final receipt = purchase.verificationData.serverVerificationData;
          _receiptCompleter?.complete(receipt);
          _receiptCompleter = null;
          // Acknowledge with Apple so the transaction closes
          await InAppPurchase.instance.completePurchase(purchase);
          break;

        case PurchaseStatus.error:
          _receiptCompleter?.completeError(
            PaymentException(
              purchase.error?.message ?? 'App Store purchase failed',
              code: purchase.error?.code ?? 'STORE_ERROR',
            ),
          );
          _receiptCompleter = null;
          await InAppPurchase.instance.completePurchase(purchase);
          break;

        case PurchaseStatus.canceled:
          _receiptCompleter?.completeError(
            PaymentException('Purchase cancelled', code: 'CANCELLED'),
          );
          _receiptCompleter = null;
          break;

        case PurchaseStatus.pending:
          // Waiting for parental approval or Ask to Buy — nothing to do yet
          break;
      }
    }
  }

  /// Initiate payment for Phase 13 negotiation ($2.99 to "purge data")
  Future<PaymentTransaction> initiatePayment() async {
    return _initiatePurchase(
      productId: productStandardPayment,
      amount: amountPayment,
    );
  }

  /// Initiate donation ($1.99, $4.99, or $9.99)
  Future<PaymentTransaction> initiateDonation({String amount = 'regular'}) async {
    final productId = {
      'small': productDonateSmall,
      'regular': productDonateRegular,
      'large': productDonateLarge,
    }[amount] ?? productDonateRegular;

    final amountValue = {
      'small': amountDonateSmall,
      'regular': amountDonateRegular,
      'large': amountDonateLarge,
    }[amount] ?? amountDonateRegular;

    return _initiatePurchase(
      productId: productId,
      amount: amountValue,
    );
  }

  /// Initiate in-app purchase (internal)
  Future<PaymentTransaction> _initiatePurchase({
    required String productId,
    required double amount,
  }) async {
    // Prevent duplicate simultaneous payment attempts
    if (_isPaymentInProgress) {
      throw PaymentException(
        'Payment already in progress. Please wait.',
        code: 'DUPLICATE_ATTEMPT',
      );
    }

    _isPaymentInProgress = true;
    _paymentTimeout = Timer(
      Duration(seconds: paymentTimeoutSeconds),
      () {
        _isPaymentInProgress = false;
        throw PaymentException(
          'Payment request timed out. Please try again.',
          code: 'TIMEOUT',
        );
      },
    );

    try {
      // Step 1: Notify backend of payment initiation (fraud check, rate limiting)
      final initiateResp = await http.post(
        Uri.parse('$baseUrl/payment/initiate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'product_id': productId,
          'amount': amount,
          'currency': 'USD',
        }),
      ).timeout(
        Duration(seconds: 10),
        onTimeout: () {
          throw PaymentException(
            'Backend unavailable. Please check connection.',
            code: 'BACKEND_TIMEOUT',
          );
        },
      );

      if (initiateResp.statusCode != 200) {
        final errorBody = jsonDecode(initiateResp.body);
        throw PaymentException(
          errorBody['message'] ?? 'Payment initiation failed',
          code: 'INITIATE_FAILED',
        );
      }

      final initiateData = jsonDecode(initiateResp.body);
      final transactionId = initiateData['transaction_id'] as String?;

      if (transactionId == null) {
        throw PaymentException(
          'No transaction ID returned from backend',
          code: 'NO_TRANSACTION_ID',
        );
      }

      _currentTransaction = PaymentTransaction(
        transactionId: transactionId,
        productId: productId,
        amount: amount,
        currency: 'USD',
        status: 'initiated',
      );

      // Step 2: Show App Store purchase sheet, get Apple receipt
      final receiptData = await _triggerStoreKitPurchase(productId);

      // Step 3: Validate receipt with backend
      final validationResp = await http.post(
        Uri.parse('$baseUrl/payment/validate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'transaction_id': transactionId,
          'receipt_data': receiptData,
          'session_id': sessionId,
          'platform': 'macos',
        }),
      ).timeout(
        Duration(seconds: 10),
        onTimeout: () {
          throw PaymentException(
            'Receipt validation timed out',
            code: 'VALIDATE_TIMEOUT',
          );
        },
      );

      if (validationResp.statusCode != 200) {
        final errorBody = jsonDecode(validationResp.body);
        throw PaymentException(
          errorBody['message'] ?? 'Receipt validation failed',
          code: 'VALIDATE_FAILED',
        );
      }

      final validationData = jsonDecode(validationResp.body);
      final purgeToken = validationData['purge_token'] as String?;

      if (purgeToken == null) {
        throw PaymentException(
          'No purge token returned',
          code: 'NO_PURGE_TOKEN',
        );
      }

      // Update transaction with completion data
      _currentTransaction = PaymentTransaction(
        transactionId: transactionId,
        productId: productId,
        amount: amount,
        currency: 'USD',
        status: 'completed',
        receiptData: receiptData,
        purgeToken: purgeToken,
      );

      return _currentTransaction!;
    } catch (e) {
      _isPaymentInProgress = false;
      _paymentTimeout?.cancel();
      rethrow;
    } finally {
      _paymentTimeout?.cancel();
    }
  }

  /// Trigger the real App Store purchase sheet and return Apple's receipt.
  /// Throws [PaymentException] if the store is unavailable, product not found,
  /// purchase is cancelled, or the IAP sheet times out.
  Future<String> _triggerStoreKitPurchase(String productId) async {
    // Check Store availability (returns false in Simulator without StoreKit config)
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      throw PaymentException(
        'App Store is not available on this device.',
        code: 'STORE_UNAVAILABLE',
      );
    }

    // Load the product from App Store Connect
    final response = await InAppPurchase.instance
        .queryProductDetails({productId})
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw PaymentException(
            'App Store product lookup timed out.',
            code: 'PRODUCT_TIMEOUT',
          ),
        );

    if (response.notFoundIDs.isNotEmpty || response.productDetails.isEmpty) {
      throw PaymentException(
        'Product not found in App Store: $productId. '
        'Ensure the product is approved in App Store Connect.',
        code: 'PRODUCT_NOT_FOUND',
      );
    }

    // Set up a completer that will be resolved by _handlePurchaseUpdate
    if (_receiptCompleter != null && !_receiptCompleter!.isCompleted) {
      _receiptCompleter!.completeError(
        PaymentException('New purchase started', code: 'SUPERSEDED'),
      );
    }
    _receiptCompleter = Completer<String>();

    // Show the App Store purchase sheet
    final param = PurchaseParam(productDetails: response.productDetails.first);
    await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);

    // Wait for the stream to deliver the receipt (user completes / cancels IAP sheet)
    return _receiptCompleter!.future.timeout(
      const Duration(seconds: paymentTimeoutSeconds),
      onTimeout: () {
        _receiptCompleter = null;
        throw PaymentException(
          'App Store purchase timed out. Please try again.',
          code: 'IAP_TIMEOUT',
        );
      },
    );
  }

  /// Get data purge sequence after successful payment
  Future<List<PurgeStage>> getPurgeSequence() async {
    if (_currentTransaction == null || _currentTransaction?.purgeToken == null) {
      throw PaymentException(
        'No valid purchase to purge',
        code: 'NO_PURCHASE',
      );
    }

    final purgeResp = await http.post(
      Uri.parse('$baseUrl/payment/purge'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'purge_token': _currentTransaction!.purgeToken,
        'session_id': sessionId,
      }),
    ).timeout(
      Duration(seconds: 10),
      onTimeout: () {
        throw PaymentException(
          'Purge sequence request timed out',
          code: 'PURGE_TIMEOUT',
        );
      },
    );

    if (purgeResp.statusCode != 200) {
      final errorBody = jsonDecode(purgeResp.body);
      throw PaymentException(
        errorBody['message'] ?? 'Purge sequence failed',
        code: 'PURGE_FAILED',
      );
    }

    final purgeData = jsonDecode(purgeResp.body);
    final stages = (purgeData['stages'] as List?)
        ?.map((s) => PurgeStage.fromJson(s as Map<String, dynamic>))
        .toList() ?? [];

    return stages;
  }

  /// Get transaction history for this session (fraud detection)
  Future<List<Map<String, dynamic>>> getTransactionHistory() async {
    final historyResp = await http.get(
      Uri.parse('$baseUrl/payment/history/$sessionId'),
    ).timeout(
      Duration(seconds: 10),
      onTimeout: () {
        throw PaymentException(
          'History request timed out',
          code: 'HISTORY_TIMEOUT',
        );
      },
    );

    if (historyResp.statusCode != 200) {
      return [];
    }

    final data = jsonDecode(historyResp.body);
    final transactions = (data['transactions'] as List?)
        ?.map((t) => t as Map<String, dynamic>)
        .toList() ?? [];

    return transactions;
  }

  /// Record purchase completion (analytics/state tracking)
  void recordPurchaseComplete({
    String? productId,
    double? amount,
  }) {
    // Log purchase for analytics
    print(
      '[PAYMENT] Purchase completed: '
      'product=$productId, amount=\$$amount, session=$sessionId',
    );
  }

  /// Handle payment failure gracefully
  Future<void> handlePaymentFailure(PaymentException error) async {
    _isPaymentInProgress = false;
    _paymentTimeout?.cancel();

    print('[PAYMENT ERROR] ${error.message} (${error.code})');

    // Fallback strategies:
    // - If network timeout: suggest retry
    // - If fraud blocked: show friendly message
    // - If user cancelled: reset state
  }

  /// Check if safe to retry payment (fraud detection)
  Future<bool> canRetryPayment() async {
    try {
      final history = await getTransactionHistory();
      final recentFailed = history
          .where((t) =>
              t['status'] == 'failed' &&
              (DateTime.now().millisecondsSinceEpoch / 1000 - (t['timestamp'] as num))
                  .abs() <
              3600) // Last hour
          .length;

      return recentFailed < 3; // Allow 3 retries per hour
    } catch (_) {
      return true; // Assume safe if we can't check
    }
  }

  /// Clean up resources
  void dispose() {
    _paymentTimeout?.cancel();
    _iapSubscription?.cancel();
    _isPaymentInProgress = false;
    _receiptCompleter = null;
  }
}
