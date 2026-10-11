import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/api_client.dart';

final projectDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, id) async {
  ref.watch(dataVersionProvider);
  final data = await ref.watch(apiClientProvider).get('/project_detail/$id');
  return Map<String, dynamic>.from(data as Map);
});
