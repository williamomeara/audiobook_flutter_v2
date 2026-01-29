import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/subscription/subscription.dart';
import '../theme/app_colors.dart';

/// A paywall dialog that shows subscription options.
///
/// Show this when a user tries to use a premium feature.
class PaywallDialog extends ConsumerStatefulWidget {
  /// The feature that triggered the paywall.
  final Feature? feature;

  /// Custom title for the paywall.
  final String? title;

  /// Custom description for the paywall.
  final String? description;

  const PaywallDialog({
    super.key,
    this.feature,
    this.title,
    this.description,
  });

  /// Show the paywall dialog.
  static Future<bool?> show(
    BuildContext context, {
    Feature? feature,
    String? title,
    String? description,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PaywallDialog(
        feature: feature,
        title: title,
        description: description,
      ),
    );
  }

  @override
  ConsumerState<PaywallDialog> createState() => _PaywallDialogState();
}

class _PaywallDialogState extends ConsumerState<PaywallDialog> {
  bool _isLoading = false;
  SubscriptionOfferings? _offerings;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    final service = ref.read(subscriptionServiceProvider);
    final offerings = await service.getOfferings();
    if (mounted) {
      setState(() => _offerings = offerings);
    }
  }

  Future<void> _purchaseMonthly() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(subscriptionServiceProvider);
      final success = await service.purchaseMonthly();
      if (mounted) {
        if (success) {
          Navigator.of(context).pop(true);
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _purchaseAnnual() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(subscriptionServiceProvider);
      final success = await service.purchaseAnnual();
      if (mounted) {
        if (success) {
          Navigator.of(context).pop(true);
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(subscriptionServiceProvider);
      final success = await service.restorePurchases();
      if (mounted) {
        if (success) {
          Navigator.of(context).pop(true);
        } else {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No purchases to restore')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String get _title {
    if (widget.title != null) return widget.title!;
    return 'Upgrade to Premium';
  }

  String get _description {
    if (widget.description != null) return widget.description!;
    if (widget.feature != null) {
      switch (widget.feature!) {
        case Feature.multipleBooks:
          return 'Build your complete audiobook library with unlimited books.';
        case Feature.premiumVoices:
          return 'Access 20+ premium AI voices for the perfect listening experience.';
        case Feature.preSynthesis:
          return 'Pre-synthesize chapters for instant playback without waiting.';
        case Feature.unlimitedStorage:
          return 'Cache your entire library with unlimited storage.';
        case Feature.priorityProcessing:
          return 'Get priority processing for faster synthesis.';
      }
    }
    return 'Unlock all premium features for the best audiobook experience.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;

    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              // Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.workspace_premium,
                  size: 48,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                _title,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 8),

              // Description
              Text(
                _description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // Features list
              _buildFeaturesList(colors),
              const SizedBox(height: 24),

              // Pricing options
              if (_offerings != null) ...[
                // Monthly option
                _buildPricingOption(
                  title: 'Monthly',
                  price: _offerings!.monthlyPrice ?? '\$5.00/month',
                  subtitle: '3 months free, then auto-renews',
                  onTap: _isLoading ? null : _purchaseMonthly,
                  isPrimary: false,
                  colors: colors,
                ),
                const SizedBox(height: 12),

                // Annual option (recommended)
                _buildPricingOption(
                  title: 'Annual',
                  price: _offerings!.annualPrice ?? '\$50.00/year',
                  subtitle: 'Save \$10 per year',
                  badge: 'BEST VALUE',
                  onTap: _isLoading ? null : _purchaseAnnual,
                  isPrimary: true,
                  colors: colors,
                ),
              ] else ...[
                const CircularProgressIndicator(),
              ],
              const SizedBox(height: 16),

              // Restore purchases
              TextButton(
                onPressed: _isLoading ? null : _restorePurchases,
                child: Text(
                  'Restore Purchases',
                  style: TextStyle(color: colors.textSecondary),
                ),
              ),
              const SizedBox(height: 8),

              // Terms and privacy
              Text(
                'Cancel anytime. See our Terms of Service and Privacy Policy.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturesList(AppThemeColors colors) {
    final features = [
      'Unlimited books in library',
      '20+ premium AI voices',
      'Pre-synthesis for instant playback',
      'Unlimited cache storage',
      'Priority processing',
    ];

    return Column(
      children: features
          .map((feature) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 20,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      feature,
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.text,
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _buildPricingOption({
    required String title,
    required String price,
    required String subtitle,
    String? badge,
    required VoidCallback? onTap,
    required bool isPrimary,
    required AppThemeColors colors,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isPrimary ? colors.primary : colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPrimary ? colors.primary : colors.border,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isPrimary ? Colors.white : colors.text,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: isPrimary
                              ? Colors.white70
                              : colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  price,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isPrimary ? Colors.white : colors.primary,
                  ),
                ),
              ],
            ),
            if (badge != null)
              Positioned(
                top: -8,
                right: -8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
