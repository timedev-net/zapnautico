import 'package:flutter_riverpod/flutter_riverpod.dart';

enum PushNavigationType { queueStatus, muralPost }

class PushNavigationIntent {
  const PushNavigationIntent.queueStatus({
    required this.queueEntryId,
    this.marinaId,
    this.boatId,
  })  : type = PushNavigationType.queueStatus,
        postId = null;

  const PushNavigationIntent.muralPost({
    required this.postId,
    this.marinaId,
  })  : type = PushNavigationType.muralPost,
        queueEntryId = null,
        boatId = null;

  final PushNavigationType type;
  final String? queueEntryId;
  final String? marinaId;
  final String? boatId;
  final String? postId;
}

final pushNavigationIntentProvider =
    StateProvider<PushNavigationIntent?>((_) => null);
