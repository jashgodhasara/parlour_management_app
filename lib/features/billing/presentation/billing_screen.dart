import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../services/domain/service.dart';
import '../domain/bill.dart';
import 'billing_cubit.dart';

class BillingScreen extends StatelessWidget {
  final String? customerId;

  const BillingScreen({
    super.key,
    this.customerId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl.get<BillingCubit>(param1: customerId),
      child: const _BillingScreenBody(),
    );
  }
}

// ── Screen shell ──────────────────────────────────────────────────────────────

class _BillingScreenBody extends StatelessWidget {
  const _BillingScreenBody();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BillingCubit, BillingState>(
      listener: (context, state) {
        if (state is BillingStateSaved) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bill created successfully'),
              backgroundColor: Colors.green,
            ),
          );
          context.go('/billing/${state.bill.id}');
        } else if (state is BillingStateError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('New Bill'),
          ),
          body: switch (state) {
            BillingStateInitial() ||
            BillingStateLoading() =>
              const Center(child: CircularProgressIndicator()),
            BillingStateError(message: final msg) =>
              _ErrorView(message: msg),
            BillingStateSaving() => const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Saving bill...'),
                  ],
                ),
              ),
            BillingStateSaved() => const SizedBox.shrink(),
            BillingStateReady() =>
              _BillingForm(state: state as BillingStateReady),
          },
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ── Main form ─────────────────────────────────────────────────────────────────

class _BillingForm extends StatelessWidget {
  final BillingStateReady state;
  const _BillingForm({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── "Select Services" label ──────────────────────────────
                Text(
                  'Select Services',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                ),
                const SizedBox(height: 12),

                // ── Service list (tap to select, price editable inline) ──
                _ServiceChipGrid(state: state),

                // ── Discount ─────────────────────────────────────────────
                if (state.lineItems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _DiscountRow(state: state),
                ],

                const SizedBox(height: 80),
              ],
            ),
          ),
        ),

        // ── Footer ──────────────────────────────────────────────────────
        if (state.lineItems.isNotEmpty) _BillFooter(state: state),
      ],
    );
  }
}

// ── Service chips grid ────────────────────────────────────────────────────────

class _ServiceChipGrid extends StatelessWidget {
  final BillingStateReady state;
  const _ServiceChipGrid({required this.state});

