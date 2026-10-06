import 'package:flutter_test/flutter_test.dart';
import 'package:parlour_management_app/main.dart';

void main() {
  test('InvestmentTransaction JSON serialization and calculations', () {
    final now = DateTime.now();
    final credit = InvestmentTransaction(
      id: 'INV-1',
      title: 'Salon Capital',
      amount: 50000,
      type: InvestmentType.credit,
      paymentMode: PaymentMode.cash,
      dateTime: now,
      note: 'Initial deposit',
    );

    final debit = InvestmentTransaction(
      id: 'INV-2',
      title: 'Equipment Buy',
      amount: 12000,
      type: InvestmentType.debit,
      paymentMode: PaymentMode.online,
      dateTime: now,
      note: 'Hair dryer and chairs',
    );

    final creditJson = credit.toJson();
    final parsedCredit = InvestmentTransaction.fromJson(creditJson);
    expect(parsedCredit.id, 'INV-1');
    expect(parsedCredit.title, 'Salon Capital');
    expect(parsedCredit.amount, 50000);
    expect(parsedCredit.type, InvestmentType.credit);
    expect(parsedCredit.paymentMode, PaymentMode.cash);
    expect(parsedCredit.note, 'Initial deposit');

    final debitJson = debit.toJson();
    final parsedDebit = InvestmentTransaction.fromJson(debitJson);
    expect(parsedDebit.id, 'INV-2');
    expect(parsedDebit.amount, 12000);
    expect(parsedDebit.type, InvestmentType.debit);
    expect(parsedDebit.paymentMode, PaymentMode.online);

    final list = [parsedCredit, parsedDebit];
    final totalCredit = list
        .where((e) => e.type == InvestmentType.credit)
        .fold<double>(0, (sum, e) => sum + e.amount);
    final totalDebit = list
        .where((e) => e.type == InvestmentType.debit)
        .fold<double>(0, (sum, e) => sum + e.amount);
    final netBalance = totalCredit - totalDebit;

    expect(totalCredit, 50000);
    expect(totalDebit, 12000);
    expect(netBalance, 38000);
  });
}
