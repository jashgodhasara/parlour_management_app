import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/result.dart';
import '../domain/bill.dart';
import '../domain/billing_repository.dart';

class BillDetailScreen extends StatefulWidget {
  final String billId;

  const BillDetailScreen({
    super.key,
    required this.billId,
  });

  @override
  State<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends State<BillDetailScreen> {
  Bill? _bill;
  bool _loading = true;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadBill();
  }

  Future<void> _loadBill() async {
    final repo = sl<BillingRepository>();
    final result = await repo.getBillById(widget.billId);
    if (!mounted) return;
    switch (result) {
      case Success(value: final bill):
        setState(() {
          _bill = bill;
          _loading = false;
        });
      case Failure(failure: final failure):
        setState(() {
          _error = failure.message;
          _loading = false;
        });
    }
  }

  Future<void> _updatePrice(String serviceId, double newPrice) async {
    setState(() => _saving = true);
    final repo = sl<BillingRepository>();
    final result = await repo.updateLineItemPrice(
      billId: widget.billId,
      serviceId: serviceId,
      newPrice: newPrice,
    );
    if (!mounted) return;
    switch (result) {
      case Success(value: final updatedBill):
        setState(() {
          _bill = updatedBill;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Price updated'),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      case Failure(failure: final failure):
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: ${failure.message}'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  bool get _canEdit => _bill != null && _bill!.status != BillStatus.paid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill Details'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (_bill != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _StatusBadge(status: _bill!.status),
            ),
          if (_bill != null)
            PopupMenuButton<String>(
              tooltip: 'Bill options',
              onSelected: (value) {
                if (value == 'delete') {
                  _deleteBill();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.red),
                      SizedBox(width: 12),
                      Text('Delete'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _bill == null
                  ? const Center(child: Text('Bill not found'))
                  : _BillDetailBody(
                      bill: _bill!,
                      canEdit: _canEdit,
                      onPriceChanged: _updatePrice,
                    ),
    );
  }

  Future<void> _deleteBill() async {
    final bill = _bill;
    if (bill == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete bill?'),
        content: Text('Delete bill ${bill.id}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final result = await sl<BillingRepository>().deleteBill(bill.id);
    if (!mounted) return;

    switch (result) {
      case Success<void>():
        messenger.showSnackBar(
          SnackBar(content: Text('Bill ${bill.id} deleted')),
        );
        router.go('/customers/${bill.customerId}');
      case Failure<void>(failure: final failure):
        messenger.showSnackBar(
          SnackBar(content: Text(failure.message)),
        );
    }
  }
}

// ── Main body ─────────────────────────────────────────────────────────────────

class _BillDetailBody extends StatelessWidget {
  final Bill bill;
  final bool canEdit;
  final Future<void> Function(String serviceId, double newPrice) onPriceChanged;

  const _BillDetailBody({
    required this.bill,
    required this.canEdit,
    required this.onPriceChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasDiscount = bill.discountAmount > 0 && bill.discountType != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date row
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                _formatDate(bill.visitDate),
                style: const TextStyle(color: Colors.grey),
              ),
              if (canEdit) ...[
                const Spacer(),
                Row(
                  children: [
                    const Icon(Icons.edit, size: 14, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      'Tap price to edit',
                      style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Services section
          Text(
            'Services',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ...bill.lineItems.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  return Column(
                    children: [
                      _EditableLineItemRow(
                        item: item,
                        canEdit: canEdit,
                        onPriceChanged: (newPrice) =>
                            onPriceChanged(item.serviceId, newPrice),
                      ),
                      if (index < bill.lineItems.length - 1)
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    ],
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Totals card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _TotalRow(
                    label: 'Subtotal',
                    value: CurrencyFormatter.format(bill.subtotal),
                  ),
                  if (hasDiscount) ...[
                    const SizedBox(height: 8),
                    _TotalRow(
                      label: bill.discountType == DiscountType.percentage
                          ? 'Discount (${bill.discountAmount.toStringAsFixed(0)}%)'
                          : 'Discount',
                      value:
                          '- ${CurrencyFormatter.format(bill.subtotal - bill.total)}',
                      valueColor: Colors.orange,
                    ),
                  ],
                  const Divider(height: 20),
                  _TotalRow(
                    label: 'Total',
                    value: CurrencyFormatter.format(bill.total),
                    isBold: true,
                    valueColor: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Record payment button
          if (bill.status != BillStatus.paid)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () =>
                    context.push('/payments/new?billId=${bill.id}'),
                icon: const Icon(Icons.payment),
                label: const Text('Record Payment'),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }
}

// ── Editable line item row ────────────────────────────────────────────────────

class _EditableLineItemRow extends StatefulWidget {
  final BillLineItem item;
  final bool canEdit;
  final Future<void> Function(double newPrice) onPriceChanged;

  const _EditableLineItemRow({
    required this.item,
    required this.canEdit,
    required this.onPriceChanged,
  });

  @override
  State<_EditableLineItemRow> createState() => _EditableLineItemRowState();
}

class _EditableLineItemRowState extends State<_EditableLineItemRow> {
  late TextEditingController _controller;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.item.servicePrice.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(_EditableLineItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh controller when bill reloads (after save), but not while editing
    if (!_editing && oldWidget.item.servicePrice != widget.item.servicePrice) {
      _controller.text = widget.item.servicePrice.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    final value = double.tryParse(_controller.text);
    if (value == null || value < 0) {
      // Reset to current saved price
      _controller.text = widget.item.servicePrice.toStringAsFixed(2);
      setState(() => _editing = false);
      return;
    }
    // No change — skip the network call
    if (value == widget.item.servicePrice) {
      setState(() => _editing = false);
      return;
    }
    setState(() {
      _editing = false;
      _saving = true;
    });
    await widget.onPriceChanged(value);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Service name
          Expanded(
            child: Text(
              widget.item.serviceName,
              style: const TextStyle(fontSize: 14),
            ),
          ),

          // Price — editable or read-only
          if (widget.canEdit)
            SizedBox(
              width: 100,
              child: TextField(
                controller: _controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: _editing
                      ? Theme.of(context).colorScheme.primary
                      : Colors.green[700],
                ),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  prefixStyle: TextStyle(
                    color: _editing
                        ? Theme.of(context).colorScheme.primary
                        : Colors.green[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: _editing
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade300,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  suffixIcon: _saving
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _editing
                          ? IconButton(
                              icon: const Icon(Icons.check,
                                  size: 16, color: Colors.green),
                              onPressed: _commit,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          : const Icon(Icons.edit,
                              size: 14, color: Colors.orange),
                ),
                onTap: () => setState(() => _editing = true),
                onSubmitted: (_) => _commit(),
                onEditingComplete: _commit,
                onTapOutside: (_) {
                  if (_editing) _commit();
                },
              ),
            )
          else
            // Read-only when bill is paid
            Text(
              CurrencyFormatter.format(widget.item.servicePrice),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green[700],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  const _TotalRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isBold
              ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
              : null,
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isBold ? 18 : 14,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final BillStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      BillStatus.draft => ('Draft', Colors.grey),
      BillStatus.finalised => ('Finalised', Colors.blue),
      BillStatus.paid => ('Paid', Colors.green),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}