  @override
  Widget build(BuildContext context) {
    final services = state.filteredServices;

    if (services.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('No active services',
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return Column(
      children: services.map((service) {
        final item = state.lineItems
            .where((i) => i.serviceId == service.id)
            .firstOrNull;
        final isSelected = item != null;
        return _ServiceChipRow(
          service: service,
          isSelected: isSelected,
          selectedItem: item,
        );
      }).toList(),
    );
  }
}

/// One row per service — shows chip + price field when selected
class _ServiceChipRow extends StatefulWidget {
  final ParlourService service;
  final bool isSelected;
  final DraftLineItem? selectedItem;

  const _ServiceChipRow({
    required this.service,
    required this.isSelected,
    required this.selectedItem,
  });

  @override
  State<_ServiceChipRow> createState() => _ServiceChipRowState();
}

class _ServiceChipRowState extends State<_ServiceChipRow> {
  late TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(
      text: widget.selectedItem?.customPrice.toStringAsFixed(0) ??
          widget.service.price.toStringAsFixed(0),
    );
  }

  @override
  void didUpdateWidget(_ServiceChipRow old) {
    super.didUpdateWidget(old);
    // When item is newly selected, reset to catalog price
    if (!old.isSelected && widget.isSelected) {
      _priceCtrl.text = widget.service.price.toStringAsFixed(0);
    }
    // When price changes externally (e.g. state rebuild), sync
    if (widget.selectedItem != null &&
        old.selectedItem?.customPrice != widget.selectedItem!.customPrice) {
      _priceCtrl.text =
          widget.selectedItem!.customPrice.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  void _commitPrice() {
    final value = double.tryParse(_priceCtrl.text);
    if (value != null && value >= 0) {
      context
          .read<BillingCubit>()
          .updateLineItemPrice(widget.service.id, value);
    } else {
      _priceCtrl.text = (widget.selectedItem?.customPrice ??
              widget.service.price)
          .toStringAsFixed(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isCustom = widget.selectedItem != null &&
        widget.selectedItem!.customPrice != widget.selectedItem!.catalogPrice;

    return GestureDetector(
      onTap: () {
        if (widget.isSelected) {
          context.read<BillingCubit>().removeService(widget.service.id);
        } else {
          context.read<BillingCubit>().addService(widget.service);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? primary.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isSelected ? primary : Colors.grey.shade300,
            width: widget.isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Checkmark or empty circle
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: widget.isSelected
                  ? Icon(Icons.check_circle,
                      key: const ValueKey('checked'),
                      size: 20,
                      color: primary)
                  : Icon(Icons.radio_button_unchecked,
                      key: const ValueKey('unchecked'),
                      size: 20,
                      color: Colors.grey.shade400),
            ),
            const SizedBox(width: 12),

            // Service name
            Expanded(
              child: Text(
                widget.service.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: widget.isSelected
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color:
                      widget.isSelected ? Colors.black87 : Colors.black54,
                ),
              ),
            ),

            // Price — editable when selected, static when not
            if (widget.isSelected) ...[
              // Editable price field
              GestureDetector(
                onTap: () {}, // prevent parent GestureDetector from firing
                child: SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}')),
                    ],
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isCustom ? primary : Colors.green[700],
                    ),
                    decoration: InputDecoration(
                      prefixText: 'Rs. ',
                      prefixStyle: TextStyle(
                        color: isCustom ? primary : Colors.green[700],
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isCustom
                              ? primary
                              : Colors.grey.shade300,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isCustom
                              ? primary
                              : Colors.grey.shade300,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: primary, width: 2),
                      ),
                    ),
                    onTap: () {
                      if (_priceCtrl.text == '0') {
                        _priceCtrl.clear();
                      }
                    },
                    onSubmitted: (_) => _commitPrice(),
                    onEditingComplete: _commitPrice,
                    onTapOutside: (_) => _commitPrice(),
                  ),
                ),
              ),
            ] else ...[
              // Static price label
              Text(
                'Rs. ${widget.service.price.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Discount row ──────────────────────────────────────────────────────────────

class _DiscountRow extends StatefulWidget {
  final BillingStateReady state;
  const _DiscountRow({required this.state});

  @override
  State<_DiscountRow> createState() => _DiscountRowState();
}

class _DiscountRowState extends State<_DiscountRow> {
  late TextEditingController _ctrl;
  DiscountType? _type;

  @override
  void initState() {
    super.initState();
    _type = widget.state.discountType;
    _ctrl = TextEditingController(
      text: widget.state.discountAmount > 0
          ? widget.state.discountAmount.toStringAsFixed(0)
          : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _apply() {
    final value = double.tryParse(_ctrl.text) ?? 0;
    context.read<BillingCubit>().updateDiscount(value, _type);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.discount_outlined, size: 18, color: Colors.orange),
          const SizedBox(width: 8),
          const Text('Discount',
              style:
                  TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(width: 12),
          DropdownButton<DiscountType?>(
            value: _type,
            isDense: true,
            underline: const SizedBox.shrink(),
            hint: const Text('None', style: TextStyle(fontSize: 13)),
            items: const [
              DropdownMenuItem(value: null, child: Text('None')),
              DropdownMenuItem(
                  value: DiscountType.flat, child: Text('Flat (Rs.)')),
              DropdownMenuItem(
                  value: DiscountType.percentage, child: Text('Percent (%)')),
            ],
            onChanged: (t) {
              setState(() => _type = t);
              if (t == null) {
                _ctrl.clear();
                context.read<BillingCubit>().updateDiscount(0, null);
              }
            },
          ),
          if (_type != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: TextField(
                controller: _ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}')),
                ],
                textAlign: TextAlign.right,
                isDense: true,
                decoration: InputDecoration(
                  suffixText:
                      _type == DiscountType.percentage ? '%' : 'Rs.',
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onSubmitted: (_) => _apply(),
                onTapOutside: (_) => _apply(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _BillFooter extends StatelessWidget {
  final BillingStateReady state;
  const _BillFooter({required this.state});

  @override
  Widget build(BuildContext context) {
    final hasDiscount =
        state.discountAmount > 0 && state.discountType != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Subtotal row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Subtotal',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              Text(
                'Rs. ${state.subtotal.toStringAsFixed(0)}',
                style:
                    TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
            ],
          ),

          // Discount row
          if (hasDiscount) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  state.discountType == DiscountType.percentage
                      ? 'Discount (${state.discountAmount.toStringAsFixed(0)}%)'
                      : 'Discount',
                  style: const TextStyle(
                      color: Colors.orange, fontSize: 13),
                ),
                Text(
                  '- Rs. ${(state.subtotal - state.total).toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: Colors.orange, fontSize: 13),
                ),
              ],
            ),
          ],

          const Divider(height: 16),

          // Total + Save button
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Amount:',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(
                    'Rs. ${state.total.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton(
                onPressed: state.lineItems.isEmpty
                    ? null
                    : () => context.read<BillingCubit>().saveBill(),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Save',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
