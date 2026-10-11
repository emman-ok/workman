import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/widgets.dart';
import 'package:app/features/milestone_edit/milestone_edit_form.dart';

final milestoneEditProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, id) async {
  final data = await ref.watch(apiClientProvider).get('/milestone_edit/$id');
  return Map<String, dynamic>.from(data as Map);
});

class MilestoneEditPage extends ConsumerWidget {
  const MilestoneEditPage({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = int.tryParse(params['id'] ?? '');
    if (id == null) {
      return AppScaffold(
        title: tr('Edit milestone'),
        body: ErrorView(message: tr('Milestone not found.')),
      );
    }
    final async = ref.watch(milestoneEditProvider(id));
    return AppScaffold(
      title: tr('Edit milestone'),
      body: async.when(
        data: (record) => MilestoneEditForm(id: id, record: record),
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: errorMessage(e),
          onRetry: () => ref.invalidate(milestoneEditProvider(id)),
        ),
      ),
    );
  }
}
