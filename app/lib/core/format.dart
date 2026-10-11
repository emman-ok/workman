// Owned by AppWand. Each helper accepts null, a String from JSON, a num or a DateTime.
import 'package:intl/intl.dart';

DateTime? _date(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  return DateTime.tryParse(value.toString())?.toLocal();
}

num? _num(dynamic value) {
  if (value == null) return null;
  if (value is num) return value;
  return num.tryParse(value.toString());
}

String formatDate(dynamic value) {
  final date = _date(value);
  return date == null ? '' : DateFormat.yMMMd().format(date);
}

String formatDateTime(dynamic value) {
  final date = _date(value);
  return date == null ? '' : DateFormat.yMMMd().add_jm().format(date);
}

String formatMoney(dynamic value) {
  final number = _num(value);
  return number == null ? '' : NumberFormat.currency(symbol: r'$', decimalDigits: 2).format(number);
}

String formatNumber(dynamic value) {
  final number = _num(value);
  return number == null ? '' : NumberFormat.decimalPattern().format(number);
}
